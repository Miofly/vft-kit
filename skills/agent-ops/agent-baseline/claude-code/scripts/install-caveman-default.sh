#!/usr/bin/env bash
# Caveman 风格模式改走用户级 hook，不再装 caveman 插件本体（插件的几十个 skill/agent 每会话白占上下文）。
#   1. vendor-plugin-hooks.mjs 拉上游最新代码，只 vendor 风格模式要的文件到 ~/.cache/vft-kit/caveman/current，
#      把 SessionStart / SubagentStart / UserPromptSubmit 三个 hook 写进 settings.json（配置见 config/caveman-hooks.json，
#      可用 CAVEMAN_VENDOR_CONFIG 指向别的配置）。拉取或自检失败时保留旧版本，不弄坏风格模式。
#   2. 插件还装着时：vendor 版本自检通过才卸载插件，卸载后再接线；插件在时不接线，同一规则不会注入两次。
#   3. 把 ~/.config/caveman/config.json 的 defaultMode 固定为 full（新旧版本都认）。
set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SYNC="$SCRIPT_DIR/vendor-plugin-hooks.mjs"
CONF="${CAVEMAN_VENDOR_CONFIG:-$SCRIPT_DIR/../config/caveman-hooks.json}"
PLUGIN="caveman@caveman"
INSTALLED="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"

node "$SYNC" --config "$CONF"

plugin_installed(){
  [ -f "$INSTALLED" ] && node -e "const j=require(process.argv[1]).plugins||{};process.exit(j[process.argv[2]]?0:1)" "$INSTALLED" "$PLUGIN" 2>/dev/null
}
if plugin_installed; then
  if node "$SYNC" --config "$CONF" --check >/dev/null 2>&1; then
    if claude plugin uninstall "$PLUGIN" >/dev/null 2>&1 || ! plugin_installed; then
      printf '  ✓ 已卸载 %s 插件，风格模式改由用户级 hook 提供\n' "$PLUGIN"
      node "$SYNC" --config "$CONF" --offline
    else
      printf '  ○ 卸载 %s 失败；保持插件版，用户级 hook 暂不接线\n' "$PLUGIN" >&2
    fi
  else
    printf '  ○ vendor 版本自检未通过；保持 %s 插件版，不卸载\n' "$PLUGIN" >&2
  fi
fi

node <<'NODE'
const fs = require('fs');
const path = require('path');
const file = path.join(process.env.HOME, '.config', 'caveman', 'config.json');
fs.mkdirSync(path.dirname(file), { recursive: true });
let config = {};
try { config = JSON.parse(fs.readFileSync(file, 'utf8')); } catch {}
if (config.defaultMode !== 'full') {
  config.defaultMode = 'full';
  const temp = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(temp, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temp, file);
}
NODE

printf 'Caveman 风格模式（用户级 hook，默认 full）已就位；新开 Claude Code 会话生效。\n'
