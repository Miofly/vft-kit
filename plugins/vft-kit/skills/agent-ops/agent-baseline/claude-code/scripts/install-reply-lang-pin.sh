#!/usr/bin/env bash
# Register reply-lang-pin.py as a UserPromptSubmit hook in ~/.claude/settings.json (idempotent).
# Live by default (user asked for it); off switch: touch ~/.cache/vft-kit/reply-lang.OFF.
# Target language: env VFT_REPLY_LANG (default 简体中文).
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/reply-lang-pin.py"
SETTINGS="${HOME}/.claude/settings.json"
python3 "$HOOK" --self-test >/dev/null
mkdir -p "$(dirname "$SETTINGS")"
python3 - "$SETTINGS" "$HOOK" <<'PY'
import json, os, sys
path, hook = sys.argv[1], sys.argv[2]
d = json.load(open(path)) if os.path.exists(path) else {}
ups = d.setdefault("hooks", {}).setdefault("UserPromptSubmit", [])
cmd = f'python3 "{hook}"'
for block in ups:
    for h in block.get("hooks", []):
        if "reply-lang-pin.py" in h.get("command", ""):
            if h["command"] == cmd:
                print("unchanged"); sys.exit(0)
            h["command"] = cmd
            json.dump(d, open(path, "w"), ensure_ascii=False, indent=2)
            print("updated"); sys.exit(0)
ups.append({"hooks": [{"type": "command", "command": cmd, "timeout": 5}]})
json.dump(d, open(path, "w"), ensure_ascii=False, indent=2)
print("installed")
PY
