#!/usr/bin/env bash
# codex-baseline —— 核对本机 Codex 是否符合装配基线。
# 只读，不改配置；缺什么就打印对应修复命令。
set -uo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CODEX_HOME/config.toml"
AGENTS="$CODEX_HOME/AGENTS.md"
PLUGIN_CACHE="$CODEX_HOME/plugins/cache"
SYSTEM_SKILLS="$CODEX_HOME/skills/.system"

pass=0; fail=0; warn=0
c_g=$'\033[32m'; c_r=$'\033[31m'; c_y=$'\033[33m'; c_d=$'\033[2m'; c_0=$'\033[0m'
ok()  { printf "  ${c_g}✓${c_0} %s\n" "$1"; pass=$((pass+1)); }
bad() { printf "  ${c_r}✗${c_0} %-34s ${c_d}→ 修复: %s${c_0}\n" "$1" "$2"; fail=$((fail+1)); }
opt() { printf "  ${c_y}○${c_0} %-34s ${c_d}(可选) %s${c_0}\n" "$1" "$2"; warn=$((warn+1)); }
sec(){ printf "\n${c_d}== %s ==${c_0}\n" "$1"; }

has_cmd(){ command -v "$1" >/dev/null 2>&1; }
cfg_has_line(){
  [ -f "$CONFIG" ] || return 1
  grep -Eq "$1" "$CONFIG"
}
cfg_section_has_line(){
  [ -f "$CONFIG" ] || return 1
  awk -v section="$1" -v pat="$2" '
    $0 ~ "^\\[" { in_section=($0==section) }
    in_section && $0 ~ pat { found=1 }
    END { exit found?0:1 }
  ' "$CONFIG"
}
plugin_enabled(){
  local key="$1"
  cfg_section_has_line "[plugins.\"$key\"]" '^[[:space:]]*enabled[[:space:]]*=[[:space:]]*true[[:space:]]*$'
}
plugin_cached(){
  local key="$1"
  local plugin="${key%@*}"
  local marketplace="${key#*@}"
  [ -d "$PLUGIN_CACHE/$marketplace/$plugin" ] && find "$PLUGIN_CACHE/$marketplace/$plugin" -mindepth 1 -maxdepth 1 -type d | grep -q .
}
skill_exists(){
  [ -f "$SYSTEM_SKILLS/$1/SKILL.md" ]
}
project_trusted(){
  local path="$1"
  cfg_section_has_line "[projects.\"$path\"]" '^[[:space:]]*trust_level[[:space:]]*=[[:space:]]*"trusted"[[:space:]]*$'
}
agents_has(){
  [ -f "$AGENTS" ] || return 1
  grep -Eq "$1" "$AGENTS"
}
chromium_installed(){
  local dir
  for dir in "$HOME/Library/Caches/ms-playwright" "$HOME/.cache/ms-playwright"; do
    [ -d "$dir" ] && find "$dir" -mindepth 1 -maxdepth 1 -type d -name 'chromium*' | grep -q . && return 0
  done
  return 1
}

printf "${c_d}Codex 装配基线核对 (codex-baseline)${c_0}\n"

sec "CLI 工具"
if has_cmd codex; then
  codex_version="$(codex --version 2>&1)"
  if [ "$?" -eq 0 ]; then
    ok "codex ($(printf '%s' "$codex_version" | tr '\n' ' '))"
  else
    bad "codex CLI 可执行" "Volta: volta install @openai/codex@latest；或 npm: npm install -g @openai/codex@latest"
  fi
else
  bad "codex" "安装/更新 Codex CLI"
fi
has_cmd node  && ok "node ($(node -v 2>/dev/null))"                       || bad "node" "安装 Node 22.x"
has_cmd npm   && ok "npm ($(npm -v 2>/dev/null))"                         || bad "npm" "随 node 安装"
has_cmd git   && ok "git ($(git --version 2>/dev/null | awk '{print $3}'))" || bad "git" "安装 git"
has_cmd jq    && ok "jq"                                                   || opt "jq" "brew install jq"

sec "dangerous full access 权限基线"
[ -f "$CONFIG" ] && ok "$CONFIG" || bad "config.toml" "创建 ~/.codex/config.toml"
cfg_has_line '^[[:space:]]*approval_policy[[:space:]]*=[[:space:]]*"never"[[:space:]]*$' && ok 'approval_policy = "never"' || bad "approval_policy" '在 ~/.codex/config.toml 顶层加入: approval_policy = "never"'
cfg_has_line '^[[:space:]]*sandbox_mode[[:space:]]*=[[:space:]]*"danger-full-access"[[:space:]]*$' && ok 'sandbox_mode = "danger-full-access"' || bad "sandbox_mode" '在 ~/.codex/config.toml 顶层加入: sandbox_mode = "danger-full-access"'
cfg_section_has_line "[notice]" '^[[:space:]]*hide_full_access_warning[[:space:]]*=[[:space:]]*true[[:space:]]*$' && ok "full access 警告已隐藏" || opt "full access 警告隐藏" '在 [notice] 下加入: hide_full_access_warning = true'

sec "项目与 hooks"
cfg_section_has_line "[features]" '^[[:space:]]*hooks[[:space:]]*=[[:space:]]*true[[:space:]]*$' && ok "features.hooks = true" || bad "hooks feature" '在 [features] 下加入: hooks = true'
if project_trusted "/"; then
  ok "/ 已信任"
elif project_trusted "$HOME/Documents/code/wfly"; then
  ok "$HOME/Documents/code/wfly 已信任"
else
  bad "项目 trust_level" '在 ~/.codex/config.toml 加入 [projects."/"] trust_level = "trusted" 或信任常用代码根'
fi

sec "Playwright MCP"
if cfg_section_has_line "[mcp_servers.playwright]" '^[[:space:]]*command[[:space:]]*='; then
  ok "playwright MCP 已配置"
  if cfg_section_has_line "[mcp_servers.playwright]" '^[[:space:]]*enabled[[:space:]]*=[[:space:]]*false[[:space:]]*$'; then
    bad "playwright MCP 已禁用" '删除 [mcp_servers.playwright] 下的 enabled = false，或改为 enabled = true'
  else
    ok "playwright MCP 已启用"
  fi
else
  bad "playwright MCP" "codex mcp add playwright -- npx --yes @playwright/mcp@latest"
fi
chromium_installed && ok "Playwright Chromium 内核" || bad "Playwright Chromium 内核" "npx --yes playwright install chromium"

sec "CLI 插件（启用 + cache）"
for key in \
  "github@openai-api-curated" \
  "superpowers@openai-api-curated"
do
  if plugin_enabled "$key"; then ok "$key enabled"; else bad "$key enabled" "codex plugin add $key"; fi
  if plugin_cached "$key"; then ok "$key cache"; else bad "$key cache" "codex plugin add $key"; fi
done

sec "系统 skills"
for s in openai-docs imagegen skill-creator plugin-creator skill-installer; do
  skill_exists "$s" && ok "$s" || bad "$s" "恢复 $SYSTEM_SKILLS/$s/SKILL.md"
done

sec "全局 AGENTS 规范"
[ -f "$AGENTS" ] && ok "$AGENTS" || opt "全局 AGENTS.md" "创建 ~/.codex/AGENTS.md"
agents_has '中文回复|简体中文|一律中文|reply.*[Cc]hinese' && ok "全局规范含「始终中文回复」" || opt "中文回复规范" $'printf \'\\n- 始终使用简体中文回复。\\n\' >> ~/.codex/AGENTS.md'
agents_has '可点短链|短链|markdown 可点|Cannot open file' && ok "全局规范含「代码位置可点短链」" || opt "代码短链规范" $'printf \'\\n- 引用代码位置使用 markdown 可点短链：[短名:行](绝对路径:行)。\\n\' >> ~/.codex/AGENTS.md'
agents_has '上下文压缩|压缩取舍|保留决策和状态' && ok "全局规范含「压缩取舍规则」" || opt "压缩取舍规范" $'printf \'\\n- 上下文压缩时保留决策和状态，丢弃可重跑恢复的噪音。\\n\' >> ~/.codex/AGENTS.md'

printf "\n${c_d}────────────────────────────────${c_0}\n"
printf "结果：${c_g}%d 正常${c_0} / ${c_r}%d 缺失(必需)${c_0} / ${c_y}%d 可选提醒${c_0}\n" "$pass" "$fail" "$warn"
if [ "$fail" -eq 0 ]; then
  printf "${c_g}✓ Codex 必备基线齐全。${c_0}\n"
  printf "${c_d}提示：配置变更后新开 Codex 会话才稳定生效。${c_0}\n"
  exit 0
else
  printf "${c_r}✗ 有 %d 项必需基线缺失，按上面修复命令补齐后重跑。${c_0}\n" "$fail"
  printf "${c_d}提示：配置变更后新开 Codex 会话才稳定生效。${c_0}\n"
  exit 1
fi
