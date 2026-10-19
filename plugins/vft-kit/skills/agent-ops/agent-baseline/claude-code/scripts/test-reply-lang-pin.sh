#!/usr/bin/env bash
# Isolated test: language judge (self-test) + idempotent registration + output/off switch, fake HOME only.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
python3 "$DIR/reply-lang-pin.py" --self-test | grep -q 'self-test ok'
mkdir -p "$tmp/home/.claude"
echo '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"other-hook"}]}]}}' > "$tmp/home/.claude/settings.json"
HOME="$tmp/home" bash "$DIR/install-reply-lang-pin.sh" | grep -q installed
HOME="$tmp/home" bash "$DIR/install-reply-lang-pin.sh" | grep -q unchanged
[ "$(grep -o 'reply-lang-pin.py' "$tmp/home/.claude/settings.json" | wc -l | tr -d ' ')" = 1 ]
grep -q 'other-hook' "$tmp/home/.claude/settings.json"
echo '{"prompt":"Why is the build failing?"}' | HOME="$tmp/home" python3 "$DIR/reply-lang-pin.py" | grep -q '简体中文'
[ -z "$(echo '{"prompt":"为什么构建失败"}' | HOME="$tmp/home" python3 "$DIR/reply-lang-pin.py")" ]
echo '{"prompt":"hi"}' | HOME="$tmp/home" VFT_REPLY_LANG=English python3 "$DIR/reply-lang-pin.py" | grep -q 'Reply language: English'
mkdir -p "$tmp/home/.cache/vft-kit"; touch "$tmp/home/.cache/vft-kit/reply-lang.OFF"
[ -z "$(echo '{"prompt":"Why?"}' | HOME="$tmp/home" python3 "$DIR/reply-lang-pin.py")" ]
echo 'not json' | HOME="$tmp/home" python3 "$DIR/reply-lang-pin.py"          # fail-open, exit 0
echo 'PASS: reply-lang-pin'
