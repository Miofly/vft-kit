#!/usr/bin/env python3
"""Read-only private Studio health probe; token stays out of argv and logs."""
import argparse
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.request


def runtime_url(studio):
    if not re.fullmatch(r"[A-Za-z0-9_-]+/[A-Za-z0-9_-]+", studio):
        raise ValueError("Expected Studio owner/repo with letters, digits, hyphens or underscores")
    return "https://studio-" + studio.replace("/", "-") + ".api-inference.modelscope.net/health"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("studio", nargs="?")
    parser.add_argument("--token-file", type=Path, help="JSON containing api_key; defaults to MODELSCOPE_API_KEY")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        assert runtime_url("example/demo-cpu") == "https://studio-example-demo-cpu.api-inference.modelscope.net/health"
        for invalid in ["../demo", "https://example/demo", "example/demo?token=x", "example/demo/extra"]:
            try:
                runtime_url(invalid)
            except ValueError:
                continue
            raise AssertionError(invalid)
        print("runtime probe self-check passed")
        return 0
    if not args.studio:
        parser.error("studio is required")
    url = runtime_url(args.studio)
    token = json.loads(args.token_file.read_text())["api_key"] if args.token_file else os.environ.get("MODELSCOPE_API_KEY")
    if not token:
        parser.error("set MODELSCOPE_API_KEY or --token-file")
    request = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    try:
        response = urllib.request.urlopen(request, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    except urllib.error.URLError as error:
        print(json.dumps({"url":url,"reachable":False,"error":str(error.reason).replace(token,"[REDACTED]")}))
        return 1
    with response:
        body = response.read(4096).decode("utf-8", errors="replace").replace(token,"[REDACTED]")
        print(json.dumps({"url":url,"http":response.status,"body":body}, ensure_ascii=False))
        return 0 if response.status == 200 else 1


if __name__ == "__main__":
    raise SystemExit(main())
