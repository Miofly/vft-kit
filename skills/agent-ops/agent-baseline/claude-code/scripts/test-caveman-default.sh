#!/usr/bin/env bash
# Isolated test: caveman style mode moves from plugin to user-level hooks.
# Fake HOME, fake `claude`, local git fixture as upstream; no network, no real config touched.
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp:?}"' EXIT

home="$tmp/home"
up="$tmp/upstream"
bin="$tmp/bin"
log="$tmp/claude.log"
mkdir -p "$home/.claude/plugins" "$home/.config/caveman" "$bin" "$up/.claude-plugin" "$up/src/hooks"
for s in caveman ultracave megacave; do mkdir -p "$up/skills/$s"; echo "# $s" > "$up/skills/$s/SKILL.md"; done
echo 'process.stdout.write("CAVEMAN MODE ACTIVE")' > "$up/src/hooks/caveman-activate.js"
cat > "$up/.claude-plugin/plugin.json" <<'EOF'
{"hooks":{
 "SessionStart":[{"hooks":[{"type":"command","command":"node \"${CLAUDE_PLUGIN_ROOT}/src/hooks/caveman-activate.js\""}]}],
 "SubagentStart":[{"hooks":[{"type":"command","command":"node \"${CLAUDE_PLUGIN_ROOT}/src/hooks/caveman-activate.js\" --subagent"}]}],
 "UserPromptSubmit":[{"hooks":[{"type":"command","command":"node \"${CLAUDE_PLUGIN_ROOT}/src/hooks/caveman-activate.js\""}]}]}}
EOF
git -C "$up" init -q -b main && git -C "$up" add -A && git -C "$up" -c user.name=t -c user.email=t@t commit -qm v1
node -e "const c=require(process.argv[1]);c.repo=process.argv[2];c.vendor=process.argv[3];require('fs').writeFileSync(process.argv[4],JSON.stringify(c))" \
  "$DIR/../config/caveman-hooks.json" "$up" "$home/.cache/vft-kit/caveman" "$tmp/cfg.json"

# Start state: plugin installed + enabled, user hooks absent.
echo '{"plugins":{"caveman@caveman":[{"installPath":"/x"}]}}' > "$home/.claude/plugins/installed_plugins.json"
echo '{"enabledPlugins":{"caveman@caveman":true}}' > "$home/.claude/settings.json"
cat > "$bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CLAUDE_LOG"
if [ "$*" = "plugin uninstall caveman@caveman" ]; then
  node -e "const fs=require('fs');for(const [p,k] of [[process.argv[1],'plugins'],[process.argv[2],'enabledPlugins']]){const j=JSON.parse(fs.readFileSync(p));delete j[k]['caveman@caveman'];fs.writeFileSync(p,JSON.stringify(j))}" \
    "$HOME/.claude/plugins/installed_plugins.json" "$HOME/.claude/settings.json"
fi
EOF
chmod +x "$bin/claude"
env_run(){ HOME="$home" PATH="$bin:$PATH" CLAUDE_LOG="$log" CAVEMAN_VENDOR_CONFIG="$tmp/cfg.json" "$@"; }

output="$(env_run bash "$DIR/check.sh" 2>&1 || true)"
grep -q '✗.*Caveman 风格模式 hook' <<< "$output"

env_run bash "$DIR/install-caveman-default.sh" >/dev/null
env_run bash "$DIR/install-caveman-default.sh" >/dev/null
[ "$(grep -Fc 'plugin uninstall caveman@caveman' "$log")" -eq 1 ]
! grep -q 'plugin install\|plugin enable' "$log"
[ "$(grep -o "export CLAUDE_PLUGIN_ROOT='$home/.cache/vft-kit/caveman/current'" "$home/.claude/settings.json" | wc -l | tr -d ' ')" = 3 ]
node -e "const j=require(process.argv[1]);process.exit(j.defaultMode==='full'?0:1)" "$home/.config/caveman/config.json"
output="$(env_run bash "$DIR/check.sh" 2>&1 || true)"
grep -q '✓.*Caveman 风格模式 hook' <<< "$output"

printf 'PASS: Caveman style hooks vendored, plugin removed once, default full\n'
