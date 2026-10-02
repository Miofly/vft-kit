#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

home="$tmp/home"
plugin="$tmp/caveman"
bin="$tmp/bin"
log="$tmp/claude.log"
mkdir -p "$home/.claude/plugins" "$plugin/.claude-plugin" "$home/.config/caveman" "$bin"

cat > "$home/.claude/plugins/installed_plugins.json" <<EOF
{"plugins":{"caveman@caveman":[{"installPath":"$plugin"}]}}
EOF
cat > "$home/.claude/settings.json" <<'EOF'
{"enabledPlugins":{"caveman@caveman":false}}
EOF
cat > "$home/.config/caveman/config.json" <<'EOF'
{"defaultMode":"full"}
EOF
cat > "$plugin/.claude-plugin/plugin.json" <<'EOF'
{"hooks":{"SessionStart":[{"hooks":[{"command":"node ${CLAUDE_PLUGIN_ROOT}/src/hooks/caveman-activate.js"}]}]}}
EOF
cat > "$bin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CLAUDE_LOG"
if [ "$*" = "plugin list --json" ]; then
  node -e "const j=require(process.argv[1]);process.stdout.write(JSON.stringify([{id:'caveman@caveman',enabled:j.enabledPlugins['caveman@caveman']===true}]))" "$HOME/.claude/settings.json"
  exit 0
fi
if [ "$*" = "plugin enable caveman@caveman --scope user" ]; then
  node -e "const j=require(process.argv[1]);process.exit(j.enabledPlugins['caveman@caveman']===true?0:1)" "$HOME/.claude/settings.json" && exit 1
  node -e "const fs=require('fs');const p=process.argv[1];const j=JSON.parse(fs.readFileSync(p));j.enabledPlugins['caveman@caveman']=true;fs.writeFileSync(p,JSON.stringify(j))" "$HOME/.claude/settings.json"
fi
EOF
chmod +x "$bin/claude"

output="$(HOME="$home" PATH="$bin:$PATH" bash "$DIR/check.sh" 2>&1 || true)"
grep -q '✗.*Caveman 默认 full 自动启用' <<< "$output"

HOME="$home" PATH="$bin:$PATH" CLAUDE_LOG="$log" bash "$DIR/install-caveman-default.sh"
HOME="$home" PATH="$bin:$PATH" CLAUDE_LOG="$log" bash "$DIR/install-caveman-default.sh"
[ "$(grep -Fc 'plugin enable caveman@caveman --scope user' "$log")" -eq 1 ]
node -e "const j=require(process.argv[1]);process.exit(j.defaultMode==='full'?0:1)" "$home/.config/caveman/config.json"
output="$(HOME="$home" PATH="$bin:$PATH" bash "$DIR/check.sh" 2>&1 || true)"
grep -q '✓.*Caveman 默认 full 自动启用' <<< "$output"

printf 'PASS: Caveman installed, enabled, and default full\n'
