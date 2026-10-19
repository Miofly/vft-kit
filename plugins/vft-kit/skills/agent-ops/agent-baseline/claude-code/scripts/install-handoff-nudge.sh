#!/usr/bin/env bash
# Register handoff-nudge.py as a PostToolUse(*) hook in ~/.claude/settings.json (idempotent).
# Shadow by default: it only appends to ~/.cache/vft-kit/handoff-nudge.jsonl what it would have said.
# Go live: touch ~/.cache/vft-kit/handoff-nudge.LIVE (the marker is never created by this installer).
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/handoff-nudge.py"
SETTINGS="${HOME}/.claude/settings.json"
python3 "$HOOK" --self-test >/dev/null
mkdir -p "$(dirname "$SETTINGS")"
python3 - "$SETTINGS" "$HOOK" <<'PY'
import json, os, sys
path, hook = sys.argv[1], sys.argv[2]
d = json.load(open(path)) if os.path.exists(path) else {}
post = d.setdefault("hooks", {}).setdefault("PostToolUse", [])
cmd = f'python3 "{hook}"'
for block in post:
    for h in block.get("hooks", []):
        if "handoff-nudge.py" in h.get("command", ""):
            if h["command"] == cmd:
                print("unchanged"); sys.exit(0)
            h["command"] = cmd
            json.dump(d, open(path, "w"), ensure_ascii=False, indent=2)
            print("updated"); sys.exit(0)
post.append({"matcher": "*", "hooks": [{"type": "command", "command": cmd, "timeout": 5}]})
json.dump(d, open(path, "w"), ensure_ascii=False, indent=2)
print("installed")
PY
