#!/usr/bin/env bash
# Isolated test: filter logic + idempotent settings rewrite, fake HOME only.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
python3 "$DIR/codegraph-prompt-filter.py" --self-test | grep -q 'self-test ok'
mkdir -p "$tmp/home/.claude"
cat > "$tmp/home/.claude/settings.json" <<'JSON'
{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"codegraph prompt-hook"}]}]}}
JSON
HOME="$tmp/home" bash "$DIR/install-codegraph-prompt-filter.sh" >/dev/null
HOME="$tmp/home" bash "$DIR/install-codegraph-prompt-filter.sh" >/dev/null
grep -q 'codegraph-prompt-filter.py' "$tmp/home/.claude/settings.json"
! grep -q '"codegraph prompt-hook"' "$tmp/home/.claude/settings.json"
[ -x "$tmp/home/.claude/hooks/codegraph-prompt-filter.py" ]
echo '{"prompt":"<task-notification>x</task-notification>"}' | python3 "$DIR/codegraph-prompt-filter.py" | { ! read -r _; }
echo 'PASS: codegraph prompt filter'
