#!/usr/bin/env python3
"""Token-safe wrapper around the supported AI Studio Hub SDK surface."""

import argparse
import json
import os
from pathlib import Path
from typing import Any


TRANSFER_TYPES = ("model", "dataset")


def require_token() -> str:
    token = os.environ.get("AISTUDIO_ACCESS_TOKEN", "").strip()
    if not token:
        raise SystemExit("AISTUDIO_ACCESS_TOKEN is not set")
    return token


def resolve_repo_id(value: str, owner: str | None = None) -> str:
    value = value.strip().strip("/")
    if "/" in value:
        return value
    owner = (owner if owner is not None else os.environ.get("AISTUDIO_OWNER", "")).strip()
    if not owner:
        raise SystemExit("repo_id must be OWNER/REPO or AISTUDIO_OWNER must be set")
    return f"{owner}/{value}"


def require_absolute(value: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        raise argparse.ArgumentTypeError("path must be absolute")
    if not path.exists():
        raise argparse.ArgumentTypeError(f"path does not exist: {path}")
    return path


def absolute_destination(value: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        raise argparse.ArgumentTypeError("destination must be absolute")
    if not path.parent.exists():
        raise argparse.ArgumentTypeError(f"destination parent does not exist: {path.parent}")
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

    sub.add_parser("credential-status", help="report credential and owner presence without secrets")

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

    exists = sub.add_parser("file-exists", help="check a remote model/dataset file")
    exists.add_argument("repo_id")
    exists.add_argument("path_in_repo")
    exists.add_argument("--revision", default="master")

    upload_file = sub.add_parser("upload-file", help="upload one absolute local file")
    upload_file.add_argument("repo_id")
    upload_file.add_argument("file", type=require_absolute)
    upload_file.add_argument("path_in_repo")
    upload_file.add_argument("--repo-type", choices=TRANSFER_TYPES, default="model")
    upload_file.add_argument("--revision", default="master")
    upload_file.add_argument("--message")

    upload_folder = sub.add_parser("upload-folder", help="upload one absolute local folder")
    upload_folder.add_argument("repo_id")
    upload_folder.add_argument("folder", type=require_absolute)
    upload_folder.add_argument("--path-in-repo", default="")
    upload_folder.add_argument("--repo-type", choices=TRANSFER_TYPES, default="model")
    upload_folder.add_argument("--revision", default="master")
    upload_folder.add_argument("--message")
    upload_folder.add_argument("--allow", action="append")
    upload_folder.add_argument("--ignore", action="append")

    download_file = sub.add_parser("download-file", help="download one model/dataset file")
    download_file.add_argument("repo_id")
    download_file.add_argument("path_in_repo")
    download_file.add_argument("local_dir", type=absolute_destination)
    download_file.add_argument("--repo-type", choices=TRANSFER_TYPES, default="model")
    download_file.add_argument("--revision", default="master")
    download_file.add_argument("--force", action="store_true")

    download_repo = sub.add_parser("download-repo", help="download a model/dataset repository")
    download_repo.add_argument("repo_id")
    download_repo.add_argument("local_dir", type=absolute_destination)
    download_repo.add_argument("--repo-type", choices=TRANSFER_TYPES, default="model")
    download_repo.add_argument("--revision", default="master")
    download_repo.add_argument("--allow", action="append")
    download_repo.add_argument("--ignore", action="append")
    download_repo.add_argument("--force", action="store_true")

    sub.add_parser("self-check", help="run local checks without network access")
    return parser


def ensure_download_target(args: argparse.Namespace) -> None:
    if args.command == "download-file":
        target = args.local_dir / args.path_in_repo
        if target.exists() and not args.force:
            raise SystemExit(f"download target exists; pass --force to replace: {target}")
    elif args.local_dir.exists() and any(args.local_dir.iterdir()) and not args.force:
        raise SystemExit(f"download directory is not empty; pass --force to reuse: {args.local_dir}")
    args.local_dir.mkdir(parents=True, exist_ok=True)


def main() -> None:
    args = build_parser().parse_args()

    if args.command == "credential-status":
        token = os.environ.get("AISTUDIO_ACCESS_TOKEN", "").strip()
        owner = os.environ.get("AISTUDIO_OWNER", "").strip()
        print_result({"configured": bool(token), "length": len(token), "owner": owner or None})
        return
    if args.command == "self-check":
        assert resolve_repo_id("repo", "123") == "123/repo"
        assert resolve_repo_id("456/repo", "123") == "456/repo"
        assert "app" not in TRANSFER_TYPES
        assert "token" not in json.dumps({"configured": True, "length": 40})
        print("ok")
        return

    token = require_token()
    hub = load_hub()

    if args.command in {"create-model", "create-app"}:
        repo_name = args.repo_id.rsplit("/", 1)[-1]
        if args.command == "create-model":
            result = hub.create_repo(
                repo_id=args.repo_id,
                repo_type="model",
                model_name=args.model_name or repo_name,
                desc=args.desc,
                license=args.license,
                private=not args.public,
                token=token,
            )
        else:
            if args.app_sdk != "static" and not args.version:
                raise SystemExit("--version is required for gradio and streamlit apps")
            kwargs = {
                "repo_id": args.repo_id,
                "repo_type": "app",
                "app_name": args.app_name or repo_name,
                "app_sdk": args.app_sdk,
                "desc": args.desc,
                "license": args.license,
                "private": not args.public,
                "token": token,
            }
            if args.version:
                kwargs["version"] = args.version
            result = hub.create_repo(**kwargs)
        if isinstance(result, dict) and result.get("repo_id"):
            repo_id = result["repo_id"]
            owner = (
                args.repo_id.split("/", 1)[0]
                if "/" in args.repo_id
                else os.environ.get("AISTUDIO_OWNER")
            )
            if "/" in repo_id or owner:
                result["resolved_repo_id"] = resolve_repo_id(repo_id, owner)
    elif args.command == "file-exists":
        result = hub.file_exists(
            resolve_repo_id(args.repo_id),
            args.path_in_repo,
            revision=args.revision,
            token=token,
        )
    elif args.command == "upload-file":
        if not args.file.is_file():
            raise SystemExit(f"not a file: {args.file}")
        result = hub.upload_file(
            repo_id=resolve_repo_id(args.repo_id),
            path_or_fileobj=args.file,
            path_in_repo=args.path_in_repo,
            repo_type=args.repo_type,
            revision=args.revision,
            commit_message=args.message,
            token=token,
        )
        result = {"ok": True, "result": result}
    elif args.command == "upload-folder":
        if not args.folder.is_dir():
            raise SystemExit(f"not a folder: {args.folder}")
        result = hub.upload_folder(
            repo_id=resolve_repo_id(args.repo_id),
            folder_path=args.folder,
            path_in_repo=args.path_in_repo,
            repo_type=args.repo_type,
            revision=args.revision,
            commit_message=args.message,
            allow_patterns=args.allow,
            ignore_patterns=args.ignore,
            token=token,
        )
        result = {"ok": True, "result": result}
    elif args.command == "download-file":
        ensure_download_target(args)
        from aistudio_sdk.file_download import model_file_download

        result = model_file_download(
            repo_id=resolve_repo_id(args.repo_id),
            file_path=args.path_in_repo,
            revision=args.revision,
            local_dir=str(args.local_dir),
            repo_type=args.repo_type,
            token=token,
        )
    else:
        ensure_download_target(args)
        from aistudio_sdk.snapshot_download import snapshot_download

        result = snapshot_download(
            repo_id=resolve_repo_id(args.repo_id),
            revision=args.revision,
            local_dir=str(args.local_dir),
            repo_type=args.repo_type,
            allow_patterns=args.allow,
            ignore_patterns=args.ignore,
            token=token,
        )
    print_result(result)


if __name__ == "__main__":
    main()
