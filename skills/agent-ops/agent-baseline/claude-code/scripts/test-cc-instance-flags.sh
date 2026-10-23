#!/usr/bin/env bash
# Isolated test: cc-instance-flags.sh copies source flags minus excludes, forces Monitor's gate on, keeps other config
# keys, survives a missing source, rewrites only on change, refuses the main dir, survives parallel runs. Fake dirs only.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
S="$DIR/cc-instance-flags.sh"; inst="$tmp/inst"; mkdir -p "$inst"; c="$inst/.claude.json"
echo '{"cachedGrowthBookFeatures":{"tengu_a":true,"tengu_bridge_x":true,"tengu_c4e_slash_upsell":true,"tengu_n":3,"tengu_amber_sentinel":false}}' > "$tmp/main.json"
echo '{"theme":"dark","cachedGrowthBookFeatures":{"stale":true}}' > "$c"
run() { CLAUDE_CONFIG_DIR="$inst" CC_FLAGS_SRC="$tmp/main.json" bash "$S" "$@"; }
[ "$(run --dry-run)" = "3 flags, changed" ]
grep -q stale "$c"                                              # dry-run writes nothing
run
[ "$(jq -c '.cachedGrowthBookFeatures' "$c")" = '{"tengu_a":true,"tengu_n":3,"tengu_amber_sentinel":true}' ]
[ "$(jq -r .theme "$c")" = dark ]                               # other keys kept
mt() { stat -f %m "$c" 2>/dev/null || stat -c %Y "$c"; }
touch -t 200001010000 "$c"; before=$(mt); run
[ "$(mt)" = "$before" ]                                         # unchanged: not rewritten
[ "$(run --dry-run)" = "3 flags, unchanged" ]
CLAUDE_CONFIG_DIR="$inst" CC_FLAGS_SRC="$tmp/none.json" bash "$S"
[ "$(jq -c '.cachedGrowthBookFeatures' "$c")" = '{"tengu_amber_sentinel":true}' ]  # missing source: forced flags only
CLAUDE_CONFIG_DIR="$inst" CC_FLAGS_SRC="$tmp/main.json" CC_FLAGS_FORCE="x y" bash "$S"
[ "$(jq -c '.cachedGrowthBookFeatures | {x,y,tengu_amber_sentinel}' "$c")" = '{"x":true,"y":true,"tengu_amber_sentinel":false}' ]
for i in 1 2 3 4 5 6; do run & done; wait                       # parallel launches: no failure, no tmp left, valid JSON
jq -e '.cachedGrowthBookFeatures.tengu_amber_sentinel == true' "$c" >/dev/null
[ -z "$(ls -A "$inst" | grep tmp || true)" ]
HOME="$tmp" CLAUDE_CONFIG_DIR="$tmp/.claude" bash "$S" 2>&1 | grep -q 'instance dir'  # main dir refused
CLAUDE_CONFIG_DIR="$tmp/nope" bash "$S" 2>&1 | grep -q missing
echo 'PASS: cc-instance-flags'
