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
  GET  /receipt?request_id=X      -> process-local receipt, no send

Backend is selected by WECHAT_BRIDGE_BACKEND:
  "noop"   (default) - no GUI, no send; returns status_unknown. Safe for wiring tests.
  "exec"            - one command per operation, JSON on stdin, JSON on stdout.
  "upstream"        - proxy every route to an already-running wechat-use bridge.

Only loopback is bound (127.0.0.1). Set WECHAT_BRIDGE_BEARER to require auth on
non-/health routes. Never log message text, wxid or tokens.
"""
from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import os
import re
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


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def _backend() -> str:
    return _env("WECHAT_BRIDGE_BACKEND", "noop").lower()


def _bearer() -> str:
    return _env("WECHAT_BRIDGE_BEARER")


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


class NoUpstreamRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Never forward an upstream credential or replay a POST on redirect.


def _open_upstream(method: str, path: str, body: bytes | None, headers: dict):
    base = _env("WECHAT_BRIDGE_UPSTREAM", DEFAULT_UPSTREAM).rstrip("/")
    parsed = urllib.parse.urlsplit(base)
    if (parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}
            or parsed.username is not None or parsed.path or parsed.query or parsed.fragment):
        raise RuntimeError("upstream must be a loopback HTTP origin")
    headers = dict(headers)
    token = _env("WECHAT_BRIDGE_UPSTREAM_TOKEN")
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(base + path, data=body, method=method, headers=headers)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoUpstreamRedirect())
    try:
        return opener.open(req, timeout=30)
    except urllib.error.HTTPError as exc:
        exc.close()
        raise


def _proxy(method: str, path: str, body: bytes | None, headers: dict) -> tuple[int, bytes]:
    with _open_upstream(method, path, body, headers) as resp:
        return resp.status, resp.read()


def _sse_frames(source, include_self: bool):
    """Forward bounded SSE frames; do not treat partial frames as new messages."""
    frame = bytearray()
    data = []
    while line := source.readline(MAX_BODY + 1):
        if len(frame) + len(line) > MAX_BODY:
            raise ValueError("upstream SSE frame too large")
        frame.extend(line)
        content = line.rstrip(b"\r\n")
        if content.startswith(b"data:"):
            data.append(content[5:].removeprefix(b" "))
        elif not content:
            if data:
                message = json.loads(b"\n".join(data))
                if not isinstance(message, dict):
                    raise ValueError("upstream SSE data must be a JSON object")
                if include_self or message.get("fromSelf") is not True:
                    yield bytes(frame)
            elif frame.startswith(b":"):
                yield bytes(frame)
            frame.clear()
            data.clear()


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
        return {"ok": True, "backend": b, "send_ready": b != "noop",
                "note": "noop backend never sends; this is a protocol harness"}

    def _query(self, op: str, payload: dict) -> dict:
        b = _backend()
        if b == "noop":
            return {"ok": True, "items": [], "backend": "noop"}
        if b == "exec":
            return _call_exec(op, payload)
        if b == "upstream":
            qs = urllib.parse.urlencode({k: v for k, v in payload.items() if v not in (None, "")})
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
        wxid = str(payload.get("wxid", "")).strip()
        text = payload.get("text")
        if not wxid:
            raise ValueError("wxid is required")
        if not isinstance(text, str) or not text:
            raise ValueError("text is required")
        if len(text) > MAX_TEXT:
            raise ValueError(f"text exceeds {MAX_TEXT} chars")
        if "mention" in payload and not isinstance(payload["mention"], (str, list, dict)):
            raise ValueError("mention must be a string, list or object")

        rid = payload.get("request_id", uuid.uuid4().hex)
        if not isinstance(rid, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", rid):
            raise ValueError("request_id must contain 1..128 ASCII letters, digits, underscores or hyphens")
        message = {"wxid": wxid, "text": text}
        if "mention" in payload:
            message["mention"] = payload["mention"]
        body = json.dumps(message, ensure_ascii=False, sort_keys=True).encode()
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
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(raw)

    def _auth_ok(self) -> bool:
        token = _bearer()
        if not token or self.path.split("?", 1)[0] == "/health":
            return True
        return self.headers.get("Authorization", "") == "Bearer " + token

    def _read_body(self) -> bytes:
        n = int(self.headers.get("Content-Length", "0"))
        if n <= 0 or n > MAX_BODY:
            raise ValueError("invalid Content-Length")
        return self.rfile.read(n)

    def do_GET(self) -> None:  # noqa: N802 - stdlib
        if not self._auth_ok():
            return self._reply(401, {"error": "unauthorized"})
        parsed = urllib.parse.urlparse(self.path)
        path, qs = parsed.path, urllib.parse.parse_qs(parsed.query)
        try:
            if path == "/health":
                return self._reply(200, BRIDGE.health())
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
                        "wxid": rest[:-len("/history")], "since": qs.get("since", [""])[0],
                        "until": qs.get("until", [""])[0], "limit": int(qs.get("limit", ["20"])[0])}))
                return self._reply(200, BRIDGE._query("chat", {
                    "wxid": rest, "limit": int(qs.get("limit", ["20"])[0])}))
            if path == "/receipt":
                return self._reply(200, BRIDGE.receipt(qs.get("request_id", [""])[0]))
            return self._reply(404, {"error": "not found"})
        except (ValueError, KeyError) as exc:
            return self._reply(400, {"error": str(exc)})
        except Exception as exc:  # noqa: BLE001 - surface class only, never text
            return self._reply(502, {"error": type(exc).__name__})

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
        except ValueError as exc:
            return self._reply(400, {"error": str(exc)})
        else:
            return self._reply(502 if "error" in result else 200, result)


def self_test() -> None:
    """Protocol-level checks for all three backends; no GUI, no network, no real send."""
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
                    return r.status, data if r.headers.get_content_type() == "text/event-stream" else json.loads(data)
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
        own = b'id: 1\r\ndata: {"fromSelf": true}\r\n\r\n'
        partial = b'data: {"text": "incomplete"}\n'
        seen = []

        class Fixture(BaseHTTPRequestHandler):
            def do_GET(self):
                seen.append((self.path, self.headers.get("Authorization")))
                if self.headers.get("Authorization") != "Bearer upstream-only":
                    self.send_error(401)
                    return
                payload, mime = peer + own + partial, "text/event-stream"
                if self.path.startswith("/chat/"):
                    payload, mime = b'{"items":[{"text":"fixture"}]}', "application/json"
                elif self.path == "/messages/stream?since=4":
                    payload, mime = b'{}', "application/json"
                elif self.path == "/messages/stream?since=5":
                    self.send_response(302)
                    self.send_header("Location", "/chat/redirected")
                    self.end_headers()
                    return
                elif self.path == "/messages/stream?since=6":
                    payload = peer + b'data: invalid\n\n' + own
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
                    assert all(token == "Bearer upstream-only" for _, token in seen)
                    assert len(seen) == 6 and not any("redirected" in path for path, _ in seen)
            finally:
                upstream.shutdown()
                thread.join(timeout=2)
        return 10

    n1 = run_case("noop", {}, noop_checks)
    n2 = run_case("noop", {"WECHAT_BRIDGE_BEARER": "secret"}, auth_checks)
    # exec backend: a fake executor that echoes a delivered status via stdin JSON.
    fake = "python3 -c 'import sys,json; d=json.load(sys.stdin); print(json.dumps({\"status\":\"delivered\" if d[\"op\"]==\"send\" else \"ok\",\"request_id\":\"native-test-receipt\"}))'"
    n3 = run_case("exec", {"WECHAT_BRIDGE_EXEC_SEND": fake}, exec_checks)
    n4 = run_case("upstream", {}, receipt_checks) + run_case("upstream", {}, upstream_checks)
    n5 = run_case("upstream", {"WECHAT_BRIDGE_BEARER": "local-only"}, stream_checks)
    print(f"self-test ok: {n1} noop + {n2} auth + {n3} exec + {n4} receipt/upstream + {n5} stream = {n1+n2+n3+n4+n5} protocol checks")


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
    base = _env("WECHAT_BRIDGE_URL", f"http://127.0.0.1:{args.port}").rstrip("/")
    rid = args.request_id or uuid.uuid4().hex
    body = json.dumps({"wxid": args.wxid, "text": args.text, "request_id": rid},
                      ensure_ascii=False).encode()
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    tok = _bearer()
    if tok:
        headers["Authorization"] = "Bearer " + tok
    req = urllib.request.Request(base + "/send", data=body, method="POST", headers=headers)
    try:
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                out = json.loads(resp.read())
        except urllib.error.HTTPError as exc:
            with exc:
                data = json.loads(exc.read())
            if exc.code in (400, 401, 409):
                out = {"status": "failed", "request_id": rid, "error": data["error"]}
            elif exc.code == 502 and data.get("status") == "status_unknown" and data.get("request_id") == rid:
                out = data
            else:
                raise
        if not isinstance(out, dict) or out.get("status") not in SEND_STATUSES | {"pending"}:
            raise ValueError("unrecognized send response")
    except Exception as exc:  # A network or protocol error does not prove no send occurred.
        out = {"status": "status_unknown", "request_id": rid, "error": type(exc).__name__,
               "diagnostic": "send outcome unknown; query the original receipt, do not retry"}
    print(json.dumps(out, ensure_ascii=False))
    if out["status"] in ("pending", "status_unknown"):
        sys.exit(2)
    if out["status"] == "failed":
        sys.exit(1)


def main() -> None:
    p = argparse.ArgumentParser(description="wechat-use-compatible local send bridge")
    sub = p.add_subparsers(dest="cmd")
    serve = sub.add_parser("serve", help="start loopback HTTP bridge")
    serve.add_argument("--port", type=int, default=int(_env("WECHAT_BRIDGE_PORT", str(DEFAULT_PORT))))
    sub.add_parser("self-test", help="run protocol checks (no GUI, no send)")
    sub.add_parser("probe", help="read-only environment report (no GUI, no send)")
    send = sub.add_parser("send", help="POST /send once, never retry")
    send.add_argument("wxid")
    send.add_argument("text")
    send.add_argument("--request-id", help="stable request ID for deduplication and receipt lookup")
    send.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = p.parse_args()
    if args.cmd == "self-test":
        self_test()
    elif args.cmd == "probe":
        probe()
    elif args.cmd == "send":
        cli_send(args)
    elif args.cmd == "serve":
        print(f"wechat-bridge on 127.0.0.1:{args.port} backend={_backend()}", flush=True)
        ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
    else:
        p.print_help()


if __name__ == "__main__":
    main()
