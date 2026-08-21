#!/usr/bin/env bash
set -euo pipefail

installed="$HOME/.claude/plugins/installed_plugins.json"
has_plugin=0
has_hook=0

if [ -f "$installed" ]; then
  node -e "const j=require(process.argv[1]).plugins||{};process.exit(Object.keys(j).some(k=>k.split('@')[0]==='caveman')?0:1)" "$installed" 2>/dev/null && has_plugin=1
  node -e "const j=require(process.argv[1]).plugins||{};const v=Object.entries(j).find(([k])=>k.split('@')[0]==='caveman');const x=v&&Array.isArray(v[1])?v[1][0]:null;if(!x||!x.installPath)process.exit(1);const p=require(x.installPath+'/.claude-plugin/plugin.json');process.exit(/caveman-activate/.test(JSON.stringify(p.hooks&&p.hooks.SessionStart||[]))?0:1)" "$installed" 2>/dev/null && has_hook=1
fi

if [ "$has_plugin" -eq 0 ]; then
  claude plugin marketplace add JuliusBrussee/caveman 2>/dev/null || true
  claude plugin install caveman@caveman
elif [ "$has_hook" -eq 0 ]; then
  claude plugin marketplace update caveman 2>/dev/null || true
  claude plugin update caveman@caveman
fi

if ! claude plugin list --json 2>/dev/null | node -e '
let input="";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  try {
    const json = JSON.parse(input);
    const plugins = Array.isArray(json) ? json : (Array.isArray(json.plugins) ? json.plugins : []);
    process.exit(plugins.some(plugin => plugin.id === "caveman@caveman" && plugin.enabled === true) ? 0 : 1);
  } catch { process.exit(1); }
});'; then
  claude plugin enable caveman@caveman --scope user
fi

node <<'NODE'
const fs = require('fs');
const path = require('path');
const file = path.join(process.env.HOME, '.config', 'caveman', 'config.json');
fs.mkdirSync(path.dirname(file), { recursive: true });
let config = {};
try { config = JSON.parse(fs.readFileSync(file, 'utf8')); } catch {}
config.defaultMode = 'full';
const temp = `${file}.tmp-${process.pid}`;
fs.writeFileSync(temp, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
fs.renameSync(temp, file);
NODE

printf 'Caveman 已设为默认 full；新开 Claude Code 会话生效。\n'
