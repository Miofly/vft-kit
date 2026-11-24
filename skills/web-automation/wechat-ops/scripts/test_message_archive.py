#!/usr/bin/env python3
"""Exercise the offline archive through fresh CLI processes, without using WeChat."""
from contextlib import closing
import csv
from html.parser import HTMLParser
import http.client
from io import StringIO
import json
import os
import re
import select
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
from urllib.parse import urlencode


def verify_http(db, expected, cursor, event_batches, idle_cursor, import_next):
    bridge = Path(__file__).with_name("wechat_bridge.py")
    env = {**os.environ, "WECHAT_BRIDGE_ARCHIVE_DB": str(db), "WECHAT_BRIDGE_BACKEND": "noop",
           "WECHAT_BRIDGE_BEARER": "archive-fixture-only"}
    before = db.read_bytes()
    count = 0
    with subprocess.Popen([sys.executable, "-I", str(bridge), "serve", "--port", "0"], env=env,
                          stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as proc:
        try:
            assert select.select([proc.stdout], [], [], 8)[0], "bridge did not start"
            address = re.fullmatch(rb"wechat-bridge on 127\.0\.0\.1:(\d+) backend=noop\s*", proc.stdout.readline(1024))
            assert address, "bridge is not bound to loopback"

            def request(path, status, *, method="GET", token="archive-fixture-only"):
                nonlocal count
                with closing(http.client.HTTPConnection("127.0.0.1", int(address[1]), timeout=5)) as conn:
                    headers = {"Authorization": "Bearer " + token} if token else {}
                    conn.request(method, path, headers=headers)
                    response = conn.getresponse()
                    row = json.load(response)
                assert response.status == status, (path, response.status, row)
                count += 1
                return row

            def stream(query, on_wait=None):
                nonlocal count
                with closing(http.client.HTTPConnection("127.0.0.1", int(address[1]), timeout=8)) as conn:
                    conn.request("GET", "/archive/events/stream?" + urlencode(query),
                                 headers={"Authorization": "Bearer archive-fixture-only"})
                    if on_wait is not None:
                        assert not select.select([conn.sock], [], [], 0.4)[0], "idle request replied before import"
                        on_wait()
                    response = conn.getresponse()
                    assert response.status == 200 and response.headers.get_content_type() == "text/event-stream"
                    assert response.headers.get("Cache-Control") == "no-store"
                    header, data, *tail = response.read().split(b"\n")
                    assert header == b"event: archive_batch" and data.startswith(b"data: ") and tail == [b"", b""]
                    count += 1
                    return json.loads(data[len(b"data: "):])

            for query, result in event_batches:
                assert stream(query) == result
            assert stream({"after": idle_cursor}) == {
                "status": "ok", "scope": "imported_messages", "complete_history": False,
                "live_wechat": False, "items": [], "cursor": idle_cursor, "has_more": False,
            }
            request("/archive/events/stream?after=" + cursor, 401, token="")
            request("/archive/events/stream?after=invalid", 400)
            request("/archive/events/stream?after=" + cursor + "&after=" + cursor, 400)

            for operation, query, result in expected:
                actual = request(f"/archive/{operation}?" + urlencode(query), 200)
                differing_fields = sorted(k for k in actual.keys() | result.keys() if actual.get(k) != result.get(k))
                assert actual == result, (operation, query.get("format", "json"), differing_fields)
            request("/archive/baseline", 401, token="")
            request("/archive/baseline", 401, token="wrong")
            request("/archive/history?chat=self&limit=2&limit=3", 400)
            request("/archive/history?chat=self&since=100&until=90", 400)
            request("/archive/search?query=%FF", 400)
            request("/archive/export?format=pdf", 400)
            request("/archive/events?after=" + cursor + "&db=other", 400)
            request("/archive/events?after=invalid", 400)
            request("/archive/events?" + urlencode({"after": cursor, "exclude_self": "1"}), 400)
            request("/archive/ingest", 501)
            request("/archive/ingest", 404, method="POST")
            db.chmod(0o644)
            try:
                request("/archive/baseline", 503)
            finally:
                db.chmod(0o600)
            db.rename(db.with_suffix(".unavailable"))
            try:
                request("/archive/baseline", 503)
            finally:
                db.with_suffix(".unavailable").rename(db)
            assert db.read_bytes() == before, "HTTP modified the archive"
            imported = []

            def write_fixture():
                imported.append(import_next())

            batch = stream({"after": idle_cursor}, on_wait=write_fixture)
            assert batch["items"] == [imported[0][0]] and not batch["has_more"]
            assert batch["cursor"] == imported[0][1] and batch["live_wechat"] is False
            assert db.read_bytes() == imported[0][2], "stream modified the archive after import"
        finally:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=5)
    return count


def main():
    script = Path(__file__).with_name("message_archive.py")
    with tempfile.TemporaryDirectory() as work:
        root = Path(work).resolve()
        db = root / "archive.sqlite3"
        count = 0

        def cli(*args, records=(), path=db, fail=False, document=None):
            nonlocal count
            proc = subprocess.run([sys.executable, "-I", str(script), "--db", str(path), *args],
                                  input=json.dumps(document) if document is not None else "".join(json.dumps(r) + "\n" for r in records),
                                  capture_output=True, text=True, timeout=5)
            result = json.loads(proc.stdout)
            assert proc.returncode == int(fail), (args, result)
            if fail:
                assert result["status"] == "failed", result
            else:
                assert result["scope"] == "imported_messages" and result["live_wechat"] is False
                assert result["complete_history"] is False
            count += 1
            return result

        def row(mid, *, chat="self", timestamp=100, text="测试", self_message=False):
            return dict(chat_id=chat, message_id=mid, timestamp=timestamp, sender_id="fixture",
                        from_self=self_message, kind="text", text=text)

        first = row("1", text="  =1+2,\"引号\"\r\n测试\n```\n<tag>&")
        same, late = row("2", self_message=True), row("3", timestamp=90)
        cross = {**row("1", chat="other"), "sender_id": "other-sender", "kind": "image"}
        cli("init", "--account", "a")
        assert db.stat().st_mode & 0o777 == 0o600
        cli("init", "--account", "b", fail=True)
        cli("ingest", "--account", "b", records=[first], fail=True)
        assert cli("ingest", "--account", "a", records=[first])["inserted"] == 1
        baseline = cli("baseline")["cursor"]
        assert cli("events", "--after", baseline)["items"] == []
        assert cli("ingest", "--account", "a", records=[same, late, cross])["inserted"] == 3
        duplicate = cli("ingest", "--account", "a", records=[first, same, late, cross])
        assert duplicate["inserted"] == 0 and duplicate["duplicates"] == 4
        page = cli("events", "--after", baseline, "--limit", "2")
        assert page["items"] == [same, late] and page["has_more"] is True
        last = cli("events", "--after", page["cursor"])
        assert last["items"] == [cross] and last["has_more"] is False
        assert cli("events", "--after", last["cursor"])["cursor"] == last["cursor"]
        assert cli("history", "--chat", "self")["items"] == [same, first, late]
        assert cli("history", "--chat", "self", "--since", "90", "--until", "100")["items"] == [late]
        assert cli("search", "测试")["items"] == [cross, same, first, late]
        assert cli("search", "%' OR 1=1 --")["items"] == []
        cli("ingest", "--account", "a", records=[row("new"), {**first, "text": "changed"}], fail=True)
        cli("ingest", "--account", "a", records=[row("new"), {**first, "timestamp": True}], fail=True)
        assert cli("baseline")["cursor"] == last["cursor"]  # Both batches left no partial write.
        cli("events", "--after", last["cursor"].split(":")[0] + ":99", fail=True)
        other = root / "other.sqlite3"
        cli("init", "--account", "a", path=other)
        cli("events", "--after", last["cursor"], path=other, fail=True)
        link = root / "link.sqlite3"
        link.symlink_to(db)
        cli("baseline", path=link, fail=True)
        unrelated = root / "unrelated.sqlite3"
        db2 = sqlite3.connect(unrelated)
        db2.execute("CREATE TABLE archive (generation TEXT, account TEXT)")
        db2.close()
        os.chmod(unrelated, 0o600)
        cli("baseline", path=unrelated, fail=True)
        stats = cli("stats", "--chat", "self", "--since", "90", "--until", "100", "--limit", "1")
        assert (stats["message_count"], stats["chat_count"], stats["sender_count"]) == (1, 1, 1)
        assert stats["by_kind"] == {"items": [{"kind": "text", "count": 1}], "has_more": False}
        assert stats["by_sender"] == {"items": [{"sender_id": "fixture", "count": 1}], "has_more": False}
        top = cli("stats", "--limit", "1")
        assert (top["message_count"], top["chat_count"], top["sender_count"]) == (4, 2, 2)
        assert top["by_kind"] == {"items": [{"kind": "text", "count": 3}], "has_more": True}
        assert top["by_sender"] == {"items": [{"sender_id": "fixture", "count": 3}], "has_more": True}
        empty = cli("stats", "--chat", "absent")
        assert empty["message_count"] == 0 and empty["by_sender"]["items"] == []
        assert empty["by_hour_utc"] == [0] * 24
        clock_rows = [row(str(t), chat="clock", timestamp=t) for t in (3599, 3600, 86399, 86400, 2**63 - 1)]
        cli("ingest", "--account", "a", path=other, records=clock_rows)
        clock = cli("stats", "--chat", "clock", "--since", "3599", "--until", "86400", "--limit", "1", path=other)
        assert clock["message_count"] == 3 and clock["by_hour_utc"] == [1, 1] + [0] * 21 + [1]
        clock_all = cli("stats", "--chat", "clock", path=other)
        expected_hours = clock["by_hour_utc"].copy()
        expected_hours[0] += 1
        expected_hours[(2**63 - 1) // 3600 % 24] += 1
        assert clock_all["by_hour_utc"] == expected_hours and sum(expected_hours) == clock_all["message_count"] == 5
        export = cli("export", "--chat", "self", "--limit", "2")
        assert export["format"] == "json" and export["has_more"] is True and export["items"] == [same, first]
        full_export = cli("export", "--chat", "self", "--limit", "3")
        assert full_export["has_more"] is False and full_export["items"] == [same, first, late]
        restored = root / "restored.sqlite3"
        cli("init", "--account", "a", path=restored)
        newest = cli("export", "--chat", "self", "--limit", "1")
        older = cli("export", "--chat", "self", "--cursor", newest["next_cursor"])

        def reimport(document, *, account="a", fail=False):
            return cli("ingest", "--account", account, "--format", "archive-json",
                       path=restored, document=document, fail=fail)

        reimport(newest, account="b", fail=True)
        reimport({**newest, "live_wechat": True}, fail=True)
        reimport({**newest, "items": [{**same, "from_self": 1}]}, fail=True)
        assert cli("history", "--chat", "self", path=restored)["items"] == []
        assert reimport(older)["inserted"] == 2
        assert reimport(newest)["inserted"] == 1
        assert reimport(full_export)["duplicates"] == 3
        assert cli("history", "--chat", "self", path=restored)["items"] == full_export["items"]
        reimport({**full_export, "items": [{**same, "text": "conflict"}, row("rollback")]}, fail=True)
        assert cli("history", "--chat", "self", path=restored)["items"] == full_export["items"]
        pinned = cli("export", "--chat", "self", "--limit", "1")
        assert pinned["items"] == [same]
        cursor = pinned["next_cursor"]
        assert cli("ingest", "--account", "a", records=[row("late-import", timestamp=95, text="new")])["inserted"] == 1
        tail = cli("export", "--chat", "self", "--cursor", cursor)
        assert tail["items"] == [first, late] and tail["next_cursor"] is None and tail["has_more"] is False
        cli("export", "--chat", "other", "--cursor", cursor, fail=True)
        cli("export", "--chat", "self", "--cursor", cursor, path=other, fail=True)
        cli("export", "--chat", "self", "--cursor", "malformed", fail=True)
        updated_stats = cli("stats", "--chat", "self", "--since", "90", "--until", "100", "--limit", "1")
        assert updated_stats["message_count"] == 2 and updated_stats["by_hour_utc"] == [2] + [0] * 23
        updated_events = cli("events", "--after", page["cursor"])
        assert updated_events["items"] == [cross, row("late-import", timestamp=95, text="new")]
        filtered = cli("events", "--after", baseline, "--chat", "self", "--exclude-self", "--limit", "1")
        assert filtered["items"] == [late] and filtered["has_more"] is True
        filtered_tail = cli("events", "--after", filtered["cursor"], "--chat", "self", "--exclude-self")
        assert filtered_tail["items"] == [row("late-import", timestamp=95, text="new")]
        assert not filtered_tail["has_more"]
        empty_events = cli("events", "--after", baseline, "--chat", "absent")
        assert empty_events["items"] == [] and empty_events["cursor"] == filtered_tail["cursor"]
        cli("events", "--after", baseline, "--chat", " ", fail=True)

        def markdown_items(result):
            assert result["format"] == "markdown" and "items" not in result
            lines = result["markdown"].split("\n")
            assert lines[:3] == ["# Imported messages", "", "```jsonl"] and lines[-2:] == ["```", ""]
            return list(map(json.loads, lines[3:-2]))

        md = cli("export", "--format", "markdown", "--chat", "self", "--limit", "2")
        assert markdown_items(md) == [same, first] and md["has_more"] is True
        md_cursor = md["next_cursor"]
        md_tail = cli("export", "--format", "markdown", "--chat", "self", "--cursor", md_cursor)
        assert markdown_items(md_tail) == [row("late-import", timestamp=95, text="new"), late]
        assert md_tail["next_cursor"] is None
        cli("export", "--chat", "self", "--cursor", md_cursor, fail=True)
        fields = ("chat_id", "message_id", "timestamp", "sender_id", "from_self", "kind", "text")
        html_page = cli("export", "--format", "html", "--chat", "self", "--limit", "1")
        html_tail = cli("export", "--format", "html", "--chat", "self", "--cursor", html_page["next_cursor"])
        assert html_page["has_more"] and not html_tail["has_more"]
        cli("export", "--format", "csv", "--chat", "self", "--cursor", html_page["next_cursor"], fail=True)
        assert html_tail["format"] == "html" and "items" not in html_tail
        assert "&lt;tag&gt;&amp;" in html_tail["html"] and "<tag>" not in html_tail["html"]

        class Cells(HTMLParser):
            def __init__(self):
                super().__init__()
                self.active = False
                self.cells = []

            def handle_starttag(self, tag, attrs):
                if tag == "pre":
                    self.cells.append("")
                    self.active = True

            def handle_data(self, data):
                if self.active:
                    self.cells[-1] += data

            def handle_endtag(self, tag):
                if tag == "pre":
                    self.active = False

        for html_result, records in ((html_page, [same]),
                                     (html_tail, [first, row("late-import", timestamp=95, text="new"), late])):
            parser = Cells()
            parser.feed(html_result["html"])
            parser.close()
            assert parser.cells == [str(item[key]) for item in records for key in fields]
        csv_page = cli("export", "--format", "csv", "--chat", "self", "--limit", "2")
        assert csv_page["format"] == "csv" and "items" not in csv_page and csv_page["has_more"]
        assert list(csv.reader(StringIO(csv_page["csv"], newline=""), strict=True)) == [list(fields),
            [str(same[k]) for k in fields], [str(first[k]) for k in fields[:-1]] + ["'" + first["text"]]]
        csv_tail = cli("export", "--format", "csv", "--chat", "self", "--cursor", csv_page["next_cursor"])
        assert not csv_tail["has_more"] and csv_tail["next_cursor"] is None
        assert list(csv.reader(StringIO(csv_tail["csv"], newline=""), strict=True)) == [list(fields),
            [str(row("late-import", timestamp=95, text="new")[k]) for k in fields], [str(late[k]) for k in fields]]
        def import_next():
            item = row("import-during-wait", timestamp=89)
            assert cli("ingest", "--account", "a", records=[item])["inserted"] == 1
            return item, cli("baseline")["cursor"], db.read_bytes()

        http_calls = verify_http(db, [
            ("baseline", {}, cli("baseline")),
            ("export", {"format": "html", "chat": "self", "limit": 1}, html_page),
            ("export", {"format": "html", "chat": "self", "cursor": html_page["next_cursor"]}, html_tail),
            ("export", {"format": "csv", "chat": "self", "limit": 2}, csv_page),
            ("export", {"format": "csv", "chat": "self", "cursor": csv_page["next_cursor"]}, csv_tail),
            ("export", {"format": "markdown", "chat": "self", "limit": 2}, md),
            ("export", {"format": "markdown", "chat": "self", "cursor": md_cursor}, md_tail),
            ("export", {"chat": "self", "limit": 2}, cli("export", "--chat", "self", "--limit", "2")),
            ("export", {"chat": "self", "cursor": cursor}, tail),
            ("stats", {"chat": "self", "since": 90, "until": 100, "limit": 1}, updated_stats),
            ("history", {"chat": "self", "since": 90, "until": 100},
             cli("history", "--chat", "self", "--since", "90", "--until", "100")),
            ("search", {"query": "测试"}, cli("search", "测试")),
            ("events", {"after": baseline, "limit": 2}, page),
            ("events", {"after": page["cursor"]}, updated_events),
            ("events", {"after": baseline, "chat": "self", "exclude_self": "true", "limit": 1}, filtered),
            ("events", {"after": filtered["cursor"], "chat": "self", "exclude_self": "true"}, filtered_tail),
            ("events", {"after": baseline, "chat": "absent"}, empty_events),
        ], baseline, [
            ({"after": baseline, "chat": "self", "exclude_self": "true", "limit": 1}, filtered),
            ({"after": filtered["cursor"], "chat": "self", "exclude_self": "true"}, filtered_tail),
        ], updated_events["cursor"], import_next)
        print(json.dumps({"status": "passed", "cli_calls": count, "http_calls": http_calls,
                          "input": "synthetic_jsonl", "live_wechat": False}))


if __name__ == "__main__":
    main()
