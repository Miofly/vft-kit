#!/usr/bin/env python3
"""PreToolUse(Bash) guard: deny commands that would hit Claude Code's built-in confirmation prompts.

Claude Code asks the user before some Bash forms even in bypassPermissions mode (rm/rmdir on the session
cwd or its ancestors, on unguarded variables or command substitutions, multi-level globs; `cd` into
another directory combined with git). The user wants zero interruptions, so this hook
denies those forms with a rewrite hint; the model retries with a safe form and the user never sees a dialog.

Fail-open: any parse error or unexpected input prints nothing and exits 0 (normal flow continues).
Log: ~/.claude/logs/bash-prompt-guard.log (one line per deny).
"""
import json
import os
import re
import shlex
import sys
import time

TOP_LEVEL = {"/", "/usr", "/etc", "/var", "/tmp", "/bin", "/sbin", "/opt", "/Users", "/home",
             "/System", "/Library", "/Applications", "/private", "/mnt", "/Volumes"}
SEP = re.compile(r"\s*(?:&&|\|\||;|\|)\s*")


def segments(cmd):
    # Split on && || ; | outside quotes (good enough for the forms we look for).
    out, buf, q = [], "", None
    i = 0
    while i < len(cmd):
        c = cmd[i]
        if q:
            buf += c
            if c == q:
                q = None
        elif c in "'\"":
            q = c
            buf += c
        elif cmd.startswith("&&", i) or cmd.startswith("||", i):
            out.append(buf); buf = ""; i += 2; continue
        elif c in ";|\n":
            out.append(buf); buf = ""
        else:
            buf += c
        i += 1
    out.append(buf)
    return [s.strip() for s in out if s.strip()]


def words(seg):
    try:
        return shlex.split(seg, posix=True)
    except ValueError:
        return seg.split()


def norm(p, cwd):
    p = os.path.expanduser(p)
    if not os.path.isabs(p):
        p = os.path.join(cwd, p)
    return os.path.normpath(p)


def check(cmd, cwd):
    segs = segments(cmd)
    cd_away = False
    for seg in segs:
        raw = seg
        w = words(seg)
        if not w:
            continue
        head = w[0]
        if head in ("cd", "pushd") and len(w) > 1:
            if norm(w[1], cwd) != os.path.normpath(cwd):
                cd_away = True
            continue
        if cd_away and (head == "git" or (head == "rtk" and len(w) > 1 and w[1] == "git")):
            return "同一条命令里 cd 到别的目录后又跑 git 会弹确认框。改成不 cd，直接 `git -C <绝对路径> ...`。"
        # cd + file redirect also prompts in non-bypass modes, but `>` inside quotes/heredocs makes it too noisy
        # to detect here (135/2315 false hits on replay); covered by the written rule only.
        if head in ("rm", "rmdir") or (head == "sudo" and len(w) > 1 and w[1] in ("rm", "rmdir")):
            targets = [a for a in w[1:] if not a.startswith("-") and a not in ("rm", "rmdir")]
            for t in targets:
                if "$(" in raw or "`" in raw:
                    return "rm 目标里有命令替换会弹确认框。先单独跑替换拿到路径，再用字面绝对路径删。"
                if re.search(r"\*[^/]*/\*|\*/$", t):
                    return f"多层通配删除（{t}）会弹确认框。改用 `find <字面路径> -mindepth 1 -delete` 或逐个字面路径。"
                if "$" in t:
                    if re.search(r"\$\{?(HOME|PWD|OLDPWD|TMPDIR|USER)\b", t) or not re.fullmatch(r"(\"?\$\{[A-Za-z_][A-Za-z0-9_]*:\?[^}]*\}\"?[^$]*)+", t):
                        return f"rm 目标含变量（{t}）会弹确认框。写字面绝对路径，或用 \"${{VAR:?}}\" 展开（$HOME/$PWD 这类一律写字面路径）。"
                    continue
                p = norm(t, cwd)
                c = os.path.normpath(cwd)
                if p in TOP_LEVEL or p == os.path.expanduser("~") or c == p or c.startswith(p.rstrip("/") + "/"):
                    return (f"rm 目标 {p} 是会话当前目录（{c}）或其上级，会弹确认框；同一条命令里先 cd 出去不算数。"
                            "先单独发一条 `cd <别处>`，下一条命令再删；以后不要 cd 进要删的目录。")
    return None


def main():
    try:
        data = json.load(sys.stdin)
        if data.get("tool_name") != "Bash":
            return
        cmd = (data.get("tool_input") or {}).get("command") or ""
        cwd = data.get("cwd") or os.getcwd()
        reason = check(cmd, cwd)
        if not reason:
            return
        try:
            logd = os.path.expanduser("~/.claude/logs")
            os.makedirs(logd, exist_ok=True)
            with open(os.path.join(logd, "bash-prompt-guard.log"), "a", encoding="utf-8") as f:
                f.write(json.dumps({"t": time.strftime("%F %T"), "cwd": cwd, "cmd": cmd[:300], "reason": reason},
                                   ensure_ascii=False) + "\n")
        except Exception:
            pass
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                                 "permissionDecisionReason": "[bash-prompt-guard] " + reason}},
                         ensure_ascii=False))
    except Exception:
        return


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        cases = [
            ("cd /a/b && git status", "/x", True),
            ("git -C /a/b status", "/x", False),
            ("cd /x && git status", "/x", False),
            ("cd /a && grep foo . 2>/dev/null", "/x", False),
            ("rm -rf $T/$r-$a", "/x", True),
            ('rm -rf "${T:?}"/"${r:?}"', "/x", False),
            ('rm -rf "$HOME/foo"', "/x", True),
            ('rm -rf "$(pwd)"', "/x", True),
            ("rm -rf logs/*/*", "/x", True),
            ("cd /Users/wfly && rm -rf /Users/wfly/temp/ms-h3", "/Users/wfly/temp/ms-h3", True),
            ("rm -rf /Users/wfly/temp/ms-h3", "/Users/wfly", False),
            ("rm -rf /Users/wfly/temp", "/Users/wfly/temp/ms-h3/sub", True),
            ("rm -f /tmp/a.txt /tmp/b.txt", "/x", False),
            ("ls -la && echo hi > /tmp/x", "/x", False),
        ]
        bad = 0
        for cmd, cwd, want in cases:
            got = check(cmd, cwd) is not None
            if got != want:
                bad += 1
                print("FAIL", cmd, cwd, "want", want, "got", got)
        print("SELF_TEST", "ok" if not bad else f"{bad} failed")
        sys.exit(1 if bad else 0)
    main()
