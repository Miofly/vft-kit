#!/usr/bin/env python3
"""Private, offline message archive. Ingests explicit records or its own JSON export pages; never reads WeChat."""
from __future__ import annotations

import argparse
from contextlib import closing
import csv
import hashlib
from html import escape
from io import StringIO
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import sys
import uuid

MAX_BATCH = 8 * 1024 * 1024
APPLICATION_ID = 0x57584152  # WXAR, identifies this archive format, not WeChat databases.
SCOPE = {"scope": "imported_messages", "complete_history": False, "live_wechat": False}
FIELDS = ("chat_id", "message_id", "timestamp", "sender_id", "from_self", "kind", "text")
EXPORT_FORMATS = ("json", "markdown", "html", "csv")
SCHEMA = """
CREATE TABLE archive (generation TEXT NOT NULL, account TEXT NOT NULL);
CREATE TABLE messages (
    seq INTEGER PRIMARY KEY, chat_id TEXT NOT NULL, message_id TEXT NOT NULL,
    timestamp INTEGER NOT NULL, sender_id TEXT NOT NULL, from_self INTEGER NOT NULL,
    kind TEXT NOT NULL, text TEXT NOT NULL, UNIQUE(chat_id, message_id)
);
CREATE INDEX messages_time ON messages(timestamp DESC, seq DESC);
"""


class Refused(ValueError):
    pass


class ArchiveUnavailable(Refused):
    pass


def private_path(path: Path) -> None:
    if not path.is_absolute() or path.parent.resolve(strict=True) != path.parent:
        raise ArchiveUnavailable("use an absolute archive path in a private directory without symlinks")
    info = path.parent.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ArchiveUnavailable("archive directory must be owned by the current user and have mode 0700")


def check_string(value, maximum, *, required=True):
    return (isinstance(value, str) and len(value) <= maximum and "\x00" not in value
            and not any(0xD800 <= ord(c) <= 0xDFFF for c in value)
            and (not required or bool(value.strip())))


def parse_batch(source, fmt):
    data = source.read(MAX_BATCH + 1)
    if not data or len(data) > MAX_BATCH:
        raise Refused("provide UTF-8 input up to 8 MiB")
    text = data.decode("utf-8")
    if fmt == "archive-json":
        page = json.loads(text)
        if (not isinstance(page, dict) or page.get("status") != "ok" or page.get("format") != "json"
                or page.get("scope") != SCOPE["scope"] or page.get("live_wechat") is not False
                or page.get("complete_history") is not False or not isinstance(page.get("items"), list)
                or type(page.get("has_more")) is not bool or "next_cursor" not in page
                or (not isinstance(page["next_cursor"], str) if page["has_more"] else page["next_cursor"] is not None)):
            raise Refused("provide a JSON page from this archive's export command")
        # Export is newest-first; insert in reverse so equal timestamps retain page order.
        rows = reversed(page["items"])
    else:
        rows = (json.loads(line) for line in text.split("\n") if line.strip())
    records = []
    for row in rows:
        if (not isinstance(row, dict) or set(row) != set(FIELDS)
                or not all(check_string(row[k], 256) for k in ("chat_id", "message_id", "sender_id", "kind"))
                or type(row["timestamp"]) is not int or not 0 <= row["timestamp"] <= 2**63 - 1
                or type(row["from_self"]) is not bool or not check_string(row["text"], 65_536, required=False)):
            raise Refused("invalid record; no rows imported")
        records.append(tuple(row[k] for k in FIELDS))
        if len(records) > 10_000:
            raise Refused("batch cannot exceed 10000 records")
    if not records:
        raise Refused("no records supplied")
    return records


def initialize(path: Path, account: str):
    if not check_string(account, 256):
        raise Refused("account is required")
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(fd)
    try:
        with closing(sqlite3.connect(path)) as db, db:
            db.executescript(f"BEGIN IMMEDIATE; PRAGMA application_id={APPLICATION_ID};" + SCHEMA)
            db.execute("INSERT INTO archive VALUES (?, ?)", (uuid.uuid4().hex, account))
    except (OSError, sqlite3.Error):
        path.unlink()
        raise
    return {"status": "ok", **SCOPE}


def run(db, args, source):
    generation, account = db.execute("SELECT generation, account FROM archive").fetchone()
    result = {"status": "ok", **SCOPE}
    if args.op == "ingest":
        if args.account != account:
            raise Refused("account does not match this archive")
        records = parse_batch(source, args.format)
        inserted = 0
        with db:
            db.execute("BEGIN IMMEDIATE")
            for row in records:
                prior = db.execute("SELECT timestamp,sender_id,from_self,kind,text FROM messages "
                                   "WHERE chat_id=? AND message_id=?", row[:2]).fetchone()
                if prior is None:
                    db.execute("INSERT INTO messages (" + ",".join(FIELDS) + ") VALUES (?,?,?,?,?,?,?)", row)
                    inserted += 1
                elif prior != row[2:]:
                    raise Refused("message identity conflict; batch rolled back")
        return {**result, "inserted": inserted, "duplicates": len(records) - inserted}
    if args.op == "baseline":
        latest = db.execute("SELECT coalesce(max(seq),0) FROM messages").fetchone()[0]
        return {**result, "cursor": f"{generation}:{latest}"}
    if args.op == "events":
        match = re.fullmatch(r"([a-f0-9]{32}):([0-9]{1,19})", args.after)
        if not match or match[1] != generation:
            raise Refused("cursor does not belong to this archive")
        after = int(match[2])
        latest = db.execute("SELECT coalesce(max(seq),0) FROM messages").fetchone()[0]
        if after > latest:
            raise Refused("cursor is ahead of this archive")
        # Bound the scan before skipping filtered rows so a concurrent import is never acknowledged unseen.
        where, params = "seq>? AND seq<=?", [after, latest]
        if args.chat is not None:
            where += " AND chat_id=?"
            params.append(args.chat)
        if args.exclude_self:
            where += " AND from_self=0"
        rows = db.execute("SELECT seq," + ",".join(FIELDS) + " FROM messages WHERE " + where +
                          " ORDER BY seq LIMIT ?", [*params, args.limit + 1]).fetchall()
        page = rows[:args.limit]
        more = len(rows) > len(page)
        return {**result, "items": [message(row[1:]) for row in page],
                "cursor": f"{generation}:{page[-1][0] if more else latest}", "has_more": more}
    conditions, params = [], []
    for condition, value in (("chat_id=?", args.chat), ("timestamp>=?", args.since), ("timestamp<?", args.until),
                             ("instr(text,?)>0", getattr(args, "query", None))):
        if value is not None:
            conditions.append(condition)
            params.append(value)
    if args.op == "export":
        # Freeze membership by ingest sequence, then page in the same order as history.
        filters = [args.chat, args.since, args.until]
        if args.format != "json":
            filters.append(args.format)
        fingerprint = hashlib.sha256(json.dumps(filters).encode()).hexdigest()
        latest = db.execute("SELECT coalesce(max(seq),0) FROM messages").fetchone()[0]
        watermark = latest
        if args.cursor is not None:
            match = re.fullmatch(r"export1:([a-f0-9]{32}):([a-f0-9]{64}):([0-9]{1,19}):([0-9]{1,19}):([0-9]{1,19})", args.cursor)
            if not match or match[1] != generation or match[2] != fingerprint:
                raise Refused("export cursor does not match this archive or query")
            watermark, timestamp, sequence = map(int, match.groups()[2:])
            if not 1 <= sequence <= watermark <= latest or timestamp > 2**63 - 1:
                raise Refused("invalid export cursor position")
            conditions.append("(timestamp,seq)<(?,?)")
            params.extend((timestamp, sequence))
        conditions.append("seq<=?")
        params.append(watermark)
        rows = db.execute("SELECT seq," + ",".join(FIELDS) + " FROM messages WHERE " + " AND ".join(conditions)
                          + " ORDER BY timestamp DESC,seq DESC LIMIT ?", [*params, args.limit + 1]).fetchall()
        page = rows[:args.limit]
        more = len(rows) > len(page)
        cursor = f"export1:{generation}:{fingerprint}:{watermark}:{page[-1][3]}:{page[-1][0]}" if more else None
        items = [message(row[1:]) for row in page]
        result.update(format=args.format, has_more=more, next_cursor=cursor)
        if args.format == "markdown":
            # JSON lines start with '{'; even a message containing a fence cannot end this block.
            lines = "".join(json.dumps(item, ensure_ascii=False) + "\n" for item in items)
            result["markdown"] = "# Imported messages\n\n```jsonl\n" + lines + "```\n"
        elif args.format == "html":
            header = "".join(f"<th scope=\"col\">{column}</th>" for column in FIELDS)
            body = "".join("<tr>" + "".join(f"<td><pre>{escape(str(item[k]))}</pre></td>" for k in FIELDS) + "</tr>\n"
                           for item in items)
            result["html"] = ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
                              "<title>Imported messages</title></head><body><table><caption>Imported messages</caption>"
                              "<thead><tr>" + header + "</tr></thead><tbody>\n" + body + "</tbody></table></body></html>\n")
        elif args.format == "csv":
            stream = StringIO(newline="")
            writer = csv.writer(stream)
            writer.writerow(FIELDS)
            writer.writerows([csv_cell(item[k]) for k in FIELDS] for item in items)
            result["csv"] = stream.getvalue()
        else:
            result["items"] = items
        return result
    where = " WHERE " + " AND ".join(conditions) if conditions else ""
    if args.op == "stats":
        # One read transaction keeps totals and breakdowns on the same import generation.
        db.execute("BEGIN")
        total, chats, senders = db.execute(
            "SELECT count(*),count(DISTINCT chat_id),count(DISTINCT sender_id) FROM messages" + where, params
        ).fetchone()
        breakdowns = {}
        for column in ("kind", "sender_id"):
            counts = db.execute(f"SELECT {column},count(*) AS n FROM messages{where} "
                                f"GROUP BY {column} ORDER BY n DESC,{column} LIMIT ?",
                                [*params, args.limit + 1]).fetchall()
            breakdowns[column] = {"items": [{column: key, "count": count} for key, count in counts[:args.limit]],
                                  "has_more": len(counts) > args.limit}
        by_hour = [0] * 24
        for hour, count in db.execute("SELECT timestamp / 3600 % 24 AS hour,count(*) FROM messages" + where
                                      + " GROUP BY hour", params):
            by_hour[hour] = count
        return {**result, "message_count": total, "chat_count": chats, "sender_count": senders,
                "by_kind": breakdowns["kind"], "by_sender": breakdowns["sender_id"], "by_hour_utc": by_hour}
    rows = db.execute("SELECT " + ",".join(FIELDS) + " FROM messages" + where +
                      " ORDER BY timestamp DESC,seq DESC LIMIT ?", [*params, args.limit]).fetchall()
    return {**result, "items": [message(row) for row in rows]}


def csv_cell(value):
    if isinstance(value, str) and (value.startswith(("\t", "\r", "\n")) or value.lstrip()[:1] in ("=", "+", "-", "@", "＝", "＋", "－", "＠")):
        return "'" + value
    return value


def message(row):
    data = dict(zip(FIELDS, row))
    data["from_self"] = bool(data["from_self"])
    return data


def open_archive(path: Path, *, write=False):
    private_path(path)
    info = path.lstat()
    if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != 0o600):
        raise ArchiveUnavailable("archive must be a private, singly linked, regular file with mode 0600")
    db = sqlite3.connect(f"{path.as_uri()}?mode={'rw' if write else 'ro'}", uri=True)
    try:
        db.execute("PRAGMA trusted_schema=OFF")
        if db.execute("PRAGMA application_id").fetchone()[0] != APPLICATION_ID:
            raise ArchiveUnavailable("not a message archive created by this command")
    except (sqlite3.Error, Refused):
        db.close()
        raise
    return closing(db)


def query_archive(path: Path, args):
    if args.op not in {"history", "search", "stats", "export", "baseline", "events"}:
        raise Refused("archive interface is read-only")
    if type(getattr(args, "limit", 20)) is not int or not 1 <= getattr(args, "limit", 20) <= 100:
        raise Refused("limit must be from 1 to 100")
    if args.op in {"history", "search", "stats", "export"}:
        if any(t is not None and (type(t) is not int or not 0 <= t <= 2**63 - 1) for t in (args.since, args.until)):
            raise Refused("invalid timestamp filter")
        if args.since is not None and args.until is not None and args.since >= args.until:
            raise Refused("since must be less than until")
        if (args.op == "history" or args.chat is not None) and not check_string(args.chat, 256):
            raise Refused("invalid chat identifier")
        if args.op == "search" and not check_string(args.query, 2000):
            raise Refused("invalid search term")
    if args.op == "events" and args.chat is not None and not check_string(args.chat, 256):
        raise Refused("invalid chat identifier")
    if args.op == "export" and args.format not in EXPORT_FORMATS:
        raise Refused("format must be json, markdown, html or csv")
    with open_archive(path) as db:
        return run(db, args, None)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True, type=Path)
    ops = parser.add_subparsers(dest="op", required=True)
    ops.add_parser("init").add_argument("--account", required=True)
    ingest = ops.add_parser("ingest")
    ingest.add_argument("--account", required=True)
    ingest.add_argument("--format", choices=("jsonl", "archive-json"), default="jsonl")
    ops.add_parser("baseline")
    events = ops.add_parser("events")
    events.add_argument("--after", required=True)
    events.add_argument("--limit", type=int, default=20)
    events.add_argument("--chat")
    events.add_argument("--exclude-self", action="store_true")
    for op in ("history", "search", "stats", "export"):
        query = ops.add_parser(op)
        query.add_argument("--chat", required=op == "history")
        query.add_argument("--since", type=int)
        query.add_argument("--until", type=int)
        query.add_argument("--limit", type=int, default=20)
        if op == "search":
            query.add_argument("query")
        if op == "export":
            query.add_argument("--cursor")
            query.add_argument("--format", choices=EXPORT_FORMATS, default="json")
    args = parser.parse_args()
    try:
        if args.op == "init":
            private_path(args.db)
            result = initialize(args.db, args.account)
        elif args.op == "ingest":
            with open_archive(args.db, write=True) as db:
                result = run(db, args, sys.stdin.buffer)
        else:
            result = query_archive(args.db, args)
        print(json.dumps(result))
        return 0
    except Refused as exc:
        print(json.dumps({"status": "failed", "error": str(exc)}))
    except (OSError, sqlite3.Error, ValueError, RecursionError):
        print('{"status":"failed","error":"archive unavailable or malformed input"}')
    return 1


if __name__ == "__main__":
    sys.exit(main())
