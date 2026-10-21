#!/usr/bin/env bash
# Isolated test: judge logic (self-test) + shadow/live output, fake HOME only.
set -euo pipefail
unset CLAUDE_CODE_AUTO_COMPACT_WINDOW HANDOFF_NUDGE_WINDOW   # session env would override the transcript-based window
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../scripts/hooks" && pwd)"   # scripts/hooks
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
python3 "$DIR/handoff-nudge.py" --self-test | grep -q 'self-test ok'
mkdir -p "$tmp/home"
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
