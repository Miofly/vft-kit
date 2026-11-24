#!/usr/bin/env python3
"""Verify a pinned wechat-use macOS release without executing its contents."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

SDK = frozenset(("wechat", "wechatd", "wechat-bridge", "wechat-mcp", "wechat-send-mcp",
                 "wechat-wechaty-gateway", "wechat-snapshot-validator", "wechat-native-owner"))
MAX_ARCHIVE = 256 << 20
MAX_COMPONENT = 128 << 20


def verify(archive: Path, expected: str, work_dir: Path) -> dict:
    if not re.fullmatch(r"[0-9a-fA-F]{64}", expected):
        raise ValueError("supply the published archive SHA-256 from a trusted source")
    if not archive.is_absolute() or not archive.is_file() or not work_dir.is_absolute() or not work_dir.is_dir():
        raise ValueError("archive and existing work directory must be absolute paths")
    with tempfile.TemporaryDirectory(prefix="wechat-release-verify-", dir=work_dir) as temporary:
        scratch = Path(temporary)
        pinned = scratch / "release.tar.gz"
        # Hash the exact private copy that will be parsed, not a mutable source path.
        digest = hashlib.sha256()
        total = 0
        with archive.open("rb") as source, pinned.open("xb") as snapshot:
            while chunk := source.read(1 << 20):
                total += len(chunk)
                if total > MAX_ARCHIVE:
                    raise ValueError("archive exceeds verification size limit")
                digest.update(chunk)
                snapshot.write(chunk)
        if digest.hexdigest() != expected.lower():
            raise ValueError("archive SHA-256 mismatch")

        with tarfile.open(pinned, "r:gz") as bundle:
            wanted = SDK | {"BUILD-MANIFEST.json"}
            members = {}
            for member in bundle:
                name = member.name.removeprefix("./")
                if name not in wanted:
                    continue  # Never extract other members, including installer scripts.
                limit = (1 << 20) if name == "BUILD-MANIFEST.json" else MAX_COMPONENT
                if name in members or not member.isfile() or not 0 < member.size <= limit:
                    raise ValueError(f"invalid or duplicate release member: {name}")
                members[name] = member
            if members.keys() != wanted:
                raise ValueError("release package is missing a required component or manifest")
            with bundle.extractfile(members["BUILD-MANIFEST.json"]) as stream:
                manifest = json.load(stream)
            version, commit, abi = (manifest.get(key) for key in ("version", "sourceCommit", "sdkAbi"))
            if (manifest.get("schema") != "wechat-use/release-manifest/v1"
                    or manifest.get("publicRelease") is not True
                    or not isinstance(version, str) or not version
                    or not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit)
                    or abi != "wechat-use/native-context/v1"):
                raise ValueError("unrecognized release manifest")
            rows = manifest.get("artifacts")
            if not isinstance(rows, list) or len(rows) != len(SDK):
                raise ValueError("expected exactly eight manifest components")
            checked = set()
            for row in rows:
                name = row["name"]
                if name not in SDK or name in checked:
                    raise ValueError("unexpected or duplicate manifest component")
                expected_build = {"schema": "wechat-use/build-info/v1", "binary": name, "version": version,
                                  "sourceCommit": commit, "sourceDirty": False, "sdkAbi": abi, "publicRelease": True}
                member = members[name]
                if (row.get("build") != expected_build or row.get("size") != member.size
                        or row.get("mode") != member.mode or not member.mode & 0o111):
                    raise ValueError(f"manifest metadata mismatch: {name}")
                binary = scratch / name
                with bundle.extractfile(member) as stream, binary.open("xb") as output:
                    shutil.copyfileobj(stream, output)
                with binary.open("rb") as stream:
                    if hashlib.file_digest(stream, "sha256").hexdigest() != row.get("sha256"):
                        raise ValueError(f"component SHA-256 mismatch: {name}")
                result = subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(binary)],
                                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL, timeout=15)
                if result.returncode:
                    raise ValueError(f"component signature verification failed: {name}")
                checked.add(name)
        return {"status": "verified", "version": version, "source_commit": commit, "sdk_abi": abi,
                "components": sorted(checked), "build_identity_source": "pinned_manifest", "executed": False}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = verify(args.archive, args.sha256, args.work_dir)
    except (ValueError, OSError, KeyError, TypeError, AttributeError, RecursionError,
            tarfile.TarError, subprocess.SubprocessError) as exc:
        parser.exit(1, f"release verification refused: {exc if type(exc) is ValueError else type(exc).__name__}\n")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
