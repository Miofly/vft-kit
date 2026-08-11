#!/usr/bin/env python3
"""Call a public method on the official huggingface_hub.HfApi."""

import argparse
import dataclasses
import datetime
import enum
import json
import os
import shutil
import sys
from collections.abc import Iterable, Mapping
from pathlib import Path


class LauncherError(Exception):
    pass


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("method")
    parser.add_argument("--kwargs", default="{}")
    parser.add_argument("--config")
    return parser.parse_args()


def token_from_config(path):
    config_path = Path(path).expanduser()
    if not config_path.is_file():
        raise LauncherError(f"config file not found: {path}")
    try:
        config = json.loads(config_path.read_text())
    except (OSError, json.JSONDecodeError):
        raise LauncherError("config has no supported token field") from None
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


def redact(value, token):
    return value.replace(token, "[REDACTED]") if token and isinstance(value, str) else value


def json_safe(value, token):
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, str):
        return redact(value, token)
    if isinstance(value, enum.Enum):
        return json_safe(value.value, token)
    if isinstance(value, (datetime.datetime, datetime.date)):
        return value.isoformat()
    if dataclasses.is_dataclass(value) and not isinstance(value, type):
        return json_safe(dataclasses.asdict(value), token)
    if isinstance(value, Mapping):
        return {redact(str(key), token): json_safe(item, token) for key, item in value.items()}
    if isinstance(value, (bytes, bytearray)):
        return redact(value.decode(errors="replace"), token)
    if isinstance(value, Iterable):
        return [json_safe(item, token) for item in value]
    if hasattr(value, "__dict__"):
        return json_safe(vars(value), token)
    return redact(str(value), token)


def main():
    token = None
    try:
        args = parse_args()
        if args.method.startswith("_"):
            raise LauncherError("method must be public")
        try:
            kwargs = json.loads(args.kwargs)
        except json.JSONDecodeError:
            raise LauncherError("--kwargs must be valid JSON") from None
        if not isinstance(kwargs, dict):
            raise LauncherError("--kwargs must be a JSON object")

        token = resolve_token(args.config)
        api = load_hf_api()(token=token)
        method = getattr(api, args.method, None)
        if not callable(method):
            raise LauncherError(f"HfApi method not found: {args.method}")
        result = method(**kwargs)
        print(json.dumps(json_safe(result, token), ensure_ascii=False))
        return 0
    except Exception as exc:
        message = redact(str(exc), token) or exc.__class__.__name__
        print(message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
