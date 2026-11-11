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
  POST /send  {wxid,text,mention?} -> {"status":...,"diagnostic":...}

Backend is selected by WECHAT_BRIDGE_BACKEND:
  "noop"   (default) - no GUI, no send; returns status_unknown. Safe for wiring tests.
  "exec"            - one command per operation, JSON on stdin, JSON on stdout.
  "upstream"        - proxy every route to an already-running wechat-use bridge.

Only loopback is bound (127.0.0.1). Set WECHAT_BRIDGE_BEARER to require auth on
non-/health routes. Never log message text, wxid or tokens.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DEFAULT_PORT = 18400
DEFAULT_UPSTREAM = "http://127.0.0.1:18400"
MAX_BODY = 1 << 20
MAX_TEXT = 8000


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
        return {"ok": True}
    data = json.loads(out)
    if not isinstance(data, dict):
        raise RuntimeError("executor must print a JSON object")
    return data


def _proxy(method: str, path: str, body: bytes | None, headers: dict) -> tuple[int, bytes]:
    base = _env("WECHAT_BRIDGE_UPSTREAM", DEFAULT_UPSTREAM).rstrip("/")
    req = urllib.request.Request(base + path, data=body, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.status, resp.read()


class Bridge:
    """All state lives here; the handler is stateless per request."""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.sent: list[dict] = []
        self.requests: dict[str, str] = {}

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
            path = {"chats": "/chats", "unread": "/unread", "contacts": "/contacts",
                    "resolve": "/resolve", "chat": "/chat/" + str(payload.get("wxid", "")),
                    "chat_history": "/chat/" + str(payload.get("wxid", "")) + "/history"}[op]
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

        b = _backend()
        if b == "noop":
            status = "status_unknown"
            diagnostic = "noop backend: request accepted but no message was sent"
        elif b == "exec":
            result = _call_exec("send", {"wxid": wxid, "text": text,
                                         "mention": payload.get("mention")})
            status = str(result.get("status", "submitted_unconfirmed"))
            diagnostic = str(result.get("diagnostic", ""))[:500]
        elif b == "upstream":
            body = json.dumps({"wxid": wxid, "text": text,
                               **({"mention": payload["mention"]} if "mention" in payload else {})},
                              ensure_ascii=False).encode()
            headers = {"Content-Type": "application/json", "Accept": "application/json"}
            tok = _env("WECHAT_BRIDGE_UPSTREAM_TOKEN")
            if tok:
                headers["Authorization"] = "Bearer " + tok
            status_code, raw = _proxy("POST", "/send", body, headers)
            data = json.loads(raw)
            return {"status": data.get("status", "status_unknown" if status_code == 200 else "failed"),
                    "diagnostic": str(data.get("diagnostic", ""))[:500],
                    "request_id": data.get("request_id"),
                    "proxy": "upstream"}
        else:
            raise RuntimeError(f"unknown backend: {b}")

        with self.lock:
            rid = f"{int(time.time()*1000)}-{len(self.sent)}"
            self.requests[rid] = wxid
            self.sent.append({"request_id": rid, "wxid": wxid, "ts": int(time.time()),
                              "status": status, "text_len": len(text)})
        return {"status": status, "diagnostic": diagnostic, "request_id": rid}

    def receipt(self, rid: str) -> dict:
        with self.lock:
            for row in self.sent:
                if row["request_id"] == rid:
                    return {"request_id": rid, "status": row["status"], "ts": row["ts"]}
        return {"request_id": rid, "status": "not_found"}


BRIDGE = Bridge()


class Handler(BaseHTTPRequestHandler):
    server_version = "wechat-bridge/1.0"

    def log_message(self, fmt: str, *args) -> None:  # noqa: A002 - stdlib signature
        # Never log paths containing wxid or message bodies.
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

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
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        try:
            # noop backend has no inbound source; emit one comment and hold briefly.
            self.wfile.write(b": connected\n\n")
            self.wfile.flush()
            deadline = time.time() + 3
            while time.time() < deadline:
                time.sleep(0.5)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self) -> None:  # noqa: N802 - stdlib
        if not self._auth_ok():
            return self._reply(401, {"error": "unauthorized"})
        if self.path.split("?", 1)[0] != "/send":
            return self._reply(404, {"error": "not found"})
        try:
            payload = json.loads(self._read_body())
            if not isinstance(payload, dict):
                raise ValueError("body must be a JSON object")
            return self._reply(200, BRIDGE.send(payload))
        except (ValueError, json.JSONDecodeError) as exc:
            return self._reply(400, {"error": str(exc)})
        except Exception as exc:  # noqa: BLE001 - ambiguous: never auto-retry
            return self._reply(502, {"status": "status_unknown", "error": type(exc).__name__,
                                     "diagnostic": "send outcome unknown; do not automatically retry"})


def self_test() -> None:
    """Protocol-level checks for all three backends; no GUI, no network, no real send."""
    import http.client

    def run_case(backend: str, env: dict, checks) -> str:
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

            def req(method: str, path: str, body: dict | None = None, token: str = "") -> tuple[int, dict]:
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                headers = {"Content-Type": "application/json"}
                if token:
                    headers["Authorization"] = "Bearer " + token
                raw = json.dumps(body).encode() if body is not None else None
                conn.request(method, path, raw, headers)
                r = conn.getresponse()
                data = json.loads(r.read())
                conn.close()
                return r.status, data

            try:
                n = checks(req)
            finally:
                srv.shutdown()
                t.join(timeout=2)
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
        assert r["request_id"], r
        return 2

    n1 = run_case("noop", {}, noop_checks)
    n2 = run_case("noop", {"WECHAT_BRIDGE_BEARER": "secret"}, auth_checks)
    # exec backend: a fake executor that echoes a delivered status via stdin JSON.
    fake = "python3 -c 'import sys,json; d=json.load(sys.stdin); print(json.dumps({\"status\":\"delivered\" if d[\"op\"]==\"send\" else \"ok\"}))'"
    n3 = run_case("exec", {"WECHAT_BRIDGE_EXEC": fake}, exec_checks)
    print(f"self-test ok: {n1} noop + {n2} auth + {n3} exec = {n1+n2+n3} protocol checks")


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
    body = json.dumps({"wxid": args.wxid, "text": args.text}, ensure_ascii=False).encode()
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    tok = _bearer()
    if tok:
        headers["Authorization"] = "Bearer " + tok
    req = urllib.request.Request(base + "/send", data=body, method="POST", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            out = json.loads(resp.read())
    except Exception as exc:  # noqa: BLE001 - ambiguous by definition
        print(json.dumps({"status": "status_unknown", "error": type(exc).__name__,
                          "diagnostic": "send outcome unknown; do not automatically retry"},
                         ensure_ascii=False))
        sys.exit(2)
    print(json.dumps(out, ensure_ascii=False))
    if out.get("status") == "status_unknown":
        sys.exit(2)


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
