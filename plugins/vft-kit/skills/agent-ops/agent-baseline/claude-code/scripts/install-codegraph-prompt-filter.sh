#!/usr/bin/env bash
# Wrap `codegraph prompt-hook` (UserPromptSubmit) with codegraph-prompt-filter.py so that
# background task notifications and non-code prompts get no ~15 KB symbol injection.
# Idempotent. No-op when codegraph is not installed or its prompt hook is not configured.
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
for h in (d.get("hooks") or {}).get("UserPromptSubmit", []):
    for hh in h.get("hooks", []):
        if hh.get("command", "").strip() == "codegraph prompt-hook":
            hh["command"] = 'python3 "$HOME/.claude/hooks/codegraph-prompt-filter.py"'; n += 1
if n:
    shutil.copy(p, p + ".bak-codegraph-filter")
    json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
    print(f"  ✓ codegraph prompt-hook 已加过滤（{n} 处）")
PY
