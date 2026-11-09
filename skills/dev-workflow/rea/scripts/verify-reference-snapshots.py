#!/usr/bin/env python3
"""Verify selected reference snapshots, not their runtime or security claims."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re


SNAPSHOTS = {
    "craft-anything": (13, 90888),
    "bla": (13, 77389),
    "awesome-rea": (10, 10178089),
}


def parse_manifest(text):
    entries = {}
    for line in text.splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (upstream/.+)", line)
        if not match:
            raise ValueError(f"invalid checksum line: {line!r}")
        digest, name = match.groups()
        path = PurePosixPath(name)
        if ".." in path.parts or "\\" in name or str(path) != name or name in entries:
            raise ValueError(f"unsafe or duplicate snapshot path: {name}")
        entries[name] = digest
    return entries


def verify(skill):
    main = (skill / "SKILL.md").read_text()
    assert re.search(r"^name: rea$", main, re.M), "skill identity changed"
    for name, (count, size) in SNAPSHOTS.items():
        root = skill / "references" / name
        entries = parse_manifest((root / "SHA256SUMS").read_text())
        files = sorted(p for p in (root / "upstream").rglob("*") if p.is_file())
        assert not any(p.is_symlink() for p in root.rglob("*")), f"{name}: symlink"
        assert {str(p.relative_to(root)) for p in files} == set(entries), f"{name}: inventory differs"
        assert len(files) == count, f"{name}: file count differs"
        assert sum(p.stat().st_size for p in files) == size, f"{name}: byte count differs"
        for path, digest in entries.items():
            assert hashlib.sha256((root / path).read_bytes()).hexdigest() == digest, path
        index = root / "README.md"
        assert f"references/{name}/README.md" in main, f"{name}: missing main route"
        # Vendor docs retain upstream links; validate only the locally maintained router.
        for target in re.findall(r"\]\(([^)]+)\)", index.read_text()):
            if "://" not in target and not target.startswith("#"):
                assert (root / target.split("#", 1)[0]).exists(), f"broken link: {target}"
        print(f"{name}: {count} files, {size} bytes, SHA-256 and routing OK")
    data = skill / "references/awesome-rea/upstream/data"
    resources = json.loads((data / "rea-resources.json").read_text())
    resources += json.loads((data / "tool-resources.json").read_text())
    papers = json.loads((data / "papers.json").read_text())
    evidence = json.loads((data / "evidence-classes.json").read_text())["entries"]
    assert len(resources) == 2848 and len(papers) == 235, "catalog counts changed"
    ids = {entry["id"] for entry in resources}
    assert len(ids) == len(resources), "duplicate resource id"
    assert len(evidence) == len(ids), "duplicate or missing evidence id"
    assert {entry["id"] for entry in evidence} == ids, "catalog evidence coverage differs"
    assert len({entry["id"] for entry in resources + papers}) == 3083, "duplicate catalog id"
    assert all(entry["runtime_status"] == "not-run" for entry in evidence), "runtime claims changed"
    print("awesome-rea: 2848 resources, 235 papers, evidence coverage and not-run status OK")
    for relative in ("references/resource-selection.md", "scripts/search-awesome-rea.py",
                     "scripts/test-search-awesome-rea.py"):
        assert (skill / relative).is_file(), f"missing selection/search entry: {relative}"
    skill_entries = [p for p in skill.rglob("*") if p.is_file() and p.name.lower() == "skill.md"]
    assert skill_entries == [skill / "SKILL.md"], "nested skill entry (case-insensitive)"


def self_check():
    digest = hashlib.sha256(b"sample").hexdigest()
    assert parse_manifest(f"{digest}  upstream/example.md\n") == {"upstream/example.md": digest}
    invalid = [
        f"{digest}  upstream/../escape.md", f"{digest}  /escape.md",
        f"{digest}  upstream//example.md", "not a checksum",
        f"{digest}  upstream/example.md\n{digest}  upstream/example.md",
    ]
    for text in invalid:
        try:
            parse_manifest(text)
        except ValueError:
            continue
        raise AssertionError(f"invalid manifest accepted: {text}")
    print("manifest parser: 1 positive + 5 negative checks OK")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skill-dir", required=True, type=Path, help="Absolute rea skill directory")
    args = parser.parse_args()
    if not args.skill_dir.is_absolute():
        parser.error("--skill-dir must be absolute")
    self_check()
    verify(args.skill_dir)
