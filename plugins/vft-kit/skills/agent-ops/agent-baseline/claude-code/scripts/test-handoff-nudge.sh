#!/usr/bin/env bash
# Isolated test: judge logic (self-test) + idempotent settings registration + shadow/live output, fake HOME only.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
python3 "$DIR/handoff-nudge.py" --self-test | grep -q 'self-test ok'
mkdir -p "$tmp/home/.claude"
echo '{"hooks":{"PostToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"other-hook"}]}]}}' > "$tmp/home/.claude/settings.json"
HOME="$tmp/home" bash "$DIR/install-handoff-nudge.sh" | grep -q installed
HOME="$tmp/home" bash "$DIR/install-handoff-nudge.sh" | grep -q unchanged
[ "$(grep -o 'handoff-nudge.py' "$tmp/home/.claude/settings.json" | wc -l | tr -d ' ')" = 1 ]
grep -q 'other-hook' "$tmp/home/.claude/settings.json"
[ ! -e "$tmp/home/.cache/vft-kit/handoff-nudge.LIVE" ]
tr="$tmp/t.jsonl"
echo '{"type":"assistant","message":{"model":"claude-sonnet-5","usage":{"input_tokens":5,"cache_read_input_tokens":99995,"cache_creation_input_tokens":0}}}' > "$tr"
payload="{\"session_id\":\"abc\",\"transcript_path\":\"$tr\",\"hook_event_name\":\"PostToolUse\"}"
out="$(echo "$payload" | HOME="$tmp/home" python3 "$DIR/handoff-nudge.py")"
[ -z "$out" ]                                                  # shadow: silent
grep -q '"tier": "0.40"' "$tmp/home/.cache/vft-kit/handoff-nudge.jsonl"
echo "$payload" | HOME="$tmp/home" python3 "$DIR/handoff-nudge.py" >/dev/null
[ "$(wc -l < "$tmp/home/.cache/vft-kit/handoff-nudge.jsonl" | tr -d ' ')" = 1 ]   # once per tier
touch "$tmp/home/.cache/vft-kit/handoff-nudge.LIVE"
echo '{"type":"assistant","message":{"model":"claude-sonnet-5","usage":{"input_tokens":5,"cache_read_input_tokens":149995}}}' >> "$tr"
echo "$payload" | HOME="$tmp/home" python3 "$DIR/handoff-nudge.py" | grep -q additionalContext
echo 'not json' | HOME="$tmp/home" python3 "$DIR/handoff-nudge.py"            # fail-open, exit 0
echo 'PASS: handoff-nudge'
