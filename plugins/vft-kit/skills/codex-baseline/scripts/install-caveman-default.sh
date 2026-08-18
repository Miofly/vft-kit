#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
if [ ! -f "$CODEX_HOME/skills/caveman/SKILL.md" ] && [ ! -f "$HOME/.agents/skills/caveman/SKILL.md" ]; then
  npx --yes skills add JuliusBrussee/caveman --agent codex --global --yes
fi

if [ -n "${CODEX_AGENTS:-}" ]; then
  AGENTS="$CODEX_AGENTS"
elif [ -f "$CODEX_HOME/AGENTS.override.md" ]; then
  AGENTS="$CODEX_HOME/AGENTS.override.md"
else
  AGENTS="$CODEX_HOME/AGENTS.md"
fi
START_MARKER='<!-- >>> vft-kit caveman default full >>> -->'
END_MARKER='<!-- <<< vft-kit caveman default full <<< -->'

target_dir="$(dirname "$AGENTS")"
mkdir -p "$target_dir"
touch "$AGENTS"
mode="$(stat -f '%Lp' "$AGENTS" 2>/dev/null || stat -c '%a' "$AGENTS" 2>/dev/null || printf '600')"
tmp="$(mktemp "$target_dir/.AGENTS.caveman.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

awk -v start="$START_MARKER" -v end="$END_MARKER" '
  $0 == start { managed=1; next }
  managed { if ($0 == end) managed=0; next }
  { lines[++count]=$0 }
  END {
    while (count > 0 && lines[count] == "") count--
    for (i=1; i<=count; i++) print lines[i]
  }
' "$AGENTS" > "$tmp"

cat >> "$tmp" <<'EOF'

<!-- >>> vft-kit caveman default full >>> -->
## Caveman 默认 full 自动启用

- 每个新会话从第一条回复起默认使用 Caveman full：删除客套、填充词、重复解释和无意义铺垫，允许短句与片段表达。
- 保留全部技术事实、代码、命令、错误原文、风险与必要步骤；用户要求澄清或内容涉及安全警告、不可逆操作时优先清晰。
- 用户说 `stop caveman` 或 `normal mode` 时，仅在当前会话恢复普通表达。
<!-- <<< vft-kit caveman default full <<< -->
EOF

chmod "$mode" "$tmp" 2>/dev/null || true
mv "$tmp" "$AGENTS"
trap - EXIT

config="$HOME/.config/caveman/config.json"
mkdir -p "$(dirname "$config")"
node - "$config" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
let config = {};
try { config = JSON.parse(fs.readFileSync(file, 'utf8')); } catch {}
config.defaultMode = 'full';
const temp = `${file}.tmp-${process.pid}`;
fs.writeFileSync(temp, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
fs.renameSync(temp, file);
NODE

printf '  ✓ Caveman 默认 full 规则已写入 %s\n' "$AGENTS"
