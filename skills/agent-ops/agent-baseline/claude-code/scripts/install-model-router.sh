#!/usr/bin/env bash
# Install tzachbon/claude-model-router-hook at a pinned commit plus the vft-kit micro-patch
# (patches/claude-model-router-hook.patch), as a local Directory plugin. Idempotent.
#
# Why patched, not stock: stock has_task_intent abstains on every Chinese prompt; its
# UserPromptSubmit hook exits 2 in warn mode (blocks the prompt until /model is run); and it
# injects a model into named agents, overriding e.g. a haiku carrier with opus. The patch
# fixes those three and logs advisory decisions. Chinese keywords live in config, not code.
# It also points SessionStart at hooks/session_brief.py: silent when healthy (routing
# rules live in the global CLAUDE.md), one line only when router variants go missing,
# instead of upstream's ~1.4k-char "Model Tier Rules ... (MANDATORY)" table, which
# contradicts this config (only mechanical work is lowered). PreToolUse routing is unchanged.
# The variant agent (router:haiku, router:opus-high, ...) descriptions shrink to "Router-internal; do not use.": every session
# lists them, and Claude Code has no way to hide an agent the hook must still reach
# (deny Agent(name) disables it, and hook "allow" never overrides a deny rule).
#
# Config (config/model-router.json -> ~/.claude/model-router.json, never overwritten):
# only mechanical work goes to haiku, every other class stays opus/high, so routing can
# only lower cost. Starts as subagent_enforcement=advisory (shadow: log + systemMessage);
# set it to "on" after reviewing ~/.claude/hooks/model-router-hook.log.
# Upgrade: bump REV, regenerate the patch against it, run scripts/test-model-router.sh.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="https://github.com/tzachbon/claude-model-router-hook"
REV="f687111e1bd1947df23d676354afc99467294a39"
DEST="${MODEL_ROUTER_DIR:-$HOME/.cache/vft-kit/claude-model-router-hook}"
PATCH="$DIR/../patches/claude-model-router-hook.patch"
CONF="$HOME/.claude/model-router.json"
PLUGIN="router@claude-model-router-hook"

if [ ! -d "$DEST/.git" ]; then
  mkdir -p "$(dirname "$DEST")"
  git clone -q "$REPO" "$DEST"
fi
changed=0
if [ "$(git -C "$DEST" rev-parse HEAD)" != "$REV" ] || ! git -C "$DEST" apply --reverse --check "$PATCH" 2>/dev/null; then
  git -C "$DEST" cat-file -e "$REV^{commit}" 2>/dev/null || git -C "$DEST" fetch -q origin
  git -C "$DEST" checkout -q -f "$REV"
  git -C "$DEST" clean -qfd -- plugins   # drop files an older patch added, so apply is clean
  git -C "$DEST" apply "$PATCH"
  changed=1
fi

[ -f "$CONF" ] || install -m 644 "$DIR/../config/model-router.json" "$CONF"

if ! claude plugin marketplace list 2>/dev/null | grep -q "Directory ($DEST)"; then
  claude plugin marketplace add "$DEST" >/dev/null
fi
if ! claude plugin list 2>/dev/null | grep -q "$PLUGIN"; then
  claude plugin install "$PLUGIN" >/dev/null
elif [ "$changed" -eq 1 ]; then
  bash "$DIR/../../plugins/scripts/refresh-local-plugin.sh" -p router -m claude-model-router-hook >/dev/null  # plugin "router", marketplace "claude-model-router-hook"
fi

# Superseded by the router: drop the earlier agent-model-guard hook if still registered.
python3 - "$HOME/.claude/settings.json" <<'PY'
import json, os, sys
p = sys.argv[1]
if not os.path.exists(p): sys.exit(0)
d = json.load(open(p)); n = 0
for ev, blocks in (d.get("hooks") or {}).items():
    keep = []
    for b in blocks:
        hs = [h for h in b.get("hooks", []) if "agent-model-guard.py" not in h.get("command", "")]
        n += len(b.get("hooks", [])) - len(hs)
        if hs: b["hooks"] = hs; keep.append(b)
    d["hooks"][ev] = keep
if n:
    json.dump(d, open(p, "w"), ensure_ascii=False, indent=2)
PY
echo "  ✓ model-router 已安装（固定 ${REV:0:7} + vft-kit 补丁；配置 ${CONF}）"
