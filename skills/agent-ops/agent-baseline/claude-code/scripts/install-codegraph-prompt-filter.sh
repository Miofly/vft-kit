#!/usr/bin/env bash
# Wrap `codegraph prompt-hook` (UserPromptSubmit) with codegraph-prompt-filter.py so that
# background task notifications and non-code prompts get no ~15 KB symbol injection.
# Sets the hook timeout to 10 s. The filter defaults to live mode (new gate);
# `touch ~/.cache/vft-kit/codegraph-prompt-filter.SHADOW` switches back to shadow (legacy output + decision log). Idempotent. No-op when codegraph is not installed or its prompt hook is not configured.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
DEST="$HOME/.claude/hooks/codegraph-prompt-filter.py"
[ -f "$SETTINGS" ] || exit 0
mkdir -p "$(dirname "$DEST")"
install -m 755 "$DIR/codegraph-prompt-filter.py" "$DEST"
python3 - "$SETTINGS" <<'PY'
import json, sys, shutil
p = sys.argv[1]; d = json.load(open(p)); n = 0
t = 0
for h in (d.get("hooks") or {}).get("UserPromptSubmit", []):
    for hh in h.get("hooks", []):
        if hh.get("command", "").strip() == "codegraph prompt-hook":
            hh["command"] = 'python3 "$HOME/.claude/hooks/codegraph-prompt-filter.py"'; n += 1
        # The filter caps codegraph at 8-9 s; give Claude Code's hook timeout 10 s so it never fires first.
        if "codegraph-prompt-filter.py" in hh.get("command", "") and "timeout" not in hh:
            hh["timeout"] = 10; t += 1
if n or t:
    shutil.copy(p, p + ".bak-codegraph-filter")
    json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
    if n: print(f"  ✓ codegraph prompt-hook 已加过滤（{n} 处）")
    if t: print(f"  ✓ codegraph prompt-hook 过滤已设 timeout 10（{t} 处）")
PY
