#!/usr/bin/env python3
"""Call a public method on the official huggingface_hub.HfApi."""

import argparse
import dataclasses
import datetime
import enum
import json
import math
import os
import shutil
import sys
from collections.abc import Iterable, Mapping
from pathlib import Path


class LauncherError(Exception):
    pass


MAX_DEPTH = 32
MAX_ITEMS = 10_000
FORBIDDEN_CREDENTIAL_KWARGS = {"token", "access_token", "api_token"}
SENSITIVE_NAMES = {"token", "secret", "password", "api_key", "access_token", "api_token"}


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("method")
    parser.add_argument("--kwargs", default="{}")
    parser.add_argument("--config")
    return parser.parse_args()


def strict_json_loads(value, error):
    def reject_constant(_):
        raise ValueError

    def finite_float(number):
        value = float(number)
        if not math.isfinite(value):
            raise ValueError
        return value

    try:
        return json.loads(value, parse_constant=reject_constant, parse_float=finite_float)
    except (json.JSONDecodeError, ValueError, OverflowError, RecursionError):
        raise LauncherError(error) from None


def token_from_config(path):
    config_path = Path(path).expanduser()
    if not config_path.exists():
        raise LauncherError(f"config file not found: {path}")
    if not config_path.is_file():
        raise LauncherError(f"cannot read config file: {path}")
    try:
        content = config_path.read_text()
    except (OSError, UnicodeError):
        raise LauncherError(f"cannot read config file: {path}") from None
    config = strict_json_loads(content, f"invalid config JSON: {path}")
    if isinstance(config, dict):
        for key in ("token", "access_token", "api_token", "key"):
            value = config.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
    raise LauncherError("config has no supported token field")


def resolve_token(config):
    env_token = os.environ.get("HF_TOKEN", "")
    if env_token:
        return env_token
    if config is not None:
        return token_from_config(config)

    token_path = os.environ.get("HF_TOKEN_PATH")
    if not token_path:
        hf_home = os.environ.get("HF_HOME", "~/.cache/huggingface")
        token_path = str(Path(hf_home).expanduser() / "token")
    path = Path(token_path).expanduser()
    if path.is_file():
        value = path.read_text().strip()
        return value or None
    return None


def load_hf_api():
    try:
        from huggingface_hub import HfApi

        return HfApi
    except ModuleNotFoundError:
        if os.environ.get("HF_API_UV_BOOTSTRAPPED"):
            raise LauncherError("huggingface_hub import failed after uv bootstrap") from None
        uv = shutil.which("uv")
        if not uv:
            raise LauncherError("huggingface_hub is not installed and uv was not found") from None
        env = os.environ.copy()
        env["HF_API_UV_BOOTSTRAPPED"] = "1"
        try:
            os.execvpe(
                uv,
                [uv, "run", "--with", "huggingface-hub", "python", __file__, *sys.argv[1:]],
                env,
            )
        except OSError as exc:
            raise LauncherError(f"failed to start uv: {exc}") from None


def redact(value, secrets):
    if not isinstance(value, str):
        return value
    for secret in sorted((item for item in secrets if item), key=len, reverse=True):
        value = value.replace(secret, "[REDACTED]")
    return value


def sensitive_values(value):
    found = set()

    def visit(item):
        if isinstance(item, Mapping):
            for key, nested in item.items():
                if isinstance(key, str) and key.lower() in SENSITIVE_NAMES and isinstance(nested, str):
                    found.add(nested)
                visit(nested)
        elif isinstance(item, list):
            for nested in item:
                visit(nested)

    visit(value)
    return found


def json_safe(value, secrets):
    active = set()
    budget = [MAX_ITEMS]

    def consume():
        if budget[0] == 0:
            raise LauncherError("result exceeds serialization limit")
        budget[0] -= 1

    def walk(item, depth):
        if depth > MAX_DEPTH:
            raise LauncherError("result exceeds serialization limit")
        if item is None or isinstance(item, (bool, int)):
            return item
        if isinstance(item, float):
            if not math.isfinite(item):
                raise LauncherError("result contains non-finite float")
            return item
        if isinstance(item, str):
            return redact(item, secrets)
        if isinstance(item, enum.Enum):
            return walk(item.value, depth + 1)
        if isinstance(item, (datetime.datetime, datetime.date)):
            return item.isoformat()
        if isinstance(item, (bytes, bytearray)):
            return redact(item.decode(errors="replace"), secrets)

        item_id = id(item)
        if item_id in active:
            raise LauncherError("result contains a cycle")
        active.add(item_id)
        try:
            if dataclasses.is_dataclass(item) and not isinstance(item, type):
                result = {}
                for index, field in enumerate(dataclasses.fields(item)):
                    if index >= MAX_ITEMS:
                        raise LauncherError("result exceeds serialization limit")
                    consume()
                    result[redact(field.name, secrets)] = walk(getattr(item, field.name), depth + 1)
                return result
            if isinstance(item, Mapping):
                result = {}
                for index, (key, nested) in enumerate(item.items()):
                    if index >= MAX_ITEMS:
                        raise LauncherError("result exceeds serialization limit")
                    consume()
                    result[redact(str(key), secrets)] = walk(nested, depth + 1)
                return result
            if isinstance(item, Iterable):
                result = []
                for index, nested in enumerate(item):
                    if index >= MAX_ITEMS:
                        raise LauncherError("result exceeds serialization limit")
                    consume()
                    result.append(walk(nested, depth + 1))
                return result
            if hasattr(item, "__dict__"):
                return walk(vars(item), depth + 1)
            return redact(str(item), secrets)
        finally:
            active.remove(item_id)

    return walk(value, 0)


def main():
    token = None
    secrets = set()
    try:
        args = parse_args()
        if args.method.startswith("_"):
            raise LauncherError("method must be public")
        kwargs = strict_json_loads(args.kwargs, "--kwargs must be valid JSON")
        if not isinstance(kwargs, dict):
            raise LauncherError("--kwargs must be a JSON object")
        secrets.update(sensitive_values(kwargs))
        forbidden = sorted(key for key in kwargs if key.lower() in FORBIDDEN_CREDENTIAL_KWARGS)
        if forbidden:
            raise LauncherError(f"credential kwargs are not allowed: {', '.join(forbidden)}")

        token = resolve_token(args.config)
        if token:
            secrets.add(token)
        api = load_hf_api()(token=token)
        method = getattr(api, args.method, None)
        if not callable(method):
            raise LauncherError(f"HfApi method not found: {args.method}")
        result = method(**kwargs)
        print(json.dumps(json_safe(result, secrets), ensure_ascii=False, allow_nan=False))
        return 0
    except Exception as exc:
        message = redact(str(exc), secrets) or exc.__class__.__name__
        print(message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
