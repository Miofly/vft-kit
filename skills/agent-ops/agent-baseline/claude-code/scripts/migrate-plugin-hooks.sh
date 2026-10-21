#!/usr/bin/env bash
# bash-prompt-guard / handoff-nudge / reply-lang-pin are now registered by the vft-kit plugin itself
# (hooks/hooks.json, scripts in scripts/hooks/). This removes the old
# absolute-path entries the former install-*.sh wrote into settings.json (idempotent).
# Only hook objects whose command names one of the three scripts and lacks CLAUDE_PLUGIN_ROOT are removed;
# a matcher group is dropped only when that removal empties it. Backup before writing: settings.json.bak-<timestamp>.
# Usage: [CLAUDE_CONFIG_DIR=~/.claude1] bash migrate-plugin-hooks.sh [--dry-run]
set -euo pipefail
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
python3 - "$SETTINGS" "${1:-}" <<'PY'
import json, os, shutil, sys, time
path, dry = sys.argv[1], sys.argv[2] == "--dry-run"
NAMES = ("bash-prompt-guard.py", "handoff-nudge.py", "reply-lang-pin.py")
if not os.path.exists(path):
    print(f"absent: {path}"); sys.exit(0)
d = json.load(open(path, encoding="utf-8"))
hooks = d.get("hooks") if isinstance(d.get("hooks"), dict) else {}
removed = []
def legacy(h):
    c = h.get("command", "") if isinstance(h, dict) else ""
    return any(n in c for n in NAMES) and "CLAUDE_PLUGIN_ROOT" not in c
for event in list(hooks):
    groups = hooks[event]
    if not isinstance(groups, list):
        continue
    kept_groups, touched = [], False
    for g in groups:
        hs = g.get("hooks") if isinstance(g, dict) else None
        if not isinstance(hs, list) or not any(legacy(h) for h in hs):
            kept_groups.append(g); continue
        touched = True
        removed += [f"{event}: {h['command']}" for h in hs if legacy(h)]
        g["hooks"] = [h for h in hs if not legacy(h)]
        if g["hooks"]:
            kept_groups.append(g)
    if touched:
        if kept_groups:
            hooks[event] = kept_groups
        else:
            del hooks[event]
if not removed:
    print(f"unchanged: {path}"); sys.exit(0)
for r in removed:
    print(f"{'would remove' if dry else 'removed'}: {r}")
if dry:
    sys.exit(0)
bak = f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
shutil.copy2(path, bak)
# write in place (not os.replace) so a symlinked settings.json stays a symlink
with open(path, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2); f.write("\n")
print(f"backup: {bak}")
PY
