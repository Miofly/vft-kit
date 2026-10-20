#!/usr/bin/env bash
# Isolated test: filter logic + idempotent settings rewrite, fake HOME only.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
python3 "$DIR/codegraph-prompt-filter.py" --selftest | grep -q 'selftest ok'
mkdir -p "$tmp/home/.claude"
cat > "$tmp/home/.claude/settings.json" <<'JSON'
{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"codegraph prompt-hook"}]}]}}
JSON
HOME="$tmp/home" bash "$DIR/install-codegraph-prompt-filter.sh" >/dev/null
HOME="$tmp/home" bash "$DIR/install-codegraph-prompt-filter.sh" >/dev/null
grep -q 'codegraph-prompt-filter.py' "$tmp/home/.claude/settings.json"
python3 -c 'import json,sys; h=json.load(open(sys.argv[1]))["hooks"]["UserPromptSubmit"][0]["hooks"][0]; sys.exit(0 if h.get("timeout")==10 else 1)' "$tmp/home/.claude/settings.json"
! grep -q '"codegraph prompt-hook"' "$tmp/home/.claude/settings.json"
[ -x "$tmp/home/.claude/hooks/codegraph-prompt-filter.py" ]
echo '{"prompt":"<task-notification>x</task-notification>"}' | HOME="$tmp/home" python3 "$DIR/codegraph-prompt-filter.py" | { ! read -r _; }
# shadow mode (default) logs the new decision; live mode with a plain-Chinese prompt prints nothing.
echo '{"prompt":"把 GPU 监控挂上","cwd":"/"}' | HOME="$tmp/home" CODEGRAPH_FILTER_SHADOW_LOG="$tmp/log.jsonl" python3 "$DIR/codegraph-prompt-filter.py" | { ! read -r _; }
grep -q '"mode": "shadow"' "$tmp/log.jsonl" && grep -q '"reason": "no_identifier"' "$tmp/log.jsonl"
echo '{"prompt":"实现一下这个需求","cwd":"/"}' | HOME="$tmp/home" CODEGRAPH_FILTER_MODE=live CODEGRAPH_FILTER_SHADOW_LOG="$tmp/log.jsonl" python3 "$DIR/codegraph-prompt-filter.py" | { ! read -r _; }
grep -q '"mode": "live"' "$tmp/log.jsonl"
echo 'PASS: codegraph prompt filter'
