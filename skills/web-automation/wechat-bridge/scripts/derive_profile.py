#!/usr/bin/env python3
"""Derive the WeChat native-send profile (RVA set) from a local WeChat.app.

Why: upstream's profile (the RVA set that lets you drive WeChat's Qt widgets
in-process) is pushed server-side and gated behind their activation code. This
derives the same numbers locally, from the Qt metaobject data that is fully
present in `Contents/Resources/wechat.dylib`.

How it works (no full auto-analysis; seconds not hours):
  1. lipo -thin arm64 the universal dylib.
  2. analyzeHeadless with -noanalysis (its Mach-O loader resolves the
     LC_DYLD_CHAINED_FIXUPS, so in-memory pointers are real) and run
     scripts/ghidra/Profile.java, which scans QMetaObject structures.
  3. Parse and write profile.json.

Usage:
  python3 derive_profile.py [--out profile.json] [--wechat /Applications/WeChat.app]
                            [--ghidra-lib DIR] [--proj /tmp/ghproj] [--work /tmp]
Env: GHIDRA_INSTALL_DIR (or --ghidra-lib)
"""
import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def sh(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw)


def wechat_version(app):
    p = os.path.join(app, "Contents", "Info.plist")
    if not os.path.exists(p):
        return {}
    with open(p, "rb") as f:
        pl = plistlib.load(f)
    return {"short_version": pl.get("CFBundleShortVersionString"),
            "build": pl.get("CFBundleVersion"),
            "bundle_id": pl.get("CFBundleIdentifier")}


def thin(dylib, work):
    out = os.path.join(work, "wechat_arm64.dylib")
    if not os.path.exists(out) or os.path.getmtime(out) < os.path.getmtime(dylib):
        sh(["lipo", "-thin", "arm64", dylib, "-output", out])
    h = hashlib.sha256(open(out, "rb").read()).hexdigest()
    return out, h


def run_headless(ghidra, proj, thin_path, fresh):
    headless = os.path.join(ghidra, "support", "analyzeHeadless")
    script_dir = os.path.join(HERE, "ghidra")
    project_exists = os.path.isfile(os.path.join(proj, "wechat.gpr"))
    os.makedirs(proj, exist_ok=True)   # analyzeHeadless aborts if the dir is missing
    env = dict(os.environ, GHIDRA_MAXMEM=os.environ.get("GHIDRA_MAXMEM", "6G"))
    if fresh or not project_exists:
        cmd = [headless, proj, "wechat", "-import", thin_path, "-noanalysis",
               "-scriptPath", script_dir, "-postScript", "Profile.java"]
    else:
        cmd = [headless, proj, "wechat", "-process", "-noanalysis",
               "-scriptPath", script_dir, "-postScript", "Profile.java"]
    r = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if r.returncode != 0:
        sys.stderr.write(r.stdout[-3000:] + "\n" + r.stderr[-2000:])
        raise SystemExit(f"analyzeHeadless failed ({r.returncode}); "
                         f"GHIDRA_INSTALL_DIR={ghidra}")
    return r.stdout + r.stderr


def parse_classes(out):
    classes = {}
    for m in re.finditer(
            r'"([A-Za-z:_][\w:]*)": \{"metaobject": "(\w+)", "stringdata": "(\w+)", '
            r'"data": "(\w+)", "static_metacall": "(\w+)", "vtables": \[([^\]]*)\]\}', out):
        name, mo, sd, dt, smc, vt = m.groups()
        classes[name] = {"metaobject": "0x" + mo, "stringdata": "0x" + sd,
                         "data": "0x" + dt, "static_metacall": "0x" + smc,
                         "vtables": [v.strip().strip('"') for v in vt.split(",") if v.strip()]}
    return classes


def parse_methods(out):
    methods = {}
    for match in re.finditer(r"METHOD ([A-Za-z_:][\w:]*) (\d+) ([A-Za-z_]\w*) (\d+)", out):
        owner, index, name, argc = match.groups()
        methods.setdefault(owner, {})[index] = {"name": name, "argc": int(argc)}
    return methods


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="profile.json")
    ap.add_argument("--wechat", default="/Applications/WeChat.app")
    ap.add_argument("--ghidra-lib", default=os.environ.get("GHIDRA_INSTALL_DIR"))
    ap.add_argument("--proj", default="/tmp/ghproj")
    ap.add_argument("--work", default="/tmp")
    ap.add_argument("--fresh", action="store_true", help="re-import instead of reusing the project")
    a = ap.parse_args()

    if not a.ghidra_lib:
        raise SystemExit("set GHIDRA_INSTALL_DIR or pass --ghidra-lib "
                         "(scripts/ghidra_macos_bootstrap.sh installs one)")
    dylib = os.path.join(a.wechat, "Contents", "Resources", "wechat.dylib")
    if not os.path.exists(dylib):
        raise SystemExit(f"not found: {dylib}")

    thin_path, sha = thin(dylib, a.work)
    out = run_headless(a.ghidra_lib, a.proj, thin_path, a.fresh)
    classes = parse_classes(out)
    if not classes:
        sys.stderr.write(out[-3000:])
        raise SystemExit("no QMetaObject found — check the Ghidra scripts / project")

    methods = parse_methods(out)
    if not methods:
        raise SystemExit("no method tables found — do not reuse a previous build's method ids")
    prof = {
        "schema": "wechat-bridge/native-profile/v1",
        "wechat": wechat_version(a.wechat),
        "module": dylib,
        "module_arch": "arm64",
        "slice_sha256": sha,
        "note": "RVAs are slice-relative addresses of the arm64 slice; at runtime use "
                "module_base + rva. static_metacall(QObject*, QMetaObject::Call, int id, void**) "
                "uses LOCAL method ids (see references/qt-native-send-derivation.md).",
        "classes": classes,
        "methods": methods,
        "runtime_ready": False,
        "note_runtime": "Static metadata only; editor ownership, recipient guards, GUI-thread "
                        "execution and delivery must be verified separately. No automatic send.",
    }
    with open(a.out, "w") as f:
        json.dump(prof, f, indent=2, ensure_ascii=False)
    print(json.dumps(prof, indent=2, ensure_ascii=False))
    print(f"\nwrote {a.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
