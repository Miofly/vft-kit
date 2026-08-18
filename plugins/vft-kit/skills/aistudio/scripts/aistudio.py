#!/usr/bin/env python3
"""Small, token-safe wrapper around the supported AI Studio Hub SDK surface."""

import argparse
import json
import os
from pathlib import Path
from typing import Any


def require_token() -> str:
    token = os.environ.get("AISTUDIO_ACCESS_TOKEN", "").strip()
    if not token:
        raise SystemExit("AISTUDIO_ACCESS_TOKEN is not set")
    return token


def require_absolute(value: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        raise argparse.ArgumentTypeError("path must be absolute")
    if not path.exists():
        raise argparse.ArgumentTypeError(f"path does not exist: {path}")
    return path


def load_hub():
    try:
        from aistudio_sdk import hub
    except ImportError as exc:
        raise SystemExit(
            "aistudio-sdk is required; run with: uv run --with aistudio-sdk python3 ..."
        ) from exc
    return hub


def print_result(result: Any) -> None:
    print(json.dumps(result, ensure_ascii=False, indent=2, default=str))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Operate Baidu AI Studio Hub safely")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("credential-status", help="report credential presence without revealing it")

    model = sub.add_parser("create-model", help="create a model repository")
    model.add_argument("repo_id")
    model.add_argument("--model-name")
    model.add_argument("--desc", default="")
    model.add_argument("--license", default="Apache License 2.0")
    model.add_argument("--public", action="store_true")

    app = sub.add_parser("create-app", help="create an application repository")
    app.add_argument("repo_id")
    app.add_argument("--app-name")
    app.add_argument("--app-sdk", choices=("gradio", "streamlit", "static"), required=True)
    app.add_argument("--version")
    app.add_argument("--desc", default="")
    app.add_argument("--license", default="Apache License 2.0")
    app.add_argument("--public", action="store_true")

    upload_file = sub.add_parser("upload-file", help="upload one absolute local file")
    upload_file.add_argument("repo_id")
    upload_file.add_argument("file", type=require_absolute)
    upload_file.add_argument("path_in_repo")
    upload_file.add_argument("--repo-type", choices=("model", "app"), default="model")
    upload_file.add_argument("--revision", default="master")
    upload_file.add_argument("--message")

    upload_folder = sub.add_parser("upload-folder", help="upload one absolute local folder")
    upload_folder.add_argument("repo_id")
    upload_folder.add_argument("folder", type=require_absolute)
    upload_folder.add_argument("--path-in-repo", default="")
    upload_folder.add_argument("--repo-type", choices=("model", "app"), default="model")
    upload_folder.add_argument("--revision", default="master")
    upload_folder.add_argument("--message")
    upload_folder.add_argument("--allow", action="append")
    upload_folder.add_argument("--ignore", action="append")

    sub.add_parser("self-check", help="run local checks without network access")
    return parser


def main() -> None:
    args = build_parser().parse_args()

    if args.command == "credential-status":
        token = os.environ.get("AISTUDIO_ACCESS_TOKEN", "").strip()
        print_result({"configured": bool(token), "length": len(token)})
        return
    if args.command == "self-check":
        assert not Path("relative").is_absolute()
        assert "token" not in json.dumps({"configured": True, "length": 40})
        print("ok")
        return

    token = require_token()
    hub = load_hub()

    if args.command == "create-model":
        result = hub.create_repo(
            repo_id=args.repo_id,
            repo_type="model",
            model_name=args.model_name or args.repo_id.rsplit("/", 1)[-1],
            desc=args.desc,
            license=args.license,
            private=not args.public,
            token=token,
        )
    elif args.command == "create-app":
        if args.app_sdk != "static" and not args.version:
            raise SystemExit("--version is required for gradio and streamlit apps")
        kwargs = {
            "repo_id": args.repo_id,
            "repo_type": "app",
            "app_name": args.app_name or args.repo_id.rsplit("/", 1)[-1],
            "app_sdk": args.app_sdk,
            "desc": args.desc,
            "license": args.license,
            "private": not args.public,
            "token": token,
        }
        if args.version:
            kwargs["version"] = args.version
        result = hub.create_repo(**kwargs)
    elif args.command == "upload-file":
        if not args.file.is_file():
            raise SystemExit(f"not a file: {args.file}")
        result = hub.upload_file(
            repo_id=args.repo_id,
            path_or_fileobj=args.file,
            path_in_repo=args.path_in_repo,
            repo_type=args.repo_type,
            revision=args.revision,
            commit_message=args.message,
            token=token,
        )
    else:
        if not args.folder.is_dir():
            raise SystemExit(f"not a folder: {args.folder}")
        result = hub.upload_folder(
            repo_id=args.repo_id,
            folder_path=args.folder,
            path_in_repo=args.path_in_repo,
            repo_type=args.repo_type,
            revision=args.revision,
            commit_message=args.message,
            allow_patterns=args.allow,
            ignore_patterns=args.ignore,
            token=token,
        )
    print_result(result)


if __name__ == "__main__":
    main()

