#!/usr/bin/env python3
"""Compare WeChat desktop CLI, HTTP and MCP reads without printing private labels."""
from __future__ import annotations

import argparse
from collections import Counter
from contextlib import closing
import csv
import html.parser
import http.client
import io
import json
import os
from pathlib import Path
import re
import secrets
import select
import subprocess
import sys
import urllib.parse

FORMATS = ("json", "markdown", "html", "csv")


class Blocked(RuntimeError):
    pass


def require(condition, check):
    if not condition:
        raise ValueError(check)


class HTMLLabels(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.labels = []
        self.current = None

    def handle_starttag(self, tag, attrs):
        if self.current is not None:
            raise ValueError("unexpected markup in exported HTML label")
        if tag == "li":
            self.current = []

    def handle_data(self, data):
        if self.current is not None:
            self.current.append(data)

    def handle_endtag(self, tag):
        if tag == "li" and self.current is not None:
            self.labels.append("".join(self.current))
            self.current = None


def verify_export(row, fmt, labels):
    require(row.get("format") == fmt and row.get("match_count") == len(labels), fmt + " metadata mismatch")
    if fmt == "json":
        actual = [item["label"] for item in row["items"]]
    elif fmt == "markdown":
        parts = row["markdown"].split("\n", 3)
        fence = parts[2].removesuffix("text")
        require(len(fence) >= 3 and set(fence) == {"`"}, "markdown fence missing")
        actual = parts[3]
        labels = "\n\n".join(labels) + f"\n{fence}\n"
    elif fmt == "html":
        parser = HTMLLabels()
        parser.feed(row["html"])
        parser.close()
        require(parser.current is None, "unclosed HTML label")
        actual = parser.labels
    else:
        actual = list(csv.reader(io.StringIO(row["csv"], newline=""), strict=True))
        labels = [["label"]] + [[("'" if text.startswith(("\t", "\r", "\n"))
                                  or text.strip()[:1] in set("=+-@＝＋－＠") else "") + text] for text in labels]
    require(actual == labels, fmt + " export differs from the visible history")


def verify(bridge, binary, sessions_only=False, filehelper_only=False, badge_only=False, label_view=None,
           readiness_only=False):
    token = secrets.token_urlsafe(32)
    env = {**os.environ, "WECHAT_BRIDGE_BACKEND": "desktop", "WECHAT_BRIDGE_DESKTOP_BIN": str(binary),
           "WECHAT_BRIDGE_BEARER": token}
    # A mistaken write must not reach the desktop sender with a usable receipt directory.
    env.pop("WECHAT_DESKTOP_STATE_DIR", None)
    env.pop("WECHAT_BRIDGE_DESKTOP_PHOTO_DIR", None)
    command = [sys.executable, "-I", str(bridge)]
    query = urllib.parse.urlencode({"query": "图片", "limit": 100})
    with subprocess.Popen([*command, "serve", "--port", "0"], env=env, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as server:
        try:
            require(select.select([server.stdout], [], [], 8)[0], "bridge startup timed out")
            line = server.stdout.readline(1024).decode()
            match = re.fullmatch(r"wechat-bridge on 127\.0\.0\.1:(\d+) backend=desktop\s*", line)
            require(match, "bridge did not start on loopback")
            port = int(match[1])

            def get(path, auth=True):
                with closing(http.client.HTTPConnection("127.0.0.1", port, timeout=28)) as conn:
                    conn.request("GET", path, headers={"Authorization": "Bearer " + token} if auth else {})
                    response = conn.getresponse()
                    return response.status, json.load(response)

            if readiness_only:
                path = "/desktop/readiness"
                status, row = get(path)
                if status == 503:
                    raise Blocked("desktop readiness probe unavailable")
                flags = {"main_window_readable", "sessions_readable", "contacts_labels_readable",
                         "moments_labels_readable", "unread_badge_readable", "positive_unread_badge",
                         "filehelper_readable", "live_wechat", "sent"}
                require(status == 200 and set(row) == flags | {"status", "scope", "bundle_id"}
                        and row["status"] == "ok" and row["scope"] == "desktop_snapshot_readiness"
                        and row["bundle_id"] == env.get("WECHAT_DESKTOP_BUNDLE_ID", "com.tencent.xinWeChat")
                        and all(type(row[k]) is bool for k in flags)
                        and not row["live_wechat"] and not row["sent"], "wrong desktop readiness response")
                cli = subprocess.run([str(binary)], env=env, input=b'{"op":"readiness"}',
                                     capture_output=True, timeout=28, check=True)
                if get(path) != (200, row):
                    raise Blocked("desktop readiness changed during comparison")
                require(json.loads(cli.stdout) == row, "readiness differs across HTTP and CLI")
                require(get(path, False)[0] == 401 and get(path + "?limit=1")[0] == 400,
                        "readiness auth or parameter validation failed")
                return {**row, "status": "passed", "http_scenarios": 4, "cli_reads": 1}

            if label_view:
                contacts = label_view == "contact"
                scope = label_view + "_list_ax_labels"
                complete = "complete_contacts" if contacts else "complete_moments"
                op = label_view + "_labels"
                path = "/desktop/" + label_view + "-labels"
                status, row = get(path)
                if status == 503:
                    raise Blocked(label_view + " labels unavailable: selected WeChat window or list is not readable in the background")
                require(status == 200 and row.get("scope") == scope and row.get(complete) is False,
                        "wrong label list scope")
                items = row["items"]
                require(items and all(set(x) == {"label"} and isinstance(x["label"], str) for x in items),
                        "no verifiable contact labels")
                payload = {"op": op}
                cli = subprocess.run([str(binary)], env=env, input=json.dumps(payload).encode(),
                                     capture_output=True, timeout=28, check=True)
                requests = [
                    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
                    {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "desktop_" + op}},
                ]
                mcp = subprocess.run([*command, "desktop-mcp"], env=env, text=True, capture_output=True,
                                     input="\n".join(map(json.dumps, requests)) + "\n", timeout=30, check=True)
                reply = json.loads(mcp.stdout.splitlines()[1])["result"]
                tui = subprocess.run([*command, "desktop-tui"], env=env, text=True, capture_output=True,
                                     input=op + "\nquit\n", timeout=30, check=True)
                limited = get(path + "?limit=1")
                sample = next((line.strip() for line in items[0]["label"].splitlines() if line.strip()), "")[:16]
                require(sample, "missing label search sample")
                found = get(path + "?" + urllib.parse.urlencode({"query": sample}))
                absent = get(path + "?query=" + secrets.token_hex(16))
                if get(path) != (200, row):
                    raise Blocked("labels changed during verification")
                require(not reply.get("isError") and row == json.loads(cli.stdout) == json.loads(tui.stdout)
                        == json.loads(reply["content"][0]["text"]), "labels differ across interfaces")
                require(limited[0] == 200 and limited[1]["items"] == items[:1], "label limit mismatch")
                require(found[0] == 200 and items[0] in found[1]["items"], "visible label did not match")
                require(absent[0] == 200 and absent[1]["match_count"] == 0 and absent[1]["items"] == [],
                        "absent label matched")
                require(get(path, False)[0] == 401, "label authorization changed")
                if contacts:
                    require(get("/contacts")[0] == 501, "full contact scope changed")
                return {"status": "passed", "scope": row["scope"], "http_scenarios": 6 + contacts, "cli_reads": 1,
                        "mcp_tools": 1, "terminal_reads": 1, "visible_labels": row["scanned_count"],
                        complete: False, "sent": False}

            if badge_only:
                path = "/desktop/unread-badge"

                def cli_badge():
                    proc = subprocess.run([str(binary)], env=env, input=b'{"op":"unread_badge"}',
                                          capture_output=True, timeout=28)
                    row = json.loads(proc.stdout)
                    if proc.returncode == 1 and row.get("status") == "failed":
                        raise Blocked("chat sidebar badge is not currently readable")
                    require(proc.returncode == 0, "badge CLI read failed")
                    return row

                before = cli_badge()
                status, row = get(path)
                if status == 503:
                    raise Blocked("chat sidebar badge became unreadable")
                require(status == 200, "badge HTTP read failed")
                mcp_requests = [
                    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
                    {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "desktop_unread_badge"}},
                ]
                mcp = subprocess.run([*command, "desktop-mcp"], env=env, text=True, capture_output=True,
                                     input="\n".join(map(json.dumps, mcp_requests)) + "\n", timeout=30, check=True)
                mcp_rows = {r["id"]: r["result"] for r in map(json.loads, mcp.stdout.splitlines())}
                tui = subprocess.run([*command, "desktop-tui"], env=env, text=True, capture_output=True,
                                     input="unread_badge\nquit\n", timeout=30, check=True)
                terminal = json.loads(tui.stdout)
                after = cli_badge()
                if before != after or mcp_rows[2].get("isError") or terminal.get("status") == "unavailable":
                    raise Blocked("chat sidebar badge changed or became unreadable during verification")
                mcp_badge = json.loads(mcp_rows[2]["content"][0]["text"])
                require(row == before == mcp_badge == terminal and row.get("status") == "ok"
                        and row.get("scope") == "chat_sidebar_badge" and row.get("complete_unread") is False,
                        "badge results mismatch across HTTP, CLI, MCP or terminal")
                count = row["badge_count"]
                if count is None:
                    raise Blocked("no positive sidebar badge to verify")
                require(type(count) is int and count > 0, "unexpected badge value")
                require(get(path, False)[0] == 401, "missing badge bearer was not rejected")
                require(get("/unread")[0] == 501, "per-chat unread must not return the sidebar badge")
                return {"status": "passed", "scope": "chat_sidebar_badge", "http_scenarios": 3,
                        "cli_reads": 2, "mcp_tools": 1, "terminal_reads": 1,
                        "complete_unread": False, "sent": False}

            history_path = "/chat/filehelper/history?limit=100"
            auth_path = history_path if filehelper_only else "/chats"
            require(get(auth_path, False)[0] == 401, "missing bearer was not rejected")

            def read(path):
                status, row = get(path)
                route = path.split("?", 1)[0]
                if status == 503:
                    raise Blocked("background snapshot unavailable: " + route)
                require(status == 200, "HTTP read failed: " + route)
                return row

            checks = []
            chats = []
            if not filehelper_only:
                session_path = "/chats?limit=100"
                sessions = read(session_path)
                require(sessions.get("scope") == "session_list_ax_snapshot" and sessions.get("complete_sessions") is False,
                        "wrong session scope")
                chats = sessions["chats"]
                if not chats:
                    raise Blocked("no session names to compare in the current snapshot")
                require(all(set(chat) == {"name"} and isinstance(chat["name"], str) and chat["name"] for chat in chats),
                        "unexpected session list fields")
                limited = read("/chats?limit=1")["chats"]
                if read(session_path) != sessions:
                    raise Blocked("session list changed during limit verification")
                require(limited == chats[:1], "session limit mismatch")
                name = chats[0]["name"]
                count = sum(chat["name"] == name for chat in chats)
                match = read("/resolve?" + urllib.parse.urlencode({"hint": name, "limit": 1}))
                resolved_count = match.get("match_count")
                require(type(resolved_count) is int and resolved_count >= count
                        and (sessions["scanned_count"] > len(chats) or resolved_count == count)
                        and match.get("resolution") == ("unique_in_snapshot" if resolved_count == 1 else "ambiguous")
                        and match.get("candidates") == [{"name": name}], "exact session resolution mismatch")
                absent = "verification-" + secrets.token_hex(16)
                require(all(chat["name"] != absent for chat in chats), "verification name unexpectedly present")
                miss = read("/resolve?" + urllib.parse.urlencode({"hint": absent}))
                require(miss.get("resolution") == "not_found_in_snapshot" and miss.get("match_count") == 0
                        and miss.get("candidates") == [], "missing session name was not rejected")
                if read(session_path) != sessions:
                    raise Blocked("session list changed during verification; no stable comparison")

                checks = [("desktop_chats", {"limit": 100}, sessions),
                          ("desktop_resolve", {"hint": name, "limit": 1}, match),
                          ("desktop_resolve", {"hint": absent}, miss)]
            if not sessions_only:
                baseline = read(history_path)
                require(baseline.get("scope") == "visible_ax_labels" and baseline.get("complete_history") is False,
                        "wrong history scope")
                labels = [item["label"] for item in baseline["items"]]
                if not labels:
                    raise Blocked("no visible labels to compare; an empty snapshot cannot pass business verification")
                observed = {"history": baseline, "search": read("/desktop/search?" + query),
                            "stats": read("/desktop/stats?limit=100")}
                recent = read("/chat/filehelper?limit=100")
                for fmt in FORMATS:
                    observed[fmt] = read(f"/desktop/export?format={fmt}&limit=100")
                checks.extend([("filehelper_history", {"limit": 100}, baseline),
                               ("filehelper_search", {"limit": 100, "query": "图片"}, observed["search"]),
                               ("filehelper_stats", {"limit": 100}, observed["stats"]),
                               *(("filehelper_export", {"limit": 100, "format": fmt}, observed[fmt]) for fmt in FORMATS)])

            def check_stable():
                if ((not filehelper_only and read(session_path) != sessions)
                        or (not sessions_only and read(history_path) != baseline)):
                    raise Blocked("history or session snapshot changed during verification")

            def rpc(rid, method, params):
                return {"jsonrpc": "2.0", "id": rid, "method": method, "params": params}

            initial = [rpc(1, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                        "clientInfo": {"name": "wechat-desktop-verifier", "version": "1"}}),
                       {"jsonrpc": "2.0", "method": "notifications/initialized"}, rpc(2, "tools/list", {})]
            calls = [rpc(i, "tools/call", {"name": tool, "arguments": args})
                     for i, (tool, args, _) in enumerate(checks, 3)]
            wire = "".join(json.dumps(row) + "\n" for row in initial + calls)
            mcp = subprocess.run([*command, "desktop-mcp"], env=env, input=wire, text=True,
                                 capture_output=True, timeout=280, check=True)
            rows = {row["id"]: row["result"] for row in map(json.loads, mcp.stdout.splitlines())}
            require(len(rows) == len(checks) + 2 and rows[1]["protocolVersion"] == "2025-06-18", "MCP handshake mismatch")
            tools = {tool for tool, _, _ in checks}
            allowed_tools = {"desktop_chats", "desktop_resolve", "filehelper_history", "filehelper_search",
                             "filehelper_stats", "filehelper_export", "desktop_unread_badge",
                             "desktop_contact_labels", "desktop_moments_labels"}
            require({t["name"] for t in rows[2]["tools"]} == allowed_tools, "MCP read-only tool set mismatch")
            check_stable()
            cli_reads = []
            for i, (tool, args, expected) in enumerate(checks, 3):
                require(not rows[i].get("isError"), "MCP read failed: " + tool)
                require(json.loads(rows[i]["content"][0]["text"]) == expected, "HTTP/MCP mismatch: " + tool)
                family, op = tool.split("_", 1)
                request = {"op": op, **args}
                if family == "filehelper":
                    request["recipient"] = "filehelper"
                proc = subprocess.run([str(binary)], env=env, input=json.dumps(request), text=True,
                                      capture_output=True, timeout=28)
                row = json.loads(proc.stdout)
                if proc.returncode == 1 and row.get("status") == "failed":
                    raise Blocked("desktop CLI read unavailable: " + tool)
                require(proc.returncode == 0, "desktop CLI read failed: " + tool)
                cli_reads.append((tool, row, expected))
            check_stable()
            for tool, row, expected in cli_reads:
                require(row == expected, "HTTP/CLI mismatch: " + tool)

            tui_commands, tui_requests = [], []
            if not filehelper_only:
                tui_commands.extend(["chats", "resolve " + name])
                tui_requests.extend([{"op": "chats"}, {"op": "resolve", "hint": name}])
            if not sessions_only:
                tui_commands.extend(["history", "search 图片", "stats", *("export " + fmt for fmt in FORMATS)])
                tui_requests.extend([{"op": "history", "recipient": "filehelper"},
                                     {"op": "search", "query": "图片", "recipient": "filehelper"},
                                     {"op": "stats", "recipient": "filehelper"},
                                     *({"op": "export", "format": fmt, "recipient": "filehelper"} for fmt in FORMATS)])
            tui = subprocess.run([*command, "desktop-tui"], env=env,
                                 input="\n".join([*tui_commands, "send invalid", "quit", "chats", ""]),
                                 text=True, capture_output=True, timeout=250, check=True)
            tui_rows = list(map(json.loads, tui.stdout.splitlines()))
            require(len(tui_rows) == len(tui_commands) + 1 and tui_rows[-1].get("status") == "failed",
                    "terminal console did not reject sending or stop at quit")
            for request, row in zip(tui_requests, tui_rows):
                proc = subprocess.run([str(binary)], env=env, input=json.dumps(request), text=True,
                                      capture_output=True, timeout=28)
                cli_row = json.loads(proc.stdout)
                if cli_row.get("status") == "failed" or row.get("status") == "unavailable":
                    raise Blocked("terminal snapshot became unavailable")
                require(proc.returncode == 0 and row == cli_row, "terminal/CLI mismatch: " + request["op"])
            check_stable()
            if sessions_only:
                return {"status": "passed", "scope": "sessions_only", "http_scenarios": 5,
                        "mcp_tools": len(tools), "cli_reads": len(cli_reads), "terminal_reads": len(tui_commands),
                        "session_names": len(chats), "complete_sessions": False, "sent": False}

            require(all(row.get("scope") == "visible_ax_labels" and row.get("complete_history") is False
                        for row in observed.values()), "wrong history scope")
            require(recent == baseline, "recent history mismatch")
            require(observed["search"]["items"] == [{"label": text} for text in labels if "图片" in text], "search mismatch")
            require(observed["stats"]["label_frequencies"] == sorted(Counter(labels).values(), reverse=True), "stats mismatch")
            for fmt in FORMATS:
                verify_export(observed[fmt], fmt, labels)
            report = {"status": "passed", "http_scenarios": 9 if filehelper_only else 12,
                      "mcp_tools": len(tools), "cli_reads": len(cli_reads),
                      "terminal_reads": len(tui_commands), "formats": list(FORMATS),
                      "visible_labels": len(labels), "complete_history": False, "sent": False}
            if filehelper_only:
                report["scope"] = "filehelper_only"
            else:
                report.update(session_names=len(chats), complete_sessions=False)
            return report
        finally:
            if server.poll() is None:
                server.terminate()
                server.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--desktop-bin", type=Path, required=True)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--readiness-only", action="store_true", help="compare the desktop readiness report without changing views")
    modes.add_argument("--sessions-only", action="store_true", help="verify sessions without opening or reading a chat")
    modes.add_argument("--filehelper-only", action="store_true", help="verify filehelper reads without listing sessions")
    modes.add_argument("--badge-only", action="store_true", help="verify a positive sidebar badge without reading chat rows")
    modes.add_argument("--contacts-only", dest="label_view", action="store_const", const="contact",
                       help="verify labels from the already open Contacts view")
    modes.add_argument("--moments-only", dest="label_view", action="store_const", const="moments",
                       help="verify labels from the already open Moments view")
    args = parser.parse_args()
    if not args.desktop_bin.is_absolute() or not args.desktop_bin.is_file() or not os.access(args.desktop_bin, os.X_OK):
        parser.error("provide a trusted executable desktop sender by absolute path")
    try:
        report = verify(Path(__file__).with_name("wechat_bridge.py").resolve(), args.desktop_bin,
                        args.sessions_only, args.filehelper_only, args.badge_only, args.label_view,
                        readiness_only=args.readiness_only)
    except Blocked as exc:
        print(json.dumps({"status": "blocked", "reason": str(exc), "sent": False}))
        return 2
    except (OSError, ValueError, KeyError, IndexError, TypeError, http.client.HTTPException, subprocess.SubprocessError):
        print(json.dumps({"status": "failed", "reason": "read-only protocol or comparison failed", "sent": False}))
        return 1
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
