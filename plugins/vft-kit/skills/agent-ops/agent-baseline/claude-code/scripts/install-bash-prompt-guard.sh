#!/usr/bin/env bash
# Register bash-prompt-guard.py as a PreToolUse(Bash) hook in ~/.claude/settings.json (idempotent).
# The guard denies Bash forms that would trigger Claude Code's built-in confirmation prompts and tells the
# model how to rewrite them, so the user is never interrupted. Fail-open by design.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/bash-prompt-guard.py"
SETTINGS="${HOME}/.claude/settings.json"
python3 "$GUARD" --self-test >/dev/null
python3 - "$SETTINGS" "$GUARD" <<'PY'
import json, os, sys
path, guard = sys.argv[1], sys.argv[2]
d = json.load(open(path)) if os.path.exists(path) else {}
pre = d.setdefault("hooks", {}).setdefault("PreToolUse", [])
cmd = f'python3 "{guard}"'
for block in pre:
    for h in block.get("hooks", []):
        if "bash-prompt-guard.py" in h.get("command", ""):
            h["command"] = cmd
            json.dump(d, open(path, "w"), ensure_ascii=False, indent=2)
            print("updated"); sys.exit(0)
pre.append({"matcher": "Bash", "hooks": [{"type": "command", "command": cmd, "timeout": 5}]})
json.dump(d, open(path, "w"), ensure_ascii=False, indent=2)
print("installed")
PY
