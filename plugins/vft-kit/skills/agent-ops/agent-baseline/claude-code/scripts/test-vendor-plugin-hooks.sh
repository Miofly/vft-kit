#!/usr/bin/env bash
# Isolated test for vendor-plugin-hooks.mjs: local git fixture as upstream, fake CLAUDE_CONFIG_DIR, no network.
# Covers: vendor + wire, idempotent rerun, --check, other hooks kept, broken upstream / bad repo / failing
# selftest keep the old version (exit 0), and plugin-still-enabled unwires to avoid double injection.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
up="$tmp/up"; cc="$tmp/cc"; vendor="$tmp/vendor"
mkdir -p "$up/.claude-plugin" "$up/src/hooks" "$up/skills/x" "$cc/plugins"
cat > "$up/.claude-plugin/plugin.json" <<'EOF'
{"hooks":{
 "SessionStart":[{"hooks":[{"type":"command","command":"HOOK_ROOT=\"${CLAUDE_PLUGIN_ROOT}\"; node \"$HOOK_ROOT/src/hooks/a.js\"","timeout":30}]}],
 "UserPromptSubmit":[{"hooks":[{"type":"command","command":"node \"${CLAUDE_PLUGIN_ROOT}/src/hooks/a.js\"","timeout":30}]}],
 "SessionEnd":[{"hooks":[{"type":"command","command":"node \"${CLAUDE_PLUGIN_ROOT}/src/hooks/stats.js\""}]}]}}
EOF
echo 'process.stdout.write("MARK "+require("fs").readFileSync(process.env.CLAUDE_PLUGIN_ROOT+"/skills/x/SKILL.md","utf8"))' > "$up/src/hooks/a.js"
echo 'v1' > "$up/skills/x/SKILL.md"
git -C "$up" init -q -b main && git -C "$up" add -A && git -C "$up" -c user.name=t -c user.email=t@t commit -qm v1
cat > "$tmp/cfg.json" <<EOF
{"repo":"$up","ref":"main","vendor":"$vendor","events":["SessionStart","UserPromptSubmit"],
 "files":["src/hooks","skills/x"],"expect":{"SessionStart":"MARK","UserPromptSubmit":"MARK"},"skipIfPluginEnabled":"demo@demo",
 "commands":{"demo":"demo-cmd.md","mine":"demo-cmd.md"}}
EOF
echo '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"other-hook"}]}]}}' > "$cc/settings.json"
printf -- '---\nmanaged-by: vft-kit vendor-plugin-hooks\n---\nbody\n' > "$tmp/demo-cmd.md"
mkdir -p "$cc/commands" && echo 'user owned' > "$cc/commands/mine.md"
run(){ CLAUDE_CONFIG_DIR="$cc" node "$DIR/vendor-plugin-hooks.mjs" --config "$tmp/cfg.json" "$@"; }
count(){ grep -o "export CLAUDE_PLUGIN_ROOT='$vendor/current'" "$cc/settings.json" | wc -l | tr -d ' '; }
fail(){ echo "FAIL: $*" >&2; exit 1; }

run | grep -q '已同步' || fail 'first sync'
[ "$(count)" = 2 ] || fail 'expected 2 wired hooks'
grep -q 'other-hook' "$cc/settings.json" || fail 'other hook lost'
! grep -q 'CLAUDE_PLUGIN_ROOT}' "$cc/settings.json" || fail 'CC refuses non-plugin hooks that reference ${CLAUDE_PLUGIN_ROOT}'
node -e "const j=require(process.argv[1]);process.exit(j.hooks.UserPromptSubmit[0].hooks[0].command.includes('vendor/current')&&!j.hooks.SessionEnd?0:1)" "$cc/settings.json" || fail 'order or unselected event'
grep -q 'managed-by' "$cc/commands/demo.md" || fail 'user command not installed'
[ "$(cat "$cc/commands/mine.md")" = 'user owned' ] || fail 'unmanaged command overwritten'
run | grep -q '已是最新' || fail 'idempotent rerun'
[ "$(count)" = 2 ] || fail 'rerun duplicated hooks'
run --check >/dev/null || fail '--check should pass'

# broken upstream: a selected file disappears -> keep old version, exit 0
git -C "$up" rm -qr skills/x && git -C "$up" -c user.name=t -c user.email=t@t commit -qm broken
run | grep -q '保留旧版本' || fail 'broken upstream not detected'
[ -f "$vendor/current/skills/x/SKILL.md" ] || fail 'old version not kept'
# failing selftest -> keep old version
git -C "$up" checkout -q HEAD~1 -- skills/x
echo 'process.exit(3)' > "$up/src/hooks/a.js"
git -C "$up" add -A && git -C "$up" -c user.name=t -c user.email=t@t commit -qm crash
run | grep -q '自检失败' || fail 'crashing hook not rejected'
grep -q MARK "$vendor/current/src/hooks/a.js" || fail 'crash version replaced current'
# unreachable repo -> warn, exit 0, wiring intact
CLAUDE_CONFIG_DIR="$cc" node "$DIR/vendor-plugin-hooks.mjs" --config "$tmp/cfg.json" --repo "$tmp/nope" | grep -q '拉取' || fail 'bad repo'
[ "$(count)" = 2 ] || fail 'bad repo broke wiring'

# plugin still installed+enabled -> unwire, never inject twice
echo '{"plugins":{"demo@demo":[{"installPath":"/x"}]}}' > "$cc/plugins/installed_plugins.json"
run --offline | grep -q '只 vendor 不接线' || fail 'plugin guard'
[ "$(count)" = 0 ] || fail 'hooks still wired while plugin enabled'
rm "$cc/plugins/installed_plugins.json"
run --offline >/dev/null && [ "$(count)" = 2 ] || fail 'rewire after plugin removed'
echo 'PASS: vendor-plugin-hooks'
