#!/usr/bin/env python3
"""Safely add or update a Claude provider in CC Switch's SQLite database."""

from __future__ import annotations

import argparse
import copy
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit


FORMATS = ("anthropic", "openai_chat", "openai_responses")
AUTH_FIELDS = ("ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY")
MODEL_KEYS = (
    "ANTHROPIC_MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL",
)


class ProviderError(RuntimeError):
    pass


@dataclass(frozen=True)
class ProviderInput:
    name: str
    base_url: str
    model: str
    api_format: str
    auth_field: str
    api_key: str
    replace_id: str | None = None


def normalize_base_url(value: str, api_format: str) -> str:
    value = value.strip().rstrip("/")
    parsed = urlsplit(value)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ProviderError("base URL must be an absolute http(s) URL")
    if parsed.query or parsed.fragment:
        raise ProviderError("base URL must not contain query parameters or fragments")
    path = parsed.path.rstrip("/")
    if api_format.startswith("openai_") and path.endswith("/v1"):
        path = path[:-3]
    return urlunsplit((parsed.scheme, parsed.netloc, path, "", "")).rstrip("/")


def parse_json(value: str, field: str) -> dict:
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError as exc:
        raise ProviderError(f"provider has invalid {field} JSON") from exc
    if not isinstance(parsed, dict):
        raise ProviderError(f"provider {field} must be a JSON object")
    return parsed


def validate_schema(conn: sqlite3.Connection) -> None:
    row = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='providers'"
    ).fetchone()
    if not row:
        raise ProviderError("providers table not found; unsupported CC Switch database")
    columns = {r[1] for r in conn.execute("PRAGMA table_info(providers)")}
    required = {"id", "app_type", "name", "settings_config", "meta", "is_current"}
    missing = required - columns
    if missing:
        raise ProviderError(f"unsupported providers schema; missing: {', '.join(sorted(missing))}")


def provider_endpoint_and_model(row: sqlite3.Row) -> tuple[str, str]:
    settings = parse_json(row["settings_config"], "settings_config")
    meta = parse_json(row["meta"], "meta")
    env = settings.get("env") if isinstance(settings.get("env"), dict) else {}
    api_format = meta.get("apiFormat") if meta.get("apiFormat") in FORMATS else "anthropic"
    base = env.get("ANTHROPIC_BASE_URL", "")
    try:
        base = normalize_base_url(base, api_format) if base else ""
    except ProviderError:
        base = str(base).rstrip("/")
    return base, str(env.get("ANTHROPIC_MODEL", ""))


def choose_existing(
    rows: list[sqlite3.Row], data: ProviderInput, normalized_base: str
) -> sqlite3.Row | None:
    if data.replace_id:
        matches = [row for row in rows if row["id"] == data.replace_id]
        if len(matches) != 1:
            raise ProviderError(f"Claude provider id not found: {data.replace_id}")
        return matches[0]

    by_name = [row for row in rows if row["name"].casefold() == data.name.casefold()]
    if by_name:
        return by_name[0]

    duplicates = [
        row
        for row in rows
        if provider_endpoint_and_model(row) == (normalized_base, data.model)
    ]
    if duplicates:
        row = duplicates[0]
        raise ProviderError(
            "possible duplicate provider: "
            f"{row['name']} ({row['id']}); inspect it, then rerun with --replace-id"
        )
    return None


def backup_database(conn: sqlite3.Connection, db_path: Path) -> Path:
    backup_dir = db_path.parent / "backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d_%H%M%S", time.localtime())
    backup_path = backup_dir / f"manual_before_provider_{stamp}_{uuid.uuid4().hex[:6]}.db"
    target = sqlite3.connect(backup_path)
    try:
        conn.backup(target)
    finally:
        target.close()
    backup_path.chmod(0o600)
    return backup_path


def build_configs(
    existing: sqlite3.Row | None,
    data: ProviderInput,
    normalized_base: str,
    seed_settings: dict | None = None,
) -> tuple[str, str]:
    settings = (
        parse_json(existing["settings_config"], "settings_config")
        if existing
        else copy.deepcopy(seed_settings or {})
    )
    meta = parse_json(existing["meta"], "meta") if existing else {}
    env = settings.get("env")
    if not isinstance(env, dict):
        env = {}
        settings["env"] = env
    elif not existing:
        env = {key: value for key, value in env.items() if not key.startswith("ANTHROPIC_")}
        settings["env"] = env
    env.pop("ANTHROPIC_AUTH_TOKEN", None)
    env.pop("ANTHROPIC_API_KEY", None)
    env[data.auth_field] = data.api_key
    env["ANTHROPIC_BASE_URL"] = normalized_base
    for key in MODEL_KEYS:
        env[key] = data.model
    settings["model"] = "opus"
    meta.update(
        {
            "apiFormat": data.api_format,
            "apiKeyField": data.auth_field,
            "endpointAutoSelect": True,
        }
    )
    return (
        json.dumps(settings, ensure_ascii=False, separators=(",", ":")),
        json.dumps(meta, ensure_ascii=False, separators=(",", ":")),
    )


def upsert_provider(db_path: Path, data: ProviderInput, dry_run: bool = False) -> dict:
    if not data.name.strip():
        raise ProviderError("provider name must not be empty")
    if not data.model.strip():
        raise ProviderError("model must not be empty")
    if not data.api_key:
        raise ProviderError("API key must not be empty")
    if not db_path.is_file():
        raise ProviderError(f"CC Switch database not found: {db_path}")
    normalized_base = normalize_base_url(data.base_url, data.api_format)
    conn = sqlite3.connect(db_path, timeout=10)
    conn.row_factory = sqlite3.Row
    try:
        validate_schema(conn)
        rows = conn.execute(
            "SELECT id, name, settings_config, meta, is_current "
            "FROM providers WHERE app_type='claude'"
        ).fetchall()
        existing = choose_existing(rows, data, normalized_base)
        action = "update" if existing else "create"
        provider_id = existing["id"] if existing else str(uuid.uuid4())
        if dry_run:
            return {
                "action": action,
                "provider_id": provider_id,
                "name": data.name,
                "base_url": normalized_base,
                "model": data.model,
                "backup": None,
            }

        seed_settings = None
        if not existing:
            current = next((row for row in rows if row["is_current"]), None)
            if current:
                seed_settings = parse_json(current["settings_config"], "settings_config")
        settings_config, meta = build_configs(
            existing, data, normalized_base, seed_settings
        )
        backup_path = backup_database(conn, db_path)
        conn.execute("BEGIN IMMEDIATE")
        if existing:
            conn.execute(
                "UPDATE providers SET name=?, settings_config=?, meta=? "
                "WHERE id=? AND app_type='claude'",
                (data.name, settings_config, meta, provider_id),
            )
        else:
            sort_index = conn.execute(
                "SELECT COALESCE(MAX(sort_index), -1) + 1 FROM providers "
                "WHERE app_type='claude'"
            ).fetchone()[0]
            conn.execute(
                "INSERT INTO providers "
                "(id, app_type, name, settings_config, created_at, sort_index, meta, is_current) "
                "VALUES (?, 'claude', ?, ?, ?, ?, ?, 0)",
                (
                    provider_id,
                    data.name,
                    settings_config,
                    int(time.time() * 1000),
                    sort_index,
                    meta,
                ),
            )
        conn.commit()
        integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise ProviderError(f"database integrity check failed: {integrity}")
        db_path.chmod(0o600)
        return {
            "action": action,
            "provider_id": provider_id,
            "name": data.name,
            "base_url": normalized_base,
            "model": data.model,
            "backup": str(backup_path),
        }
    finally:
        conn.close()


def cc_switch_running() -> bool:
    if sys.platform != "darwin" or shutil.which("pgrep") is None:
        return False
    result = subprocess.run(
        ["pgrep", "-f", r"CC Switch\.app/Contents/MacOS/cc-switch"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def create_test_database(path: Path) -> None:
    conn = sqlite3.connect(path)
    conn.executescript(
        """
        CREATE TABLE providers (
          id TEXT NOT NULL,
          app_type TEXT NOT NULL,
          name TEXT NOT NULL,
          settings_config TEXT NOT NULL,
          website_url TEXT,
          category TEXT,
          created_at INTEGER,
          sort_index INTEGER,
          notes TEXT,
          icon TEXT,
          icon_color TEXT,
          meta TEXT NOT NULL DEFAULT '{}',
          is_current BOOLEAN NOT NULL DEFAULT 0,
          in_failover_queue BOOLEAN NOT NULL DEFAULT 0,
          cost_multiplier TEXT NOT NULL DEFAULT '1.0',
          limit_daily_usd TEXT,
          limit_monthly_usd TEXT,
          provider_type TEXT,
          PRIMARY KEY (id, app_type)
        );
        """
    )
    conn.execute(
        "INSERT INTO providers "
        "(id, app_type, name, settings_config, meta, is_current, sort_index) "
        "VALUES ('existing-id', 'claude', 'qw', ?, ?, 1, 0)",
        (
            json.dumps(
                {
                    "env": {
                        "ANTHROPIC_AUTH_TOKEN": "old-secret",
                        "ANTHROPIC_BASE_URL": "https://example.com/v1",
                        "ANTHROPIC_MODEL": "model-a",
                        "DISABLE_AUTOUPDATER": "1",
                    },
                    "enabledPlugins": {"example@plugin": True},
                    "hooks": {"SessionStart": []},
                    "permissions": {"defaultMode": "bypassPermissions"},
                    "statusLine": {"type": "command", "command": "statusline"},
                    "keep": {"unknown": True},
                }
            ),
            json.dumps({"apiFormat": "anthropic", "keep": True}),
        ),
    )
    conn.commit()
    conn.close()


def self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="cc-switch-provider-") as tmp:
        db_path = Path(tmp) / "cc-switch.db"
        create_test_database(db_path)
        updated = ProviderInput(
            "Provider A",
            "https://example.com/v1/",
            "model-a",
            "openai_chat",
            "ANTHROPIC_AUTH_TOKEN",
            "new-secret",
            "existing-id",
        )
        result = upsert_provider(db_path, updated)
        assert result["action"] == "update"
        conn = sqlite3.connect(db_path)
        row = conn.execute(
            "SELECT name, settings_config, meta, is_current FROM providers "
            "WHERE id='existing-id'"
        ).fetchone()
        settings, meta = json.loads(row[1]), json.loads(row[2])
        assert row[0] == "Provider A" and row[3] == 1
        assert settings["keep"]["unknown"] is True
        assert settings["env"]["ANTHROPIC_BASE_URL"] == "https://example.com"
        assert settings["env"]["ANTHROPIC_AUTH_TOKEN"] == "new-secret"
        assert settings["model"] == "opus"
        assert meta["apiFormat"] == "openai_chat" and meta["keep"] is True
        conn.close()

        created = ProviderInput(
            "Provider B",
            "https://other.example.com/v1",
            "model-b",
            "openai_responses",
            "ANTHROPIC_AUTH_TOKEN",
            "another-secret",
        )
        assert upsert_provider(db_path, created)["action"] == "create"
        conn = sqlite3.connect(db_path)
        row = conn.execute(
            "SELECT settings_config FROM providers WHERE name='Provider B'"
        ).fetchone()
        settings = json.loads(row[0])
        assert settings["enabledPlugins"] == {"example@plugin": True}
        assert settings["hooks"] == {"SessionStart": []}
        assert settings["permissions"]["defaultMode"] == "bypassPermissions"
        assert settings["statusLine"]["command"] == "statusline"
        assert settings["env"]["DISABLE_AUTOUPDATER"] == "1"
        assert settings["model"] == "opus"
        conn.close()
        try:
            upsert_provider(
                db_path,
                ProviderInput(
                    "Alias B",
                    "https://other.example.com/v1",
                    "model-b",
                    "openai_responses",
                    "ANTHROPIC_AUTH_TOKEN",
                    "another-secret",
                ),
                dry_run=True,
            )
        except ProviderError as exc:
            assert "possible duplicate provider" in str(exc)
        else:
            raise AssertionError("duplicate provider was not rejected")
        assert len(list((db_path.parent / "backups").glob("*.db"))) == 2
        assert db_path.stat().st_mode & 0o777 == 0o600
    print("SELF_TEST=PASS")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Safely add or update a CC Switch Claude provider."
    )
    parser.add_argument("--name")
    parser.add_argument("--base-url")
    parser.add_argument("--model")
    parser.add_argument("--api-format", choices=FORMATS)
    parser.add_argument("--auth-field", choices=AUTH_FIELDS, default=AUTH_FIELDS[0])
    parser.add_argument("--api-key-env", default="CC_SWITCH_API_KEY")
    parser.add_argument("--replace-id")
    parser.add_argument("--db", type=Path, default=Path.home() / ".cc-switch/cc-switch.db")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.self_test:
        self_test()
        return 0
    missing = [key for key in ("name", "base_url", "model", "api_format") if not getattr(args, key)]
    if missing:
        raise ProviderError("missing required arguments: " + ", ".join("--" + x.replace("_", "-") for x in missing))
    api_key = os.environ.get(args.api_key_env, "")
    if not api_key:
        raise ProviderError(f"API key environment variable is empty: {args.api_key_env}")
    if cc_switch_running() and not args.dry_run:
        raise ProviderError("CC Switch is running; quit it before writing the database")
    result = upsert_provider(
        args.db.expanduser(),
        ProviderInput(
            args.name.strip(),
            args.base_url,
            args.model.strip(),
            args.api_format,
            args.auth_field,
            api_key,
            args.replace_id,
        ),
        args.dry_run,
    )
    print(f"RESULT={result['action']}")
    print(f"PROVIDER_ID={result['provider_id']}")
    print(f"NAME={result['name']}")
    print(f"BASE_URL={result['base_url']}")
    print(f"MODEL={result['model']}")
    print("KEY_PRESENT=true")
    print("CURRENT_PROVIDER_UNCHANGED=true")
    if result["backup"]:
        print(f"BACKUP={result['backup']}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProviderError as exc:
        print(f"ERROR={exc}", file=sys.stderr)
        raise SystemExit(2)
