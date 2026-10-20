#!/usr/bin/env python3
"""Fail when a quoted example sentence in edit-rules.md shares a 6-character run with an eval source text.

Rule examples that repeat test sentences let the rewriter copy the expected fix and inflate scores (2026-10-10:
three rounds had to replace leaked examples). Trigger-word lists (三个字以内的词串) are fine; whole example
sentences are not. Usage: check-contamination.py [--selftest]
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
RULES = HERE / "references" / "edit-rules.md"
CASES = [HERE / "evals" / "cases.jsonl", HERE / "evals" / "holdout.jsonl"]
N = 6
# Pattern vocabulary lists, not example sentences: comma-joined trigger words.
VOCAB = re.compile(r"^[^，。]{1,8}(、[^，。]{1,8})+$")


def grams(text):
    t = re.sub(r"\W", "", text)
    return {t[i:i + N] for i in range(len(t) - N + 1)}


def leaks(rules_text, sources):
    pool = set().union(*(grams(s) for s in sources)) if sources else set()
    out = []
    for example in re.findall(r"“([^”]{%d,})”" % N, rules_text):
        if VOCAB.match(example):
            continue
        hit = grams(example) & pool
        if hit:
            out.append((example, sorted(hit)[0]))
    return out


def main():
    if "--selftest" in sys.argv:
        assert leaks("举例“今天上线比较顺利”", ["这次上线比较顺利吗"]) == [("今天上线比较顺利", "上线比较顺利")]
        assert leaks("词表“值得注意的是、更重要的是”", ["值得注意的是缓存"]) == []
        print("selftest ok")
        return 0
    sources = [json.loads(line)["source"] for f in CASES if f.exists() for line in f.open(encoding="utf-8")]
    found = leaks(RULES.read_text(encoding="utf-8"), sources)
    for example, gram in found:
        print(f"LEAK: “{example[:40]}” shares “{gram}” with an eval source")
    print("clean" if not found else f"{len(found)} leaked example(s)")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
