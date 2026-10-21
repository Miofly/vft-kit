#!/usr/bin/env python3
"""UserPromptSubmit hook: pin the reply language when the prompt is not written in it.

Why: caveman (and similar style plugins) inject an English "Enforce this reply" reminder
every turn and tell the model to keep the user's dominant language. An English or
mostly-code prompt then gets an English reply, even when the global CLAUDE.md says
"always reply in Simplified Chinese". This hook adds one short line after those
reminders so the configured language wins; caveman still controls the terse style.

- Target language: env VFT_REPLY_LANG (default 简体中文). Only CJK targets are detected;
  for other targets the hook injects on every prompt.
- Skips prompts that already contain enough CJK text (ratio >= 0.3 of letters), slash
  commands and empty prompts, so normal Chinese prompts cost nothing.
- Off switch: ~/.cache/vft-kit/reply-lang.OFF.
- Fail-open: any error exits 0 with no output.
"""
import json
import os
import re
import sys

OFF = os.path.expanduser("~/.cache/vft-kit/reply-lang.OFF")
CJK = re.compile(r"[㐀-鿿豈-﫿]")
LETTER = re.compile(r"[A-Za-z㐀-鿿豈-﫿]")


def target_lang():
    return os.environ.get("VFT_REPLY_LANG", "").strip() or "简体中文"


def needs_pin(prompt, lang):
    text = (prompt or "").strip()
    if not text or text.startswith("/"):
        return False
    if not any(k in lang for k in ("中文", "汉语", "Chinese", "zh")):
        return True
    # Ignore pasted code blocks and inline code when measuring the prompt's language.
    prose = re.sub(r"```.*?```", " ", text, flags=re.S)
    prose = re.sub(r"`[^`]*`", " ", prose)
    letters = LETTER.findall(prose)
    if not letters:
        return True
    return len(CJK.findall(prose)) / len(letters) < 0.3


def message(lang):
    return (
        f"Reply language: {lang}. The user's global rule requires {lang} for every user-visible "
        f"line (status lines, answers, tables), even when the prompt is in English. This overrides "
        f"caveman's 'preserve the user's language' default; keep the caveman terse style in {lang}. "
        f"Code, commands, paths, API names and exact error strings stay verbatim."
    )


def main():
    if os.path.exists(OFF):
        return
    data = json.load(sys.stdin)
    lang = target_lang()
    if not needs_pin(data.get("prompt", ""), lang):
        return
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                             "additionalContext": message(lang)}},
                     ensure_ascii=False))


def self_test():
    zh = "简体中文"
    assert needs_pin("Why does the build fail on CI?", zh)
    assert not needs_pin("这个接口为什么 404", zh)
    assert not needs_pin("帮我看下 `useUserStore().logout()` 为什么不生效", zh)
    assert needs_pin("```\nTypeError: x is undefined\n```", zh)          # only code: pin
    assert not needs_pin("/caveman lite", zh)
    assert not needs_pin("", zh)
    assert needs_pin("这个", "English")                                 # non-CJK target: always
    assert "简体中文" in message(zh)
    print("self-test ok")


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test()
        sys.exit(0)
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
