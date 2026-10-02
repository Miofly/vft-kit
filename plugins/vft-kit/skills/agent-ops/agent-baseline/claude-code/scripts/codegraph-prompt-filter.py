#!/usr/bin/env python3
"""Gate for `codegraph prompt-hook` (UserPromptSubmit).

Skips injection for background task notifications and non-code prompts, which
otherwise receive ~15 KB of irrelevant symbols every turn. Code-looking prompts
are passed through unchanged to `codegraph prompt-hook`.
Self-test: python3 codegraph-prompt-filter.py --self-test
"""
import json, re, subprocess, sys

CODE_HINT = re.compile(
    r"(\.(java|ts|tsx|js|mjs|vue|py|go|rs|kt|sql|yaml|yml|json|sh)\b)"  # file extensions
    r"|([A-Za-z_]+/[A-Za-z_./-]+)"                                      # paths
    r"|(\b[a-z]+[A-Z][A-Za-z]+\b)|(\b[A-Z][a-z]+[A-Z][A-Za-z]+\b)"      # camelCase / PascalCase
    r"|(\b[a-z]+_[a-z_]+\b)"                                            # snake_case
    r"|(函数|代码|报错|异常|接口|类名|方法|组件|编译|单测|测试用例|重构|实现|修复|bug|Bug|BUG|stack|trace)"
)

def should_run(prompt: str) -> bool:
    if "<task-notification>" in prompt or "[SYSTEM NOTIFICATION" in prompt:
        return False
    return bool(CODE_HINT.search(prompt))

def main():
    raw = sys.stdin.read()
    try:
        prompt = json.loads(raw).get("prompt", "") or ""
    except Exception:
        prompt = raw
    if not should_run(prompt):
        return 0
    return subprocess.run(["codegraph", "prompt-hook"], input=raw, text=True).returncode

def self_test():
    cases = {
        "<task-notification><task-id>x</task-id></task-notification>": False,
        "帮我思考怎么减少token消耗": False,
        "aistudio现在什么进展": False,
        "修复 VideoTaskServiceImpl 的空指针": True,
        "看下 src/views/tools/index.vue 为什么报错": True,
        "lease_account_db 脚本续租": True,
    }
    bad = [p for p, want in cases.items() if should_run(p) != want]
    print("self-test", "FAIL " + repr(bad) if bad else "ok")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else main())
