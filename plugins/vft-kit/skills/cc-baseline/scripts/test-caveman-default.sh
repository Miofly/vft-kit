#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

home="$tmp/home"
plugin="$tmp/caveman"
mkdir -p "$home/.claude/plugins" "$plugin/.claude-plugin" "$home/.config/caveman"

cat > "$home/.claude/plugins/installed_plugins.json" <<EOF
{"plugins":{"caveman@caveman":[{"installPath":"$plugin"}]}}
EOF
cat > "$plugin/.claude-plugin/plugin.json" <<'EOF'
{"hooks":{"SessionStart":[{"hooks":[{"command":"node ${CLAUDE_PLUGIN_ROOT}/src/hooks/caveman-activate.js"}]}]}}
EOF

output="$(HOME="$home" bash "$DIR/check.sh" 2>&1 || true)"
grep -q '✗.*Caveman 默认 full 自动启用' <<< "$output"

printf '%s\n' '{"defaultMode":"full"}' > "$home/.config/caveman/config.json"
output="$(HOME="$home" bash "$DIR/check.sh" 2>&1 || true)"
grep -q '✓.*Caveman 默认 full 自动启用' <<< "$output"

printf 'PASS: Caveman default full activation\n'
