#!/usr/bin/env python3
"""Local WeChat send bridge: wechat-use-compatible HTTP routes with a pluggable backend.

Compatibility target (public protocol only, no upstream code):
  GET  /health                      -> {"ok":true,"backend":...,"send_ready":bool}
  GET  /resolve?hint=X&limit=N     -> {"candidates":[...]}
  GET  /chats?limit=N              -> {"chats":[...]}
  GET  /contacts?query=X&limit=N   -> {"contacts":[...]}
  GET  /unread                     -> {"unread":[...]}
  GET  /chat/{wxid}                -> {"messages":[...]}
  GET  /chat/{wxid}/history        -> {"messages":[...]}
  GET  /messages/stream?since=TS   -> SSE (fromSelf filtering)
  POST /send {wxid,text,mention?,request_id?} -> receipt for one submission
  GET  /receipt?request_id=X      -> original receipt, no send

Backend is selected by WECHAT_BRIDGE_BACKEND:
  "noop"   (default) - no GUI, no send; returns status_unknown. Safe for wiring tests.
  "exec"            - one command per operation, JSON on stdin, JSON on stdout.
  "desktop"         - authenticated local filehelper text, photos and visible history.
  "upstream"        - proxy supported routes to an already-running wechat-use bridge.

Only loopback is bound (127.0.0.1). Set WECHAT_BRIDGE_BEARER to require auth on
non-/health routes. Never log message text, wxid or tokens.
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import http.client
from functools import lru_cache
from importlib.util import module_from_spec, spec_from_file_location
import json
import os
import re
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DEFAULT_PORT = 18400
DEFAULT_UPSTREAM = "http://127.0.0.1:18400"
MAX_BODY = 1 << 20
MAX_TEXT = 8000
SEND_STATUSES = {"delivered", "submitted_unconfirmed", "status_unknown", "failed"}


class RequestConflict(ValueError):
    pass


def _check_request_id(rid) -> None:
    if not isinstance(rid, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", rid):
        raise ValueError("request_id must contain 1..128 ASCII letters, digits, underscores or hyphens")


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def _backend() -> str:
    return _env("WECHAT_BRIDGE_BACKEND", "noop").lower()


def _bearer() -> str:
    return _env("WECHAT_BRIDGE_BEARER")


class UnsupportedOperation(ValueError):
    pass


class DesktopUnavailable(RuntimeError):
    pass


@lru_cache(maxsize=1)
def _archive_module():
    # Load the bundled sibling by path, including when this CLI runs with python -I.
    spec = spec_from_file_location("wechat_message_archive", Path(__file__).with_name("message_archive.py"))
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _archive_read(op: str, query: str) -> dict:
    keys = {"history": {"chat", "since", "until", "limit"},
            "search": {"chat", "since", "until", "limit", "query"},
            "stats": {"chat", "since", "until", "limit"},
            "export": {"chat", "since", "until", "limit", "cursor", "format"},
            "baseline": set(), "events": {"after", "limit", "chat", "exclude_self"}}
    if op not in keys:
        raise UnsupportedOperation("unknown archive read operation")
    args = urllib.parse.parse_qs(query, keep_blank_values=True, max_num_fields=len(keys[op]), errors="strict")
    if not args.keys() <= keys[op] or any(len(values) != 1 for values in args.values()):
        raise ValueError("invalid archive query parameters")
    args = {key: values[0] for key, values in args.items()}
    required = {"history": "chat", "search": "query", "events": "after"}.get(op)
    if required is not None and not args.get(required):
        raise ValueError(f"{required} is required")
    exclude_self = args.get("exclude_self", "false")
    if exclude_self not in {"true", "false"}:
        raise ValueError("exclude_self must be true or false")
    request = argparse.Namespace(op=op, chat=args.get("chat"), query=args.get("query"), after=args.get("after"),
                                 exclude_self=exclude_self == "true", cursor=args.get("cursor"), format=args.get("format", "json"),
                                 since=int(args["since"]) if "since" in args else None,
                                 until=int(args["until"]) if "until" in args else None, limit=int(args.get("limit", "20")))
    archive = _archive_module()
    try:
        return archive.query_archive(Path(_env("WECHAT_BRIDGE_ARCHIVE_DB")), request)
    except (archive.ArchiveUnavailable, OSError, sqlite3.Error) as exc:
        raise DesktopUnavailable("imported archive unavailable") from exc


def _desktop_bin() -> str:
    binary = _env("WECHAT_BRIDGE_DESKTOP_BIN")
    if not Path(binary).is_absolute() or not Path(binary).is_file() or not os.access(binary, os.X_OK):
        raise ValueError("desktop backend requires WECHAT_BRIDGE_DESKTOP_BIN set to a trusted absolute executable path")
    return binary


def _call_desktop(payload: dict) -> dict:
    # Do not kill a send during clipboard restoration or after its one submission.
    timeout = None if payload["op"] == "send" else 25
    env = {**os.environ, "WECHAT_DESKTOP_BUNDLE_ID": os.environ.get("WECHAT_DESKTOP_BUNDLE_ID", "com.tencent.xinWeChat")}
    proc = subprocess.run([_desktop_bin()], input=json.dumps(payload, ensure_ascii=True).encode(),
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=timeout, env=env)
    result = json.loads(proc.stdout)
    codes = {"ok": 0, "target_matched": 0, "not_found": 0, "submitted_unconfirmed": 0,
             "failed": 1, "status_unknown": 2}
    status = result.get("status") if isinstance(result, dict) else None
    if (not isinstance(status, str) or codes.get(status) != proc.returncode
            or ("request_id" in payload and result.get("request_id") != payload["request_id"])):
        raise RuntimeError("desktop sender returned an invalid result")
    return result


def _desktop_photos(paths) -> list[str]:
    root = Path(_env("WECHAT_BRIDGE_DESKTOP_PHOTO_DIR"))
    if not root.is_absolute() or not root.is_dir():
        raise UnsupportedOperation("desktop photos require a configured absolute photo directory")
    if (not isinstance(paths, list) or not 1 <= len(paths) <= 4
            or not all(isinstance(p, str) and Path(p).is_absolute() for p in paths)):
        raise ValueError("photos must contain 1–4 absolute JPEG paths")
    root = root.resolve()
    try:
        files = [Path(p).resolve(strict=True) for p in paths]
    except (OSError, RuntimeError, ValueError) as exc:
        raise ValueError("photo path unavailable") from exc
    if not all(root in p.parents for p in files):
        raise ValueError("photos must be inside the configured directory")
    return [str(p) for p in files]


def _exec_cmd(op: str) -> str:
    return _env("WECHAT_BRIDGE_EXEC_" + op.upper(), _env("WECHAT_BRIDGE_EXEC"))


def _call_exec(op: str, payload: dict) -> dict:
    cmd = _exec_cmd(op)
    if not cmd:
        raise RuntimeError(f"no executor for {op}; set WECHAT_BRIDGE_EXEC or WECHAT_BRIDGE_EXEC_{op.upper()}")
    proc = subprocess.run(
        cmd, shell=True, input=json.dumps({"op": op, **payload}, ensure_ascii=False),
        capture_output=True, text=True, timeout=float(_env("WECHAT_BRIDGE_EXEC_TIMEOUT", "30")),
    )
    if proc.returncode != 0:
        raise RuntimeError(f"executor failed ({proc.returncode}) for {op}")
    out = (proc.stdout or "").strip()
    if not out:
        if op == "send":
            raise RuntimeError("send executor returned no receipt")
        return {"ok": True}
    data = json.loads(out)
    if not isinstance(data, dict):
        raise RuntimeError("executor must print a JSON object")
    return data


class UpstreamUnavailable(RuntimeError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Never forward an upstream credential or replay a POST on redirect.


def _loopback_origin(base: str) -> tuple[str, int]:
    base = base.rstrip("/")
    parsed = urllib.parse.urlsplit(base)
    if (parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}
            or parsed.username is not None or parsed.path or "?" in base or "#" in base):
        raise ValueError("bridge URL must be a loopback HTTP origin")
    port = parsed.port if parsed.port is not None else 80
    if port == 0:
        raise ValueError("bridge port must be nonzero")
    return base, port


def _upstream_origin() -> tuple[str, int]:
    return _loopback_origin(_env("WECHAT_BRIDGE_UPSTREAM", DEFAULT_UPSTREAM))


def _open_upstream(method: str, path: str, body: bytes | None, headers: dict):
    base, _ = _upstream_origin()
    headers = dict(headers)
    token = _env("WECHAT_BRIDGE_UPSTREAM_TOKEN")
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(base + path, data=body, method=method, headers=headers)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        return opener.open(req, timeout=30)
    except urllib.error.HTTPError as exc:
        exc.close()
        if method == "GET" and exc.code == 402:
            raise UpstreamUnavailable("local upstream requires an active subscription") from exc
        if method == "GET" and exc.code in (401, 403):
            raise UpstreamUnavailable("local upstream denied access; check its authorization and activation") from exc
        raise


def _proxy(method: str, path: str, body: bytes | None, headers: dict) -> tuple[int, bytes]:
    with _open_upstream(method, path, body, headers) as resp:
        return resp.status, resp.read()


def _sse_frames(source, include_self: bool):
    """Forward bounded SSE frames; do not treat partial frames as new messages."""
    def own(row):
        return row.get("fromSelf") is True or row.get("sender_is_self") is True

    frame, data = [], []
    size = 0
    while line := source.readline(MAX_BODY + 1):
        size += len(line)
        if size > MAX_BODY:
            raise ValueError("upstream SSE frame too large")
        frame.append(line)
        content = line.rstrip(b"\r\n")
        if content.startswith(b"data:"):
            data.append(content[5:].removeprefix(b" "))
        elif not content:
            if data:
                message = json.loads(b"\n".join(data))
                if not isinstance(message, dict):
                    raise ValueError("upstream SSE data must be a JSON object")
                rows = message.get("rows")
                if isinstance(rows, list):
                    if any(not isinstance(row, dict) for row in rows):
                        raise ValueError("upstream SSE batch rows must be JSON objects")
                    if not include_self:
                        filtered = [row for row in rows if not own(row)]
                        if len(filtered) != len(rows):
                            # Preserve bridge metadata and SSE IDs, even when every row is filtered.
                            message["rows"] = filtered
                            payload = json.dumps(message, separators=(",", ":")).encode("ascii")
                            start = next(i for i, field in enumerate(frame) if field.startswith(b"data:"))
                            newline = b"\r\n" if frame[start].endswith(b"\r\n") else b"\n"
                            frame[start] = b"data: " + payload + newline
                            frame[start + 1:] = [field for field in frame[start + 1:] if not field.startswith(b"data:")]
                            if sum(map(len, frame)) > MAX_BODY:
                                raise ValueError("filtered SSE frame too large")
                    yield b"".join(frame)
                elif include_self or not own(message):
                    yield b"".join(frame)
            elif frame[0].startswith(b":"):
                yield b"".join(frame)
            frame.clear()
            data.clear()
            size = 0


class Bridge:
    """All state lives here; the handler is stateless per request."""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        # shortcut: process-local receipts, use durable storage before promising restart-safe deduplication.
        self.requests: dict[str, tuple[bytes, dict]] = {}

    def health(self) -> dict:
        b = _backend()
        if b == "upstream":
            try:
                status, raw = _proxy("GET", "/health", None, {})
                data = json.loads(raw)
                data["proxy"] = "upstream"
                return data
            except Exception as exc:  # noqa: BLE001 - health is diagnostic
                return {"ok": False, "backend": b, "error": type(exc).__name__}
        if b == "desktop":
            # Public health must not read the desktop or claim the target is ready.
            return {"ok": True, "backend": b, "send_ready": False, "readiness_checked": False}
        return {"ok": True, "backend": b, "send_ready": b == "exec" and bool(_exec_cmd("send")),
                "note": "noop backend never sends; this is a protocol harness"}

    def _query(self, op: str, payload: dict) -> dict:
        b = _backend()
        if b == "desktop":
            if op in {"chats", "resolve"}:
                if not 1 <= payload["limit"] <= 100:
                    raise ValueError("limit must be an integer from 1 to 100")
                if op == "resolve" and (not payload["hint"].strip()
                        or len(payload["hint"].encode("utf-16-le")) > 4000):
                    raise ValueError("hint must be a nonempty name up to 2000 UTF-16 code units")
                result = _call_desktop({"op": op, **payload})
                if result["status"] != "ok":
                    raise DesktopUnavailable("session list is not readable in the background")
                return result
            if payload.get("wxid") != "filehelper" or op not in {"chat", "chat_history", "search", "stats", "export"}:
                raise UnsupportedOperation("desktop exposes only visible filehelper history, search, stats and export")
            if payload.get("since") or payload.get("until"):
                raise UnsupportedOperation("time filters require a complete history backend")
            request = {k: v for k, v in payload.items() if k not in {"wxid", "since", "until"}}
            if not 1 <= request["limit"] <= 100:
                raise ValueError("limit must be an integer from 1 to 100")
            if op == "search" and not request["query"].strip():
                raise ValueError("query is required")
            if op == "export" and request["format"] not in {"json", "markdown", "html", "csv"}:
                raise ValueError("format must be json, markdown, html or csv")
            result = _call_desktop({**request, "op": "history" if op in {"chat", "chat_history"} else op,
                                    "recipient": "filehelper"})
            if result["status"] != "ok":
                raise DesktopUnavailable("filehelper is not readable in the background")
            return result
        if b == "noop":
            return {"ok": True, "items": [], "backend": "noop"}
        if b == "exec":
            return _call_exec(op, payload)
        if b == "upstream":
            qs = urllib.parse.urlencode({k: v for k, v in payload.items() if k != "wxid" and v not in (None, "")})
            wxid = urllib.parse.quote(str(payload.get("wxid", "")), safe="")
            path = {"chats": "/chats", "unread": "/unread", "contacts": "/contacts",
                    "resolve": "/resolve", "chat": "/chat/" + wxid,
                    "chat_history": "/chat/" + wxid + "/history"}[op]
            if qs:
                path += "?" + qs
            status, raw = _proxy("GET", path, None, {})
            return json.loads(raw)
        raise RuntimeError(f"unknown backend: {b}")

    def send(self, payload: dict) -> dict:
        desktop = _backend() == "desktop"
        if desktop and _env("WECHAT_DESKTOP_BUNDLE_ID") == "com.tencent.xinWeChat420Test":
            raise UnsupportedOperation("the 4.2.0 test clone is read-only")
        wxid = payload.get("wxid")
        if not isinstance(wxid, str) or not wxid.strip():
            raise ValueError("wxid is required")
        wxid = wxid.strip()
        if desktop and (wxid != "filehelper" or "mention" in payload):
            raise UnsupportedOperation("desktop sends only to filehelper and does not support mentions")
        if desktop and not payload.keys() <= {"wxid", "text", "photos", "request_id"}:
            raise ValueError("unsupported desktop send parameter")
        if "photos" in payload:
            if not desktop:
                raise UnsupportedOperation("only the desktop backend accepts photo paths")
            if "text" in payload:
                raise ValueError("provide exactly one of text or photos")
            message = {"wxid": wxid, "photos": _desktop_photos(payload["photos"])}
        else:
            text = payload.get("text")
            if not isinstance(text, str) or not text:
                raise ValueError("text is required")
            if len(text) > MAX_TEXT:
                raise ValueError(f"text exceeds {MAX_TEXT} chars")
            message = {"wxid": wxid, "text": text}
        if "mention" in payload:
            if not isinstance(payload["mention"], (str, list, dict)):
                raise ValueError("mention must be a string, list or object")
            message["mention"] = payload["mention"]

        rid = payload.get("request_id", uuid.uuid4().hex)
        _check_request_id(rid)
        if desktop:
            content = {k: v for k, v in message.items() if k != "wxid"}
            try:
                result = _call_desktop({"op": "send", "request_id": rid, "recipient": wxid, **content})
                if result["status"] not in SEND_STATUSES - {"delivered"}:
                    raise RuntimeError("desktop sender returned no send receipt")
            except Exception as exc:
                return {"status": "status_unknown", "request_id": rid, "error": type(exc).__name__,
                        "diagnostic": "desktop outcome unknown; query the original receipt, do not retry"}
            if result.get("error_code") == "request_conflict":
                raise RequestConflict("request_id already used for a different payload")
            return result
        try:
            body = json.dumps(message, ensure_ascii=False, sort_keys=True).encode()
        except UnicodeEncodeError as exc:
            raise ValueError("send payload contains invalid Unicode") from exc
        fingerprint = hashlib.sha256(body).digest()
        row = {"request_id": rid, "ts": int(time.time()), "status": "pending",
               "diagnostic": "request already registered; check its receipt"}
        with self.lock:
            existing = self.requests.get(rid)
            if existing is not None:
                if existing[0] != fingerprint:
                    raise RequestConflict("request_id already used for a different payload")
                return dict(existing[1])
            self.requests[rid] = (fingerprint, row)

        try:
            result = self._send_once(message, body)
        except Exception as exc:  # A backend may have sent before its response failed.
            result = {"status": "status_unknown", "error": type(exc).__name__,
                      "diagnostic": "send outcome unknown; do not automatically retry"}
        with self.lock:
            row.update(result)
            return dict(row)

    def _send_once(self, message: dict, body: bytes) -> dict:
        b = _backend()
        if b == "noop":
            return {"status": "status_unknown",
                    "diagnostic": "noop backend: request accepted but no message was sent"}
        if b == "exec":
            data = _call_exec("send", {"mention": None, **message})
        elif b == "upstream":
            _, raw = _proxy("POST", "/send", body,
                            {"Content-Type": "application/json", "Accept": "application/json"})
            data = json.loads(raw)
        else:
            raise RuntimeError(f"unknown backend: {b}")
        status = data.get("status") if isinstance(data, dict) else None
        if not isinstance(status, str) or status not in SEND_STATUSES:
            raise RuntimeError("backend returned no recognized send status")
        result = {"status": status, "diagnostic": str(data.get("diagnostic", ""))[:500]}
        if isinstance(data.get("request_id"), str) and data["request_id"]:
            result["native_request_id"] = data["request_id"]
        if b == "upstream":
            result["proxy"] = "upstream"
        return result

    def receipt(self, rid: str) -> dict:
        _check_request_id(rid)
        if _backend() == "desktop":
            if _env("WECHAT_DESKTOP_BUNDLE_ID") == "com.tencent.xinWeChat420Test":
                raise UnsupportedOperation("the 4.2.0 test clone does not expose old receipts")
            result = _call_desktop({"op": "receipt", "request_id": rid})
            if result["status"] != "not_found" and (
                result["status"] not in SEND_STATUSES - {"delivered"} or result.get("receipt_recorded") is not True
            ):
                raise RuntimeError("desktop receipt unavailable")
            return result
        with self.lock:
            existing = self.requests.get(rid)
            if existing is not None:
                return dict(existing[1])
        return {"request_id": rid, "status": "not_found"}


BRIDGE = Bridge()


class Handler(BaseHTTPRequestHandler):
    server_version = "wechat-bridge/1.0"

    def log_request(self, code="-", size="-") -> None:
        # Chat IDs and search terms can occur in paths and queries.
        self.log_message("%s %s", self.command, code)

    def log_error(self, fmt, *args) -> None:
        # Malformed request diagnostics from BaseHTTPRequestHandler can contain raw input.
        self.log_message("request or stream error")

    def _reply(self, code: int, data: dict | bytes, content_type: str = "application/json") -> None:
        raw = data if isinstance(data, bytes) else json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(raw)

    def _auth_ok(self) -> bool:
        token = _bearer()
        if self.path.split("?", 1)[0] == "/health":
            return True
        if not token:
            return _backend() != "desktop"
        return hmac.compare_digest(self.headers.get("Authorization", "").encode(), ("Bearer " + token).encode())

    def _read_body(self) -> bytes:
        n = int(self.headers.get("Content-Length", "0"))
        if n <= 0 or n > MAX_BODY:
            raise ValueError("invalid Content-Length")
        raw = self.rfile.read(n)
        if len(raw) != n:
            raise ValueError("incomplete request body")
        return raw

    def do_GET(self) -> None:  # noqa: N802 - stdlib
        if not self._auth_ok():
            return self._reply(401, {"error": "unauthorized"})
        parsed = urllib.parse.urlparse(self.path)
        path, qs = parsed.path, urllib.parse.parse_qs(parsed.query)
        try:
            if path == "/health":
                return self._reply(200, BRIDGE.health())
            if path.startswith("/archive/"):
                if not _env("WECHAT_BRIDGE_ARCHIVE_DB"):
                    raise UnsupportedOperation("imported archive not configured")
                if not _bearer():
                    return self._reply(401, {"error": "archive requires bearer authentication"})
                if path == "/archive/events/stream":
                    return self._archive_stream(parsed.query)
                return self._reply(200, _archive_read(path.removeprefix("/archive/"), parsed.query))
            if path == "/messages/stream":
                since = int(qs.get("since", [str(int(time.time()))])[0])
                if since < 0:
                    raise ValueError("since must be non-negative")
                include_self = qs.get("includeSelf", ["false"])[0].lower() == "true"
                return self._sse(since, include_self)
            if path == "/chats":
                return self._reply(200, BRIDGE._query("chats", {"limit": int(qs.get("limit", ["20"])[0])}))
            if path == "/unread":
                return self._reply(200, BRIDGE._query("unread", {}))
            if path == "/contacts":
                return self._reply(200, BRIDGE._query("contacts", {
                    "query": qs.get("query", [""])[0], "limit": int(qs.get("limit", ["20"])[0])}))
            if path == "/resolve":
                return self._reply(200, BRIDGE._query("resolve", {
                    "hint": qs.get("hint", [""])[0], "limit": int(qs.get("limit", ["10"])[0])}))
            if path.startswith("/chat/"):
                rest = path[len("/chat/"):]
                if rest.endswith("/history"):
                    return self._reply(200, BRIDGE._query("chat_history", {
                        "wxid": urllib.parse.unquote(rest[:-len("/history")]), "since": qs.get("since", [""])[0],
                        "until": qs.get("until", [""])[0], "limit": int(qs.get("limit", ["20"])[0])}))
                return self._reply(200, BRIDGE._query("chat", {
                    "wxid": urllib.parse.unquote(rest), "limit": int(qs.get("limit", ["20"])[0])}))
            if path in {"/desktop/contact-labels", "/desktop/moments-labels"}:
                if _backend() != "desktop":
                    raise UnsupportedOperation("this route requires the desktop backend")
                if not _bearer():
                    return self._reply(401, {"error": "desktop labels require bearer authentication"})
                args = urllib.parse.parse_qs(parsed.query, keep_blank_values=True, max_num_fields=2, errors="strict")
                if not args.keys() <= {"query", "limit"} or any(len(v) != 1 for v in args.values()):
                    raise ValueError("invalid label parameters")
                limit, query = int(args.get("limit", ["20"])[0]), args.get("query", [""])[0]
                if not 1 <= limit <= 100 or len(query.encode("utf-16-le")) > 4000 or (query and not query.strip()):
                    raise ValueError("invalid label limit or query")
                op = path.removeprefix("/desktop/").replace("-", "_")
                result = _call_desktop({"op": op, "query": query, "limit": limit})
                if result["status"] != "ok":
                    raise DesktopUnavailable("requested list is not readable in the background")
                return self._reply(200, result)
            if path == "/desktop/unread-badge":
                if _backend() != "desktop":
                    raise UnsupportedOperation("this route requires the desktop backend")
                if parsed.query:
                    raise ValueError("unread badge takes no parameters")
                result = _call_desktop({"op": "unread_badge"})
                if result["status"] != "ok":
                    raise DesktopUnavailable("chat sidebar badge is not readable in the background")
                return self._reply(200, result)
            if path == "/desktop/readiness":
                if _backend() != "desktop":
                    raise UnsupportedOperation("this route requires the desktop backend")
                if parsed.query:
                    raise ValueError("readiness takes no parameters")
                result = _call_desktop({"op": "readiness"})
                if result.get("status") != "ok":
                    raise DesktopUnavailable("desktop readiness unavailable")
                return self._reply(200, result)
            if path == "/desktop/probe" and _backend() == "desktop":
                result = _call_desktop({"op": "probe"})
                return self._reply(200 if result["status"] == "target_matched" else 503, result)
            if path in {"/desktop/search", "/desktop/stats", "/desktop/export"}:
                if _backend() != "desktop":
                    raise UnsupportedOperation("this route requires the desktop backend")
                op = path.rsplit("/", 1)[1]
                args = {"wxid": "filehelper", "limit": int(qs.get("limit", ["20"])[0])}
                if op == "search":
                    args["query"] = qs.get("query", [""])[0]
                if op == "export":
                    args["format"] = qs.get("format", ["json"])[0]
                return self._reply(200, BRIDGE._query(op, args))
            if path == "/image":
                return self._image(parsed.query)
            if path == "/receipt":
                return self._reply(200, BRIDGE.receipt(qs.get("request_id", [""])[0]))
            return self._reply(404, {"error": "not found"})
        except UnsupportedOperation as exc:
            return self._reply(501, {"error": str(exc)})
        except (DesktopUnavailable, UpstreamUnavailable) as exc:
            return self._reply(503, {"error": str(exc)})
        except (ValueError, KeyError) as exc:
            return self._reply(400, {"error": str(exc)})
        except Exception as exc:  # noqa: BLE001 - surface class only, never text
            return self._reply(502, {"error": type(exc).__name__})

    def _image(self, query: str) -> None:
        if _backend() != "upstream":
            return self._reply(501, {"error": "this backend does not provide image retrieval"})
        if not query or len(query) > 8192:
            raise ValueError("an upstream image reference is required")
        limit = 64 * 1024 * 1024
        with _open_upstream("GET", "/image?" + query, None,
                            {"Accept": "image/png,image/jpeg,image/gif,image/webp"}) as source:
            mime = source.headers.get_content_type()
            if source.status != 200 or mime not in {"image/png", "image/jpeg", "image/gif", "image/webp"}:
                return self._reply(502, {"error": "upstream did not return a supported image"})
            raw = source.read(limit + 1)
            if not raw or len(raw) > limit:
                return self._reply(502, {"error": "upstream image is empty or exceeds 64 MiB"})
        return self._reply(200, raw, mime)

    def _archive_stream(self, query: str) -> None:
        # One bounded long poll, then one batch. No database handle is held while waiting.
        deadline = time.monotonic() + 5
        while True:
            batch = _archive_read("events", query)
            remaining = deadline - time.monotonic()
            if batch["items"] or remaining <= 0:
                break
            time.sleep(min(0.25, remaining))
        data = json.dumps(batch, ensure_ascii=True).encode("ascii")
        return self._reply(200, b"event: archive_batch\ndata: " + data + b"\n\n", "text/event-stream")

    def _sse(self, since: int, include_self: bool) -> None:
        backend = _backend()
        if backend == "noop":
            return self._reply(200, b": connected\n\n", "text/event-stream")
        if backend != "upstream":
            return self._reply(501, {"error": "this backend has no message stream"})
        query = urllib.parse.urlencode({"since": since})
        with _open_upstream("GET", "/messages/stream?" + query, None,
                            {"Accept": "text/event-stream"}) as source:
            if source.status != 200 or source.headers.get_content_type() != "text/event-stream":
                return self._reply(502, {"error": "upstream did not return an SSE stream"})
            try:
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "close")
                self.end_headers()
                for frame in _sse_frames(source, include_self):
                    self.wfile.write(frame)
                    self.wfile.flush()
            except (OSError, ValueError, http.client.HTTPException) as exc:
                # Already streaming: close the connection, never append an HTTP error to SSE bytes.
                self.log_error("SSE connection closed (%s)", type(exc).__name__)
            finally:
                self.close_connection = True

    def do_POST(self) -> None:  # noqa: N802 - stdlib
        if not self._auth_ok():
            return self._reply(401, {"error": "unauthorized"})
        if self.path.split("?", 1)[0] != "/send":
            return self._reply(404, {"error": "not found"})
        try:
            payload = json.loads(self._read_body())
            if not isinstance(payload, dict):
                raise ValueError("body must be a JSON object")
            result = BRIDGE.send(payload)
        except RequestConflict as exc:
            return self._reply(409, {"error": str(exc)})
        except UnsupportedOperation as exc:
            return self._reply(501, {"error": str(exc)})
        except ValueError as exc:
            return self._reply(400, {"error": str(exc)})
        else:
            return self._reply(502 if "error" in result else 200, result)


def self_test() -> None:
    """Protocol-level checks for all four backends; no GUI, no network, no real send."""
    from concurrent.futures import ThreadPoolExecutor
    from unittest.mock import patch

    def run_case(backend: str, env: dict, checks) -> int:
        saved = {k: os.environ.get(k) for k in list(env) + ["WECHAT_BRIDGE_BACKEND", "WECHAT_BRIDGE_BEARER"]}
        try:
            for k in list(env) + ["WECHAT_BRIDGE_BACKEND", "WECHAT_BRIDGE_BEARER"]:
                os.environ.pop(k, None)
            os.environ["WECHAT_BRIDGE_BACKEND"] = backend
            for k, v in env.items():
                os.environ[k] = v
            srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            t = threading.Thread(target=srv.serve_forever, daemon=True)
            t.start()
            port = srv.server_address[1]

            def req(method: str, path: str, body: dict | None = None, token: str = "") -> tuple[int, dict | bytes]:
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                try:
                    headers = {"Content-Type": "application/json"}
                    if token:
                        headers["Authorization"] = "Bearer " + token
                    raw = json.dumps(body).encode() if body is not None else None
                    conn.request(method, path, raw, headers)
                    r = conn.getresponse()
                    data = r.read()
                    mime = r.headers.get_content_type()
                    return r.status, data if mime == "text/event-stream" or mime.startswith("image/") else json.loads(data)
                finally:
                    conn.close()

            try:
                n = checks(req)
            finally:
                srv.shutdown()
                t.join(timeout=2)
                srv.server_close()
        finally:
            for k, v in saved.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
        return n

    def common(req) -> int:
        code, h = req("GET", "/health")
        assert code == 200 and h["ok"] is True, h
        code, r = req("POST", "/send", {"wxid": "", "text": "x"})
        assert code == 400, r
        code, r = req("POST", "/send", {"wxid": "a", "text": ""})
        assert code == 400, r
        code, r = req("POST", "/send", {"wxid": "a", "text": "x" * (MAX_TEXT + 1)})
        assert code == 400, r
        code, r = req("POST", "/send", {"wxid": "a", "text": "x", "mention": 1})
        assert code == 400, r
        code, r = req("GET", "/resolve?hint=x")
        assert code == 200 and "items" in r, r
        code, r = req("GET", "/chat/filehelper")
        assert code == 200 and "items" in r, r
        code, r = req("GET", "/receipt?request_id=none")
        assert code == 200 and r["status"] == "not_found", r
        return 8

    def noop_checks(req) -> int:
        n = common(req)
        code, h = req("GET", "/health")
        assert h["send_ready"] is False, h
        code, r = req("POST", "/send", {"wxid": "filehelper", "text": "hello"})
        assert code == 200 and r["status"] == "status_unknown" and r["request_id"], r
        return n + 2

    def auth_checks(req) -> int:
        code, h = req("GET", "/health")
        assert code == 200, h  # /health never requires auth
        code, r = req("GET", "/resolve?hint=x")
        assert code == 401, r
        code, r = req("GET", "/resolve?hint=x", token="secret")
        assert code == 200, r
        code, r = req("POST", "/send", {"wxid": "a", "text": "x"})
        assert code == 401, r
        code, r = req("POST", "/send", {"wxid": "a", "text": "x"}, token="secret")
        assert code == 200 and r["status"] == "status_unknown", r
        return 5

    def exec_checks(req) -> int:
        code, h = req("GET", "/health")
        assert h["send_ready"] is True, h
        code, r = req("POST", "/send", {"wxid": "filehelper", "text": "hello"})
        assert code == 200 and r["status"] == "delivered", r
        assert r["request_id"] and r["native_request_id"] == "native-test-receipt", r
        code, receipt = req("GET", "/receipt?request_id=" + r["request_id"])
        assert code == 200 and receipt["native_request_id"] == "native-test-receipt", receipt
        return 3

    def receipt_checks(req) -> int:
        payload = {"wxid": "filehelper", "text": "测试", "request_id": "receipt-test"}
        entered = threading.Event()
        release = threading.Event()

        def transport(*args):
            entered.set()
            if not release.wait(4):
                raise RuntimeError("test did not release the backend")
            raise TimeoutError("simulated lost reply")

        with patch(__name__ + "._proxy", side_effect=transport) as backend, ThreadPoolExecutor(1) as pool:
            first = pool.submit(req, "POST", "/send", payload)
            try:
                assert entered.wait(2), "send did not reach backend"
                code, receipt = req("GET", "/receipt?request_id=receipt-test")
                assert code == 200 and receipt["status"] == "pending", receipt
                assert req("POST", "/send", payload) == (200, receipt)
                code, _ = req("POST", "/send", {**payload, "text": "different"})
                assert code == 409
            finally:
                release.set()
            code, result = first.result(timeout=5)
            assert code == 502 and result["status"] == "status_unknown", result
            assert result["request_id"] == "receipt-test", result
            assert req("GET", "/receipt?request_id=receipt-test") == (200, result)
            assert req("POST", "/send", payload) == (502, result)
            backend.assert_called_once()
        code, _ = req("POST", "/send", {**payload, "request_id": "bad id"})
        assert code == 400
        return 8

    def upstream_checks(req) -> int:
        with patch(__name__ + "._proxy", return_value=(200, b'{"status":"submitted_unconfirmed","request_id":"upstream-id"}')) as backend:
            code, result = req("POST", "/send", {"wxid": "filehelper", "text": "test", "request_id": "local-id"})
            assert code == 200 and result["status"] == "submitted_unconfirmed", result
            assert result["request_id"] == "local-id" and result["native_request_id"] == "upstream-id", result
            assert req("GET", "/receipt?request_id=local-id") == (200, result)
            assert json.loads(backend.call_args.args[2]) == {"wxid": "filehelper", "text": "test"}
        with patch(__name__ + "._proxy", return_value=(200, b'{}')):
            code, result = req("POST", "/send", {"wxid": "filehelper", "text": "bad receipt"})
            assert code == 502 and result["status"] == "status_unknown", result
        return 5

    def stream_checks(req) -> int:
        peer = b'id: 2\ndata: {"fromSelf": false,\ndata: "text": "incoming"}\n\n'
        own = b'id: 1\r\ndata: {"fromSelf": true}\r\n\r\n' + b'id: 3\ndata: {"sender_is_self": true}\n\n'
        partial = b'data: {"text": "incomplete"}\n'
        batch_header = b'event: messages\r\nid: 7\r\n'
        batch_rows = [{"fromSelf": True}, {"sender_is_self": True}, {"fromSelf": 1, "text": "收到"},
                      {"text": "second"}]
        batch = (batch_header + b'data: {"meta":{"cursor":"7"},\r\n: keep\r\ndata: "rows":'
                 + json.dumps(batch_rows).encode() + b'}\r\n\r\n')
        filtered_batch = (batch_header + b'data: {"meta":{"cursor":"7"},"rows":'
                          + json.dumps(batch_rows[2:], separators=(",", ":")).encode() + b'}\r\n: keep\r\n\r\n')
        all_own = b'id: 8\ndata: {"rows":[{"fromSelf":true}]}\n\n'
        from base64 import b64decode
        png = b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z1uoAAAAASUVORK5CYII=")
        image_path = "/image?chatId=filehelper&localId=34&serverId=9007199254740993"
        encoded_chat = "/chat/%E6%B5%8B%E8%AF%95%40chatroom?limit=20"
        seen = []

        class Fixture(BaseHTTPRequestHandler):
            def do_GET(self):
                seen.append((self.path, self.headers.get("Authorization")))
                if self.headers.get("Authorization") != "Bearer upstream-only":
                    self.send_error(401)
                    return
                if self.path == "/contacts?limit=20":
                    self.send_error(401)
                    return
                if self.path == "/unread":
                    self.send_error(402)
                    return
                payload, mime = peer + own + partial, "text/event-stream"
                if self.path.startswith("/chat/"):
                    payload, mime = b'{"items":[{"text":"fixture"}]}', "application/json"
                elif self.path == image_path:
                    payload, mime = png, "image/png"
                elif self.path.startswith("/image?"):
                    payload, mime = b'<!doctype html>', "text/html"
                elif self.path == "/messages/stream?since=4":
                    payload, mime = b'{}', "application/json"
                elif self.path == "/messages/stream?since=5":
                    self.send_response(302)
                    self.send_header("Location", "/chat/redirected")
                    self.end_headers()
                    return
                elif self.path == "/messages/stream?since=6":
                    payload = peer + b'data: invalid\n\n' + own
                elif self.path == "/messages/stream?since=7":
                    payload = batch + all_own
                elif self.path == "/messages/stream?since=8":
                    payload = peer + b'data: {"rows":[null]}\n\n' + batch
                self.send_response(200)
                self.send_header("Content-Type", mime)
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, *_args):
                pass

        with ThreadingHTTPServer(("127.0.0.1", 0), Fixture) as upstream:
            thread = threading.Thread(target=upstream.serve_forever, daemon=True)
            thread.start()
            try:
                with patch.dict(os.environ, {
                    "WECHAT_BRIDGE_UPSTREAM": f"http://127.0.0.1:{upstream.server_port}",
                    "WECHAT_BRIDGE_UPSTREAM_TOKEN": "upstream-only",
                }):
                    assert req("GET", "/messages/stream?since=1")[0] == 401 and not seen
                    assert req("GET", "/messages/stream?since=-1", token="local-only")[0] == 400 and not seen
                    assert req("GET", "/messages/stream?since=1", token="local-only") == (200, peer)
                    assert req("GET", "/messages/stream?since=1&includeSelf=true", token="local-only") == (200, peer + own)
                    assert req("GET", "/chat/filehelper", token="local-only") == (200, {"items": [{"text": "fixture"}]})
                    assert req("GET", "/messages/stream?since=4", token="local-only")[0] == 502
                    assert req("GET", "/messages/stream?since=5", token="local-only")[0] == 502
                    assert req("GET", "/messages/stream?since=6", token="local-only") == (200, peer)
                    assert req("GET", "/messages/stream?since=7", token="local-only") == (
                        200, filtered_batch + b'id: 8\ndata: {"rows":[]}\n\n')
                    assert req("GET", "/messages/stream?since=7&includeSelf=true", token="local-only") == (200, batch + all_own)
                    assert req("GET", "/messages/stream?since=8", token="local-only") == (200, peer)
                    assert req("GET", image_path)[0] == 401
                    assert req("GET", "/image", token="local-only")[0] == 400
                    assert req("GET", image_path, token="local-only") == (200, png)
                    assert req("GET", "/image?chatId=invalid", token="local-only")[0] == 502
                    assert req("GET", encoded_chat, token="local-only") == (200, {"items": [{"text": "fixture"}]})
                    assert [path for path, _ in seen[-3:]] == [image_path, "/image?chatId=invalid", encoded_chat]
                    assert all(token == "Bearer upstream-only" for _, token in seen)
                    assert len(seen) == 12 and not any("redirected" in path for path, _ in seen)
                    assert req("GET", "/contacts", token="local-only") == (503, {
                        "error": "local upstream denied access; check its authorization and activation"})
                    assert req("GET", "/unread", token="local-only") == (503, {
                        "error": "local upstream requires an active subscription"})
            finally:
                upstream.shutdown()
                thread.join(timeout=2)
        return 21

    def desktop_checks(req) -> int:
        from tempfile import TemporaryDirectory

        token = "desktop-test-only"
        rid = "desktop-fixture"
        photo_count = 4
        receipt = {"status": "status_unknown", "request_id": rid, "receipt_recorded": True}
        unknown = {"request_id": rid, "status": "status_unknown"}
        headers = {"token": token}
        query = {"status": "ok", "scope": "visible_ax_labels", "complete_history": False}
        with TemporaryDirectory() as directory:
            root = Path(directory) / "photos"
            root.mkdir()
            paths = [root / f"{i}.jpg" for i in range(photo_count)]
            for p in paths:
                p.touch()  # JPEG validation belongs to the real Swift sender.
            outside = Path(directory) / "outside.jpg"
            outside.touch()
            (root / "link.jpg").symlink_to(outside)
            photos = [str(p.resolve()) for p in paths]
            body = {"wxid": "filehelper", "photos": photos, "request_id": rid}
            with patch.dict(os.environ, {"WECHAT_BRIDGE_DESKTOP_PHOTO_DIR": str(root)}), \
                 patch(__name__ + "._desktop_bin", return_value="/trusted/desktop-sender"), \
                 patch(__name__ + ".subprocess.run") as execute:
                os.environ.pop("WECHAT_DESKTOP_BUNDLE_ID", None)
                for status, path in [(501, "/contacts"), (501, "/chat/wxid_other"),
                                     (501, "/chat/filehelper/history?since=1"), (501, "/messages/stream"),
                                     (400, "/receipt?request_id=bad%20id"),
                                     (400, "/chat/filehelper?limit=101"), (400, "/desktop/search"),
                                     (400, "/desktop/export?format=pdf")]:
                    assert req("GET", path, **headers)[0] == status
                assert req("GET", "/health")[1]["readiness_checked"] is False
                assert req("POST", "/send", body)[0] == 401
                assert req("POST", "/send", {**body, "wxid": "other"}, **headers)[0] == 501
                assert req("POST", "/send", {**body, "text": "mixed"}, **headers)[0] == 400
                assert req("POST", "/send", {**body, "photos": [str(root / "link.jpg")]}, **headers)[0] == 400
                execute.assert_not_called()
                execute.return_value = subprocess.CompletedProcess([], 2, json.dumps(receipt).encode())
                assert req("POST", "/send", body, **headers) == (200, receipt)
                assert json.loads(execute.call_args.kwargs["input"]) == {
                    "op": "send", "recipient": "filehelper", "photos": photos, "request_id": rid}
                assert execute.call_args.args == (["/trusted/desktop-sender"],)
                assert execute.call_args.kwargs["env"]["WECHAT_DESKTOP_BUNDLE_ID"] == "com.tencent.xinWeChat"
                execute.reset_mock()
                with patch(__name__ + ".BRIDGE", Bridge()):
                    assert req("GET", "/receipt?request_id=" + rid, **headers) == (200, receipt)
                    assert json.loads(execute.call_args.kwargs["input"]) == {"op": "receipt", "request_id": rid}
                execute.return_value = subprocess.CompletedProcess([], 1, json.dumps({
                    "status": "failed", "error_code": "request_conflict", "request_id": rid}).encode())
                assert req("POST", "/send", {"wxid": "filehelper", "text": "changed", "request_id": rid}, **headers)[0] == 409
                assert req("GET", "/receipt?request_id=" + rid, **headers)[0] == 502
                execute.return_value = subprocess.CompletedProcess([], 0, b'{}')
                code, result = req("POST", "/send", body, **headers)
                assert code == 502 and all(result.get(k) == v for k, v in unknown.items())
                execute.return_value = subprocess.CompletedProcess([], 0, json.dumps(query).encode())
                for op, path, args in [
                    ("history", "/chat/filehelper", {}),
                    ("history", "/chat/filehelper/history", {}),
                    ("search", "/desktop/search?query=%E5%9B%BE", {"query": "图"}),
                    ("stats", "/desktop/stats", {}),
                    *(("export", f"/desktop/export?format={fmt}", {"format": fmt})
                      for fmt in ("json", "markdown", "html", "csv")),
                ]:
                    assert req("GET", path, **headers) == (200, query)
                    assert json.loads(execute.call_args.kwargs["input"]) == {
                        "op": op, "recipient": "filehelper", "limit": 20, **args}
                for op, path, args in [
                    ("chats", "/chats?limit=3", {"limit": 3}),
                    ("resolve", "/resolve?hint=%E4%BC%9A%E8%AF%9D", {"limit": 10, "hint": "会话"}),
                ]:
                    assert req("GET", path, **headers) == (200, query)
                    assert json.loads(execute.call_args.kwargs["input"]) == {"op": op, **args}
                assert req("GET", "/chats?limit=0", **headers)[0] == 400
                assert req("GET", "/resolve?hint=%20", **headers)[0] == 400
                assert req("GET", "/chats")[0] == 401
                execute.return_value = subprocess.CompletedProcess([], 0, b'{"status":"target_matched","draft_empty":true}')
                assert req("GET", "/desktop/probe", **headers)[0] == 200
                assert json.loads(execute.call_args.kwargs["input"]) == {"op": "probe"}
                execute.return_value = subprocess.CompletedProcess([], 1, b'{"status":"failed"}')
                assert req("GET", "/desktop/probe", **headers)[0] == 503
                assert req("GET", "/chat/filehelper/history", **headers)[0] == 503
                assert req("GET", "/chats", **headers)[0] == 503
                assert req("GET", "/resolve?hint=fixture", **headers)[0] == 503
                assert req("GET", "/desktop/unread-badge", **headers)[0] == 503
                assert req("GET", "/desktop/unread-badge?limit=1", **headers)[0] == 400
                assert req("GET", "/desktop/unread-badge")[0] == 401
                badge = {"status": "ok", "scope": "chat_sidebar_badge", "badge_count": 123, "complete_unread": False}
                execute.return_value = subprocess.CompletedProcess([], 0, json.dumps(badge).encode())
                assert req("GET", "/desktop/unread-badge", **headers) == (200, badge)
                assert json.loads(execute.call_args.kwargs["input"]) == {"op": "unread_badge"}
                execute.reset_mock()
                path = "/desktop/contact-labels"
                assert req("GET", path)[0] == 401
                for suffix in ("?limit=0", "?query=a&query=b", "?recipient=filehelper", "?query=%20"):
                    assert req("GET", path + suffix, **headers)[0] == 400
                execute.assert_not_called()
                contacts = {"status": "ok", "complete_contacts": False, "items": [{"label": "fixture"}]}
                execute.return_value = subprocess.CompletedProcess([], 0, json.dumps(contacts).encode())
                assert req("GET", path + "?query=fixture&limit=1", **headers) == (200, contacts)
                assert json.loads(execute.call_args.kwargs["input"]) == {"op": "contact_labels", "query": "fixture", "limit": 1}
                execute.return_value = subprocess.CompletedProcess([], 1, b'{"status":"failed"}')
                assert req("GET", path, **headers)[0] == 503
                moments_path = "/desktop/moments-labels"
                assert req("GET", moments_path)[0] == 401
                assert req("GET", moments_path, **headers)[0] == 503
                moments = {"status": "ok", "complete_moments": False, "items": [{"label": "A\nB"}]}
                execute.return_value = subprocess.CompletedProcess([], 0, json.dumps(moments).encode())
                assert req("GET", moments_path + "?query=B", **headers) == (200, moments)
                assert json.loads(execute.call_args.kwargs["input"]) == {"op": "moments_labels", "query": "B", "limit": 20}
                execute.reset_mock()
                with patch.dict(os.environ, {"WECHAT_DESKTOP_BUNDLE_ID": "com.tencent.xinWeChat420Test"}):
                    assert req("POST", "/send", body, **headers)[0] == 501
                    assert req("GET", "/receipt?request_id=" + rid, **headers)[0] == 501
                execute.assert_not_called()
                readiness_path = "/desktop/readiness"
                assert req("GET", readiness_path)[0] == 401
                assert req("GET", readiness_path + "?limit=1", **headers)[0] == 400
                execute.assert_not_called()
                readiness = {"status": "ok", "scope": "desktop_snapshot_readiness", "live_wechat": False,
                             "sessions_readable": True, "filehelper_readable": False, "sent": False}
                execute.return_value = subprocess.CompletedProcess([], 0, json.dumps(readiness).encode())
                assert req("GET", readiness_path, **headers) == (200, readiness)
                assert json.loads(execute.call_args.kwargs["input"]) == {"op": "readiness"}
                execute.return_value = subprocess.CompletedProcess([], 1, b'{"status":"failed"}')
                assert req("GET", readiness_path, **headers)[0] == 503
        return 74

    def adapter_checks() -> int:
        from tempfile import TemporaryDirectory

        with TemporaryDirectory() as directory:
            home = Path(directory)
            binary = home / "wechat-wechaty-gateway"
            binary.touch(mode=0o700)
            args = ["--port", "18541"]
            with patch.dict(os.environ, {"HOME": directory, "WECHAT_USE_ADAPTER_DIR": directory}), \
                 patch.object(os, "execv") as execute:
                try:
                    upstream_adapter(["wechaty", *args])
                except SystemExit as exc:
                    assert "before opening listeners" in str(exc)
                else:
                    raise AssertionError("gateway started before state directory check")
                execute.assert_not_called()
                upstream_adapter(["wechaty", "--help"])
                execute.assert_called_once_with(str(binary), [str(binary), "--help"])
                execute.reset_mock()
                (home / ".wx-rs").mkdir(mode=0o700)
                upstream_adapter(["wechaty", *args])
                execute.assert_called_once_with(str(binary), [str(binary), *args])
        return 3

    def mcp_checks() -> int:
        from io import BytesIO, StringIO

        def call(rid, method, **params):
            return {"jsonrpc": "2.0", "id": rid, "method": method, "params": params}

        def tool(rid, name, **args):
            return call(rid, "tools/call", name="filehelper_" + name, arguments=args)

        requests = [call(0, "tools/list"), call(1, "initialize", protocolVersion="2025-06-18"),
                    {"jsonrpc": "2.0", "method": "notifications/initialized"}, call(2, "tools/list"),
                    tool(3, "history", limit=2), tool(4, "search", query="图片"), tool(5, "stats"),
                    tool(6, "export", format="csv"), tool(7, "send"), tool(8, "history", recipient="other"),
                    tool(9, "history", limit=True), tool(10, "export", format="pdf"), tool(11, "stats"),
                    call(12, "tools/call", name="desktop_chats", arguments={"limit": 1}),
                    call(13, "tools/call", name="desktop_resolve", arguments={"hint": " 名称 "})]
        invalid = [("desktop_chats", {"op": "send"}), ("desktop_chats", {"limit": True}),
                   ("desktop_resolve", {}), ("desktop_resolve", {"hint": "  "}),
                   ("desktop_resolve", {"hint": "😀" * 1001}), ("desktop_resolve", {"hint": "\ud800"})]
        requests.extend(call(i, "tools/call", name=name, arguments=args) for i, (name, args) in enumerate(invalid, 14))
        requests.extend([call(20, "tools/call", name="desktop_chats"),
                         call(21, "tools/call", name="desktop_unread_badge"),
                         call(22, "tools/call", name="desktop_unread_badge", arguments={"limit": 1}),
                         call(23, "tools/call", name="desktop_contact_labels", arguments={"query": "Alpha", "limit": 1}),
                         call(24, "tools/call", name="desktop_contact_labels", arguments={"query": " "}),
                         call(25, "tools/call", name="desktop_moments_labels", arguments={"query": "B"}),
                         call(26, "tools/call", name="desktop_moments_labels", arguments={"limit": True})])
        source = BytesIO(b"{bad json}\n" + b"".join(json.dumps(row).encode() + b"\n" for row in requests))
        sink = StringIO()
        ok = {"status": "ok", "scope": "visible_ax_labels", "complete_history": False}
        sessions = {"status": "ok", "scope": "session_list_ax_snapshot", "complete_sessions": False}
        failure = {"status": "failed"}
        badge = {"status": "ok", "scope": "chat_sidebar_badge", "badge_count": 123, "complete_unread": False}
        contacts = {"status": "ok", "complete_contacts": False, "items": [{"label": "Alpha"}]}
        moments = {"status": "ok", "complete_moments": False, "items": [{"label": "A\nB"}]}
        with patch(__name__ + "._call_desktop", side_effect=[ok] * 4 + [failure, sessions, sessions, failure, badge, contacts, moments]) as reader:
            desktop_mcp(source, sink)
        rows = {row["id"]: row for row in map(json.loads, sink.getvalue().splitlines())}
        assert len(rows) == 28 and rows[None]["error"]["code"] == -32700
        assert rows[0]["error"]["code"] == -32002 and rows[1]["result"]["protocolVersion"] == "2025-06-18"
        assert {t["name"] for t in rows[2]["result"]["tools"]} == {
            "filehelper_history", "filehelper_search", "filehelper_stats", "filehelper_export", "desktop_chats",
            "desktop_resolve", "desktop_unread_badge", "desktop_contact_labels", "desktop_moments_labels"}
        assert json.loads(rows[21]["result"]["content"][0]["text"]) == badge
        assert json.loads(rows[23]["result"]["content"][0]["text"]) == contacts
        assert json.loads(rows[25]["result"]["content"][0]["text"]) == moments
        assert rows[22]["error"]["code"] == rows[24]["error"]["code"] == rows[26]["error"]["code"] == -32602
        assert all(json.loads(rows[i]["result"]["content"][0]["text"]) == ok for i in range(3, 7))
        assert all(rows[i]["error"]["code"] == -32602 for i in [*range(7, 11), *range(14, 20)])
        assert rows[11]["result"]["isError"] is True
        assert all(json.loads(rows[i]["result"]["content"][0]["text"]) == sessions for i in (12, 13))
        assert rows[20]["result"]["isError"] is True and "Session list" in rows[20]["result"]["content"][0]["text"]
        assert [c.args[0] for c in reader.call_args_list] == [
            {"op": "history", "recipient": "filehelper", "limit": 2},
            {"op": "search", "recipient": "filehelper", "query": "图片"},
            {"op": "stats", "recipient": "filehelper"},
            {"op": "export", "recipient": "filehelper", "format": "csv"},
            {"op": "stats", "recipient": "filehelper"},
            {"op": "chats", "limit": 1},
            {"op": "resolve", "hint": " 名称 "},
            {"op": "chats"}, {"op": "unread_badge"}, {"op": "contact_labels", "query": "Alpha", "limit": 1},
            {"op": "moments_labels", "query": "B"},
        ]
        return len(rows)

    def cli_checks() -> int:
        seen = []
        lookups = []

        class Fixture(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                lookups.append((self.path, self.headers.get("Authorization")))
                rid = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get("request_id", [""])[0]
                if rid == "redirect":
                    self.send_response(302)
                    self.send_header("Location", "/must-not-be-called")
                    self.end_headers()
                    return
                status = {"original": "submitted_unconfirmed", "missing": "not_found", "unknown": "status_unknown"}.get(rid, "failed")
                row = {"request_id": "wrong" if rid == "mismatch" else rid, "status": status}
                raw = json.dumps(row).encode()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(raw)

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                seen.append((self.path, body))
                if body["request_id"] == "redirect":
                    self.send_response(307)
                    self.send_header("Location", "/must-not-be-called")
                    self.end_headers()
                    return
                rid = "wrong-id" if body["request_id"] == "mismatch" else body["request_id"]
                raw = json.dumps({"request_id": rid, "status": "submitted_unconfirmed"}).encode()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(raw)

        with ThreadingHTTPServer(("127.0.0.1", 0), Fixture) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                env = {**os.environ, "WECHAT_BRIDGE_URL": f"http://127.0.0.1:{server.server_port}",
                       "WECHAT_BRIDGE_BEARER": "fixture-only", "http_proxy": "http://127.0.0.1:1",
                       "no_proxy": "", "NO_PROXY": ""}
                paths = [f"/photos/测试 {i}.jpg" for i in (4, 1, 3, 2)]
                photos = [arg for path in paths for arg in ("--photo", path)]

                def cli(*args, url=None):
                    return subprocess.run([sys.executable, __file__, "send", "filehelper", *args],
                                          env=env if url is None else {**env, "WECHAT_BRIDGE_URL": url},
                                          capture_output=True, text=True, timeout=8)

                p = cli(*photos, "--request-id", "four-photos")
                assert p.returncode == 0 and json.loads(p.stdout)["status"] == "submitted_unconfirmed"
                assert seen == [("/send", {"wxid": "filehelper", "request_id": "four-photos", "photos": paths})]
                for rid in ("redirect", "mismatch"):
                    p = cli("test", "--request-id", rid)
                    row = json.loads(p.stdout)
                    assert p.returncode == 2 and row["status"] == "status_unknown" and row["request_id"] == rid
                assert cli("text", *photos).returncode == 2
                assert cli("--photo", "relative.jpg").returncode == 2
                p = cli(*photos, url="https://example.invalid")
                assert p.returncode == 1 and json.loads(p.stdout)["status"] == "failed"
                cases = [("original", 0, "submitted_unconfirmed"), ("failed", 1, "failed"),
                         ("missing", 2, "not_found"), ("unknown", 2, "status_unknown"),
                         ("redirect", 2, "receipt_unavailable"), ("mismatch", 2, "receipt_unavailable")]
                for rid, code, status in cases:
                    p = subprocess.run([sys.executable, __file__, "receipt", rid], env=env,
                                       capture_output=True, text=True, timeout=8)
                    row = json.loads(p.stdout)
                    assert (p.returncode, row["status"], row["request_id"]) == (code, status, rid)
                assert lookups == [(f"/receipt?request_id={rid}", "Bearer fixture-only") for rid, _, _ in cases]
                assert [path for path, _ in seen] == ["/send"] * 3
            finally:
                server.shutdown()
                thread.join(timeout=2)
        return 15

    def tui_checks() -> int:
        from io import StringIO

        source = StringIO("chats\nresolve  名称 \nhistory\nsearch 图片\nstats\nexport csv\nunread_badge\n"
                          "contact_labels\ncontact_labels Alpha\nmoments_labels B\ncontact_labels   \n"
                          "send hello\nresolve   \nresolve\nexport pdf\nchats 1\nunread_badge 1\nchats\nquit\nchats\n")
        sink = StringIO()
        ok = {"status": "ok", "label": "\x1b[2J\n测试"}
        with patch(__name__ + "._call_desktop", side_effect=[ok] * 10 + [{"status": "failed"}]) as reader:
            desktop_tui(source, sink)
        assert "\x1b" not in sink.getvalue()
        rows = list(map(json.loads, sink.getvalue().splitlines()))
        assert rows[:10] == [ok] * 10 and [r["status"] for r in rows[10:]] == ["failed"] * 7 + ["unavailable"]
        assert [c.args[0] for c in reader.call_args_list] == [
            {"op": "chats"}, {"op": "resolve", "hint": " 名称 "},
            {"op": "history", "recipient": "filehelper"},
            {"op": "search", "recipient": "filehelper", "query": "图片"},
            {"op": "stats", "recipient": "filehelper"},
            {"op": "export", "recipient": "filehelper", "format": "csv"},
            {"op": "unread_badge"}, {"op": "contact_labels"}, {"op": "contact_labels", "query": "Alpha"},
            {"op": "moments_labels", "query": "B"}, {"op": "chats"},
        ]
        return len(rows)

    n1 = run_case("noop", {}, noop_checks)
    n2 = run_case("noop", {"WECHAT_BRIDGE_BEARER": "secret"}, auth_checks)
    # exec backend: a fake executor that echoes a delivered status via stdin JSON.
    fake = "python3 -c 'import sys,json; d=json.load(sys.stdin); print(json.dumps({\"status\":\"delivered\" if d[\"op\"]==\"send\" else \"ok\",\"request_id\":\"native-test-receipt\"}))'"
    n3 = run_case("exec", {"WECHAT_BRIDGE_EXEC_SEND": fake}, exec_checks)
    n4 = run_case("upstream", {}, receipt_checks) + run_case("upstream", {}, upstream_checks)
    n5 = run_case("upstream", {"WECHAT_BRIDGE_BEARER": "local-only"}, stream_checks)
    n6 = run_case("desktop", {"WECHAT_BRIDGE_BEARER": "desktop-test-only"}, desktop_checks)
    n7 = adapter_checks()
    n8 = mcp_checks()
    n9 = cli_checks()
    n10 = tui_checks()
    print(f"self-test ok: {n1} noop + {n2} auth + {n3} exec + {n4} receipt/upstream + {n5} stream + {n6} desktop + {n7} adapter + {n8} MCP + {n9} CLI + {n10} TUI = {n1+n2+n3+n4+n5+n6+n7+n8+n9+n10} protocol checks")


def probe() -> None:
    """Read-only environment report; never touches the GUI or sends anything."""
    import plistlib
    import subprocess as sp

    report: dict = {"backend": _backend(), "bearer_set": bool(_bearer())}
    for app in ("/Applications/WeChat.app", "/Applications/WeChat-4.1.9-wechat-use.app"):
        if Path(app).exists():
            try:
                with open(app + "/Contents/Info.plist", "rb") as f:
                    info = plistlib.load(f)
                report.setdefault("wechat_apps", []).append({
                    "path": app, "version": info.get("CFBundleShortVersionString"),
                    "bundle_id": info.get("CFBundleIdentifier")})
            except Exception as exc:  # noqa: BLE001
                report.setdefault("wechat_apps", []).append({"path": app, "error": type(exc).__name__})
    try:
        out = sp.run(["pgrep", "-fl", "^/Applications/WeChat.app/Contents/MacOS/WeChat$"],
                     capture_output=True, text=True, timeout=5).stdout
        report["wechat_main_pids"] = [l.split()[0] for l in out.splitlines()
                                      if l.strip() and "Helper" not in l][:5]
    except Exception as exc:  # noqa: BLE001
        report["wechat_main_pids_error"] = type(exc).__name__
    port = int(_env("WECHAT_BRIDGE_PORT", str(DEFAULT_PORT)))
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=2) as r:
            report["port_18400"] = json.loads(r.read())
    except Exception:
        report["port_18400"] = "free"
    # AX writability: WeChat 4.x exposes no settable input field. Report count only.
    try:
        swift = r'''
import ApplicationServices
let app=AXUIElementCreateApplication(pid_t(%s))
var w:CFTypeRef?
AXUIElementCopyAttributeValue(app,kAXWindowsAttribute as CFString,&w)
print((w as? [AXUIElement])?.count ?? -1)
''' % (report["wechat_main_pids"][0] if report.get("wechat_main_pids") else "-1")
        p = sp.run(["swift", "-e", swift], capture_output=True, text=True, timeout=30)
        report["ax_windows"] = p.stdout.strip() or p.stderr.strip()[:120]
    except Exception as exc:  # noqa: BLE001
        report["ax_windows"] = type(exc).__name__
    print(json.dumps(report, ensure_ascii=False, indent=2))


def cli_send(args: argparse.Namespace) -> None:
    rid = args.request_id or uuid.uuid4().hex
    try:
        base, _ = _loopback_origin(_env("WECHAT_BRIDGE_URL", f"http://127.0.0.1:{args.port}"))
    except ValueError:
        print(json.dumps({"status": "failed", "request_id": rid, "error": "invalid local bridge URL"}))
        sys.exit(1)
    content = {"photos": args.photos} if args.photos else {"text": args.text}
    body = json.dumps({"wxid": args.wxid, "request_id": rid, **content}, ensure_ascii=False).encode()
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    tok = _bearer()
    if tok:
        headers["Authorization"] = "Bearer " + tok
    req = urllib.request.Request(base + "/send", data=body, method="POST", headers=headers)
    try:
        try:
            with urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect()).open(req, timeout=30) as resp:
                out = json.loads(resp.read())
        except urllib.error.HTTPError as exc:
            with exc:
                data = json.loads(exc.read())
            if exc.code in (400, 401, 409, 501):
                out = {"status": "failed", "request_id": rid, "error": data["error"]}
            elif exc.code == 502 and data.get("status") == "status_unknown" and data.get("request_id") == rid:
                out = data
            else:
                raise
        if (not isinstance(out, dict) or out.get("status") not in SEND_STATUSES | {"pending"}
                or out.get("request_id") != rid):
            raise ValueError("unrecognized send response")
    except Exception as exc:  # A network or protocol error does not prove no send occurred.
        out = {"status": "status_unknown", "request_id": rid, "error": type(exc).__name__,
               "diagnostic": "send outcome unknown; query the original receipt, do not retry"}
    print(json.dumps(out, ensure_ascii=False))
    if out["status"] in ("pending", "status_unknown"):
        sys.exit(2)
    if out["status"] == "failed":
        sys.exit(1)


def cli_receipt(args: argparse.Namespace) -> int:
    rid = args.request_id
    try:
        base, _ = _loopback_origin(_env("WECHAT_BRIDGE_URL", f"http://127.0.0.1:{args.port}"))
        token = _bearer()
        headers = {"Accept": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        path = "/receipt?" + urllib.parse.urlencode({"request_id": rid})
        req = urllib.request.Request(base + path, method="GET", headers=headers)
        try:
            with urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect()).open(req, timeout=10) as resp:
                raw = resp.read(MAX_BODY + 1)
                if len(raw) > MAX_BODY:
                    raise ValueError("receipt response too large")
                row = json.loads(raw)
        except urllib.error.HTTPError as exc:
            exc.close()
            raise
        if (not isinstance(row, dict) or row.get("request_id") != rid
                or row.get("status") not in SEND_STATUSES | {"pending", "not_found"}):
            raise ValueError("invalid receipt response")
    except (ValueError, OSError, TypeError, http.client.HTTPException) as exc:
        row = {"status": "receipt_unavailable", "request_id": rid, "error": type(exc).__name__}
    print(json.dumps(row, ensure_ascii=False))
    if row["status"] in {"delivered", "submitted_unconfirmed"}:
        return 0
    return 1 if row["status"] == "failed" else 2


def upstream_cli(argv: list[str]) -> None:
    """Hand off explicit CLI arguments without interpreting them or replaying a command."""
    binary = _env("WECHAT_USE_BIN")
    if not argv or not Path(binary).is_absolute() or not Path(binary).is_file() or not os.access(binary, os.X_OK):
        raise SystemExit("upstream CLI requires arguments and WECHAT_USE_BIN set to a trusted absolute executable path")
    os.execv(binary, [binary, *argv])


def upstream_adapter(argv: list[str]) -> None:
    """Use explicit upstream companion components; never provision or register them."""
    names = {"http": "wechat-bridge", "mcp": "wechat-mcp",
             "mcp-send": "wechat-send-mcp", "wechaty": "wechat-wechaty-gateway"}
    if not argv or argv[0] not in names:
        raise SystemExit("upstream-adapter requires http, mcp, mcp-send or wechaty")
    root = Path(_env("WECHAT_USE_ADAPTER_DIR"))
    args = argv[1:]
    binary = root / names[argv[0]]
    if not root.is_absolute() or not binary.is_file() or not os.access(binary, os.X_OK):
        raise SystemExit("set WECHAT_USE_ADAPTER_DIR to an absolute directory of trusted upstream executables")
    if argv[0] in {"http", "wechaty"} and not args:
        raise SystemExit("network adapters require explicit arguments; use --help for the supported options")
    if argv[0] == "wechaty" and args not in (["-h"], ["--help"], ["-V"], ["--version"]):
        state = Path.home() / ".wx-rs"
        if not state.is_dir() or not os.access(state, os.W_OK | os.X_OK):
            raise SystemExit("Wechaty needs a writable ~/.wx-rs directory before opening listeners; run official setup first")
    os.execv(str(binary), [str(binary), *args])


def desktop_mcp(source, sink) -> None:
    """Read-only MCP over stdio. Never dispatch an operation selected by client data."""
    formats = ["json", "markdown", "html", "csv"]
    limit_schema = {"type": "integer", "minimum": 1, "maximum": 100, "default": 20}
    tools = {}
    for op in ("history", "search", "stats", "export"):
        props = {"limit": limit_schema}
        schema = {"type": "object", "properties": props, "additionalProperties": False}
        if op == "search":
            props["query"] = {"type": "string", "minLength": 1, "maxLength": 2000}
            schema["required"] = ["query"]
        if op == "export":
            props["format"] = {"type": "string", "enum": formats, "default": "json"}
        tools["filehelper_" + op] = (op, {"name": "filehelper_" + op, "inputSchema": schema,
            "description": f"{op.title()} the visible labels in the open File Transfer Assistant window only. "
                           "Not full history; does not open a window, scroll, or send."})
    for op, name, description in (
        ("chats", "desktop_chats", "List display names in the visible session-list snapshot only."),
        ("resolve", "desktop_resolve", "Match an exact display name in the visible session-list snapshot only."),
    ):
        schema = {"type": "object", "properties": {"limit": limit_schema}, "additionalProperties": False}
        if op == "resolve":
            schema["properties"]["hint"] = {"type": "string", "minLength": 1, "maxLength": 2000}
            schema["required"] = ["hint"]
        tools[name] = (op, {"name": name, "inputSchema": schema,
                           "description": description + " No account identifiers or send permission."})

    for op, description in (
        ("contact_labels", "Read visible Contacts labels, including section labels. No contact IDs."),
        ("moments_labels", "Read visible Moments labels, not full history or media."),
    ):
        name = "desktop_" + op
        tools[name] = (op, {"name": name, "inputSchema": {"type": "object", "additionalProperties": False,
            "properties": {"limit": limit_schema, "query": {"type": "string", "maxLength": 2000}}},
            "description": description + " Does not navigate."})
    tools["desktop_unread_badge"] = ("unread_badge", {
        "name": "desktop_unread_badge", "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "description": "Read the desktop chat sidebar badge only. Null means no badge shown, not zero unread. No per-chat counts."})

    def reply(row: dict) -> None:
        sink.write(json.dumps({"jsonrpc": "2.0", **row}, ensure_ascii=True) + "\n")
        sink.flush()

    initialized = False
    while raw := source.readline(MAX_BODY + 1):
        if len(raw) > MAX_BODY:
            reply({"id": None, "error": {"code": -32600, "message": "Message too large"}})
            return
        try:
            msg = json.loads(raw)
        except (ValueError, RecursionError):
            reply({"id": None, "error": {"code": -32700, "message": "Parse error"}})
            continue
        if (not isinstance(msg, dict) or msg.get("jsonrpc") != "2.0"
                or not isinstance(msg.get("method"), str)
                or ("id" in msg and type(msg["id"]) not in {str, int})):
            reply({"id": None, "error": {"code": -32600, "message": "Invalid request"}})
            continue
        if "id" not in msg:
            continue  # Notifications never dispatch tools or get a reply.
        rid, method = msg["id"], msg["method"]
        params = msg.get("params", {})
        code, detail = 0, ""
        if not isinstance(params, dict):
            code, detail = -32602, "Invalid params"
        elif method == "initialize":
            requested = params.get("protocolVersion")
            if not isinstance(requested, str):
                code, detail = -32602, "protocolVersion required"
            else:
                supported = {"2024-11-05", "2025-03-26", "2025-06-18"}
                result = {"protocolVersion": requested if requested in supported else "2025-06-18",
                          "capabilities": {"tools": {}}, "serverInfo": {"name": "wechat-desktop-readonly", "version": "1.0.0"}}
                initialized = True
        elif method == "ping":
            result = {}
        elif not initialized:
            code, detail = -32002, "Server not initialized"
        elif method == "tools/list":
            result = {"tools": [tool for _, tool in tools.values()]}
        elif method == "tools/call":
            name, args = params.get("name"), params.get("arguments", {})
            if not isinstance(name, str) or name not in tools:
                code, detail = -32602, "Unknown read-only tool"
            else:
                op, tool = tools[name]
                if not isinstance(args, dict) or not args.keys() <= tool["inputSchema"]["properties"].keys():
                    code, detail = -32602, "Invalid tool arguments"
                else:
                    limit, fmt = args.get("limit", 20), args.get("format", "json")
                    term = args.get("hint" if op == "resolve" else "query")
                    if (type(limit) is not int or not 1 <= limit <= 100
                            or (op in {"search", "resolve"} and (not isinstance(term, str) or not term.strip()
                                or len(term.encode("utf-16-le", errors="surrogatepass")) > 4000
                                or any(0xD800 <= ord(char) <= 0xDFFF for char in term)))
                            or (op in {"contact_labels", "moments_labels"} and "query" in args and (not isinstance(term, str)
                                or (term and not term.strip()) or len(term.encode("utf-16-le", errors="surrogatepass")) > 4000
                                or any(0xD800 <= ord(char) <= 0xDFFF for char in term)))
                            or (op == "export" and fmt not in formats)):
                        code, detail = -32602, "Invalid tool arguments"
                    else:
                        request = {**args, "op": op}
                        if name.startswith("filehelper_"):
                            request["recipient"] = "filehelper"
                        target = {"chats": "Session list", "resolve": "Session list",
                                  "unread_badge": "Chat sidebar badge", "contact_labels": "Contacts list",
                                  "moments_labels": "Moments list"}.get(op, "File Transfer Assistant")
                        try:
                            data = _call_desktop(request)
                            if data["status"] != "ok":
                                raise DesktopUnavailable()
                            result = {"content": [{"type": "text", "text": json.dumps(data, ensure_ascii=False)}]}
                        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
                            result = {"isError": True, "content": [{"type": "text", "text": target + " unavailable in the background"}]}
        else:
            code, detail = -32601, "Method not found"
        reply({"id": rid, "error": {"code": code, "message": detail}} if code else {"id": rid, "result": result})


def desktop_tui(source, sink) -> None:
    """Interactive local reads only; JSON escaping keeps chat data out of terminal control sequences."""
    help_text = "chats | resolve <name> | unread_badge | contact_labels [text] | moments_labels [text] | history | search <text> | stats | export <json|markdown|html|csv> | quit"
    interactive = source.isatty()
    while True:
        if interactive:
            print("wechat> ", end="", file=sink, flush=True)
        line = source.readline(8193)
        if not line:
            return
        if len(line) > 8192:
            print('{"status":"failed","error":"input too long"}', file=sink, flush=True)
            return
        op, sep, arg = line.rstrip("\r\n").partition(" ")
        if op == "quit" and not sep:
            return
        if not sep and op in {"", "help"}:
            print(help_text, file=sink, flush=True)
            continue
        request = {"op": op}
        if op in {"history", "search", "stats", "export"}:
            request["recipient"] = "filehelper"
        if (op in {"resolve", "search"} and arg.strip()
                and len(arg.encode("utf-16-le", errors="surrogatepass")) <= 4000
                and not any(0xD800 <= ord(c) <= 0xDFFF for c in arg)):
            request["hint" if op == "resolve" else "query"] = arg
        elif op == "export" and arg in {"json", "markdown", "html", "csv"}:
            request["format"] = arg
        elif (op in {"contact_labels", "moments_labels"} and sep and arg.strip()
              and len(arg.encode("utf-16-le", errors="surrogatepass")) <= 4000
              and not any(0xD800 <= ord(c) <= 0xDFFF for c in arg)):
            request["query"] = arg
        elif sep or op not in {"chats", "unread_badge", "contact_labels", "moments_labels", "history", "stats"}:
            print('{"status":"failed","error":"invalid read command"}', file=sink, flush=True)
            continue
        try:
            row = _call_desktop(request)
            if row["status"] != "ok":
                raise DesktopUnavailable()
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
            row = {"status": "unavailable", "error": "desktop snapshot not readable"}
        rendered = json.dumps(row, ensure_ascii=False)
        print("".join(c if c.isprintable() else json.dumps(c)[1:-1] for c in rendered), file=sink, flush=True)


def main() -> None:
    if sys.argv[1:2] == ["upstream-cli"]:
        upstream_cli(sys.argv[2:])
    if sys.argv[1:2] == ["upstream-adapter"]:
        upstream_adapter(sys.argv[2:])
    p = argparse.ArgumentParser(description="wechat-use-compatible local send bridge")
    sub = p.add_subparsers(dest="cmd")
    serve = sub.add_parser("serve", help="start loopback HTTP bridge")
    serve.add_argument("--port", type=int, default=int(_env("WECHAT_BRIDGE_PORT", str(DEFAULT_PORT))))
    sub.add_parser("self-test", help="run protocol checks (no GUI, no send)")
    sub.add_parser("probe", help="read-only environment report (no GUI, no send)")
    sub.add_parser("desktop-mcp", help="read-only session and filehelper MCP over stdio")
    sub.add_parser("desktop-tui", help="open a local read-only terminal console")
    sub.add_parser("upstream-cli", help="run an explicit command using the trusted WECHAT_USE_BIN executable")
    sub.add_parser("upstream-adapter", help="run an explicit official http, mcp, mcp-send or wechaty companion")
    send = sub.add_parser("send", help="POST /send once, never retry")
    send.add_argument("wxid")
    send.add_argument("text", nargs="?")
    send.add_argument("--photo", dest="photos", action="append", metavar="ABS_JPEG", help="desktop photo path, repeat up to four times")
    send.add_argument("--request-id", help="stable request ID for deduplication and receipt lookup")
    send.add_argument("--port", type=int, default=DEFAULT_PORT)
    receipt = sub.add_parser("receipt", help="look up an existing request once without sending")
    receipt.add_argument("request_id")
    receipt.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = p.parse_args()
    if args.cmd == "self-test":
        self_test()
    elif args.cmd == "probe":
        probe()
    elif args.cmd in {"desktop-mcp", "desktop-tui"}:
        try:
            _desktop_bin()
        except ValueError as exc:
            p.error(str(exc))
        if args.cmd == "desktop-mcp":
            desktop_mcp(sys.stdin.buffer, sys.stdout)
        else:
            try:
                desktop_tui(sys.stdin, sys.stdout)
            except KeyboardInterrupt:
                sys.exit(130)
    elif args.cmd == "send":
        if (args.text is None) == (args.photos is None):
            send.error("provide exactly one of text or --photo")
        if args.photos and (args.wxid != "filehelper" or len(args.photos) > 4
                            or not all(Path(path).is_absolute() for path in args.photos)):
            send.error("provide 1–4 absolute JPEG paths for filehelper")
        if args.request_id is not None:
            try:
                _check_request_id(args.request_id)
            except ValueError as exc:
                send.error(str(exc))
        cli_send(args)
    elif args.cmd == "receipt":
        try:
            _check_request_id(args.request_id)
        except ValueError as exc:
            receipt.error(str(exc))
        sys.exit(cli_receipt(args))
    elif args.cmd == "serve":
        backend = _backend()
        if backend not in {"noop", "exec", "desktop", "upstream"}:
            p.error("WECHAT_BRIDGE_BACKEND must be noop, exec, desktop or upstream")
        if backend == "desktop":
            if not _bearer():
                p.error("desktop backend requires WECHAT_BRIDGE_BEARER")
            try:
                _desktop_bin()
            except ValueError as exc:
                p.error(str(exc))
        if backend == "upstream":
            try:
                _, upstream_port = _upstream_origin()
            except ValueError as exc:
                p.error(str(exc))
            if args.port == upstream_port:
                p.error("upstream port must differ from this bridge's listen port")
        with ThreadingHTTPServer(("127.0.0.1", args.port), Handler) as server:
            print(f"wechat-bridge on 127.0.0.1:{server.server_port} backend={backend}", flush=True)
            server.serve_forever()
    else:
        p.print_help()


if __name__ == "__main__":
    main()
