#!/usr/bin/env bash
# Isolated test: migrate-plugin-hooks.sh removes only the old absolute-path entries, keeps everything else,
# backs up before writing, is idempotent, honours CLAUDE_CONFIG_DIR and --dry-run. Fake config dir only.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
cfg="$tmp/cfg"; mkdir -p "$cfg"; s="$cfg/settings.json"
cat > "$s" <<'JSON'
{"model":"opus","hooks":{
 "PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"},{"type":"command","command":"python3 \"/old/scripts/bash-prompt-guard.py\"","timeout":5}]}],
 "PostToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"python3 \"/old/scripts/handoff-nudge.py\"","timeout":5}]},{"matcher":"Edit","hooks":[{"type":"command","command":"other-post"}]}],
 "UserPromptSubmit":[{"hooks":[{"type":"command","command":"python3 \"/old/scripts/reply-lang-pin.py\"","timeout":5}]},{"hooks":[{"type":"command","command":"python3 \"${CLAUDE_PLUGIN_ROOT}/scripts/hooks/reply-lang-pin.py\""}]}],
 "Stop":[{"hooks":[{"type":"command","command":"python3 \"/old/scripts/handoff-nudge.py\""}]}]}}
JSON
before="$(cat "$s")"
CLAUDE_CONFIG_DIR="$cfg" bash "$DIR/migrate-plugin-hooks.sh" --dry-run | grep -q 'would remove'
[ "$(cat "$s")" = "$before" ]                                   # dry-run writes nothing
[ -z "$(ls "$cfg" | grep bak- || true)" ]
out="$(CLAUDE_CONFIG_DIR="$cfg" bash "$DIR/migrate-plugin-hooks.sh")"
[ "$(echo "$out" | grep -c '^removed:')" = 4 ]
[ "$(ls "$cfg" | grep -c 'settings.json.bak-')" = 1 ]
[ "$(cat "$cfg"/settings.json.bak-*)" = "$before" ]
python3 - "$s" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); h = d["hooks"]
assert d["model"] == "opus"
assert h["PreToolUse"] == [{"matcher": "Bash", "hooks": [{"type": "command", "command": "rtk hook claude"}]}], h["PreToolUse"]
assert h["PostToolUse"] == [{"matcher": "Edit", "hooks": [{"type": "command", "command": "other-post"}]}], h["PostToolUse"]
assert len(h["UserPromptSubmit"]) == 1 and "CLAUDE_PLUGIN_ROOT" in h["UserPromptSubmit"][0]["hooks"][0]["command"]
assert "Stop" not in h                                          # emptied event dropped
PY
CLAUDE_CONFIG_DIR="$cfg" bash "$DIR/migrate-plugin-hooks.sh" | grep -q '^unchanged'
[ "$(ls "$cfg" | grep -c 'settings.json.bak-')" = 1 ]           # idempotent: no second backup
mkdir -p "$tmp/home/.claude"; echo '{"hooks":{}}' > "$tmp/home/.claude/settings.json"
HOME="$tmp/home" CLAUDE_CONFIG_DIR= bash "$DIR/migrate-plugin-hooks.sh" | grep -q "unchanged: $tmp/home/.claude/settings.json"
CLAUDE_CONFIG_DIR="$tmp/none" bash "$DIR/migrate-plugin-hooks.sh" | grep -q '^absent'
echo 'PASS: migrate-plugin-hooks'
