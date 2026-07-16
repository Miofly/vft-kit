#!/usr/bin/env bash
# cc-baseline —— 核对本机 Claude Code 是否符合装配基线。
# 分六类逐项体检：CLI 工具 / 全局 npm 包 / MCP 注册 / 插件 / 系统配置(RTK hook、状态栏、App) / 配置基线。
# 只读，不改任何东西；缺什么就打印对应的修复命令。
# 退出码：所有「必需」项齐全=0；有必需项缺失=1。可选项缺失不影响退出码。
set -uo pipefail

# --health：额外跑「MCP 连接健康检查」（会实连每个 MCP，较慢，默认不跑）
HEALTH=0
for a in "$@"; do [ "$a" = "--health" ] && HEALTH=1; done

CLAUDE_JSON="$HOME/.claude.json"
SETTINGS="$HOME/.claude/settings.json"
NPM_ROOT="$(npm root -g 2>/dev/null || echo '')"

pass=0; fail=0; warn=0
c_g=$'\033[32m'; c_r=$'\033[31m'; c_y=$'\033[33m'; c_d=$'\033[2m'; c_0=$'\033[0m'
ok()  { printf "  ${c_g}✓${c_0} %s\n" "$1"; pass=$((pass+1)); }
bad() { printf "  ${c_r}✗${c_0} %-30s ${c_d}→ 修复: %s${c_0}\n" "$1" "$2"; fail=$((fail+1)); }
opt() { printf "  ${c_y}○${c_0} %-30s ${c_d}(可选未装) %s${c_0}\n" "$1" "$2"; warn=$((warn+1)); }
sec(){ printf "\n${c_d}== %s ==${c_0}\n" "$1"; }  # section 标题；勿命名为 head（会覆盖系统 head 命令）

has_cmd(){ command -v "$1" >/dev/null 2>&1; }

# MCP 是否注册（user scope 或任意 project scope 都算）
mcp_registered(){
  [ -f "$CLAUDE_JSON" ] || return 1
  node -e "const j=require('$CLAUDE_JSON');const s=new Set(Object.keys(j.mcpServers||{}));for(const p in (j.projects||{})){const m=j.projects[p].mcpServers;if(m)Object.keys(m).forEach(k=>s.add(k))}process.exit(s.has(process.argv[1])?0:1)" "$1" 2>/dev/null
}
# 插件是否已安装（读 installed_plugins.json，确定性文件读，覆盖 user/project/local 全 scope）
# 不用 `claude plugin list`：它慢（逐个实连 MCP 健康检查）且输出不稳定、还可能触发 CC 重建清单。
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
plugin_installed(){
  [ -f "$INSTALLED_PLUGINS" ] || return 1
  node -e "const j=require('$INSTALLED_PLUGINS').plugins||{};process.exit(Object.keys(j).some(k=>k.split('@')[0]===process.argv[1])?0:1)" "$1" 2>/dev/null
}
# 全局 npm 包是否装（查 node_modules 目录，比 npm ls 快）
npm_g_installed(){ [ -n "$NPM_ROOT" ] && [ -d "$NPM_ROOT/$1" ]; }
# settings.json 里某个 hook 命令是否含关键字
hook_has(){
  [ -f "$SETTINGS" ] || return 1
  node -e "const s=require('$SETTINGS');process.exit(new RegExp(process.argv[1],'i').test(JSON.stringify(s.hooks||{}))?0:1)" "$1" 2>/dev/null
}
# RTK 配置里 [hooks].exclude_commands 是否已排除「压缩会致错」的命令(cat/diff/find/grep/curl/head/wc)
# 见 SKILL.md：这七条命令过 RTK 压缩会静默出错(截断文件/坏 patch/漏文件/截断行漏匹配/假 JSON/取错数)，必须原样透传。
RTK_CONFIG="$HOME/Library/Application Support/rtk/config.toml"
rtk_excludes_verbatim(){
  [ -f "$RTK_CONFIG" ] || return 1
  local line; line=$(grep -E '^[[:space:]]*exclude_commands' "$RTK_CONFIG" 2>/dev/null) || return 1
  local cmd
  for cmd in cat diff find grep curl head wc; do printf '%s' "$line" | grep -q "\"$cmd\"" || return 1; done
}
# statusLine 命令是否含关键字
statusline_has(){
  [ -f "$SETTINGS" ] || return 1
  node -e "const s=require('$SETTINGS');process.exit(new RegExp(process.argv[1],'i').test(JSON.stringify(s.statusLine||{}))?0:1)" "$1" 2>/dev/null
}
# permissions.defaultMode 是否等于指定值
defaultmode_is(){
  [ -f "$SETTINGS" ] || return 1
  node -e "const s=require('$SETTINGS');process.exit((s.permissions&&s.permissions.defaultMode)===process.argv[1]?0:1)" "$1" 2>/dev/null
}
# permissions.allow 是否含匹配某正则的条目
perm_allows(){
  [ -f "$SETTINGS" ] || return 1
  node -e "const s=require('$SETTINGS');const a=(s.permissions&&s.permissions.allow)||[];process.exit(a.some(x=>new RegExp(process.argv[1]).test(x))?0:1)" "$1" 2>/dev/null
}
# ~/.claude.json 里某目录是否已通过文件夹信任（hasTrustDialogAccepted）
dir_trusted(){
  [ -f "$CLAUDE_JSON" ] || return 1
  node -e "const j=require('$CLAUDE_JSON');const p=(j.projects||{})[process.argv[1]];process.exit(p&&p.hasTrustDialogAccepted===true?0:1)" "$1" 2>/dev/null
}
# ~/.claude.json 顶层某布尔字段是否为 true
claudejson_true(){
  [ -f "$CLAUDE_JSON" ] || return 1
  node -e "const j=require('$CLAUDE_JSON');process.exit(j[process.argv[1]]===true?0:1)" "$1" 2>/dev/null
}
# settings.json 的 env.<KEY> 是否等于指定值
env_is(){
  [ -f "$SETTINGS" ] || return 1
  node -e "const s=require('$SETTINGS');process.exit((s.env||{})[process.argv[1]]===process.argv[2]?0:1)" "$1" "$2" 2>/dev/null
}
# 全局 ~/.claude/CLAUDE.md 是否含「始终中文回复」规范
claudemd_has_chinese(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] || return 1
  grep -Eq '中文回复|简体中文|一律中文|reply.*[Cc]hinese' "$f"
}
# 全局 ~/.claude/CLAUDE.md 是否含「引用代码位置用可点短链」规范
claudemd_has_shortlink(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] || return 1
  grep -Eq '可点短链|短链|markdown 可点|Cannot open file' "$f"
}
# MCP 是否实连成功（在 claude mcp list 输出里匹配 $1 正则的行含 Connected）
mcp_healthy(){ printf '%s\n' "$MCP_HEALTH" | grep -E "$1" | grep -q "Connected"; }

printf "${c_d}Claude Code 装配基线核对 (cc-baseline)${c_0}\n"

# ---------- 1. CLI 工具 ----------
sec "CLI 工具"
has_cmd node   && ok "node ($(node -v 2>/dev/null))"        || bad "node"   "装 Node 22.x"
has_cmd npm    && ok "npm ($(npm -v 2>/dev/null))"          || bad "npm"    "随 node 安装"
has_cmd claude && ok "claude ($(claude --version 2>/dev/null|awk '{print $1}'))" || bad "claude" "Claude Code CLI 未装"
has_cmd rtk    && ok "rtk ($(rtk --version 2>/dev/null))"   || opt "rtk"    "brew install rtk（省 token 命令代理，可选）"
has_cmd codegraph && ok "codegraph ($(codegraph -V 2>/dev/null))" || bad "codegraph" "npm i -g @colbymchenry/codegraph"
has_cmd brew   && ok "brew"                                 || opt "brew"   "Homebrew 建议装"
has_cmd jq     && ok "jq"                                   || opt "jq"     "brew install jq"

# ---------- 2. 全局 npm 包（MCP 载体） ----------
sec "全局 npm 包"
npm_g_installed "@colbymchenry/codegraph"                     && ok "@colbymchenry/codegraph"                     || bad "@colbymchenry/codegraph" "npm i -g @colbymchenry/codegraph"
npm_g_installed "@danielsogl/lighthouse-mcp"                  && ok "@danielsogl/lighthouse-mcp"                  || bad "@danielsogl/lighthouse-mcp" "npm i -g @danielsogl/lighthouse-mcp"

# ---------- 3. MCP 注册 ----------
sec "MCP 服务器（已注册到 CC）"
mcp_registered codegraph           && ok "codegraph"           || bad "codegraph MCP"           "codegraph install -t claude -l global -y"
mcp_registered lighthouse-mcp      && ok "lighthouse-mcp"      || bad "lighthouse-mcp MCP"      "claude mcp add lighthouse-mcp -s user -- node \"\$(npm root -g)/@danielsogl/lighthouse-mcp/dist/index.js\""

# ---------- 4. 插件（默认必备集） ----------
sec "插件（默认必备集）"
# 精简后的默认必备插件清单（用户指定）：核心工作流 + 自研
for p in superpowers skill-creator code-review frontend-design playwright \
         claude-hud remember typescript-lsp jdtls-lsp security-guidance \
         claude-md-management context-mode; do
  if plugin_installed "$p"; then ok "$p"; else
    case "$p" in
      claude-hud)                     bad "$p" "claude plugin marketplace add jarrodwatts/claude-hud && claude plugin install claude-hud@claude-hud";;
      context-mode)                   bad "$p" "claude plugin marketplace add mksglu/claude-context-mode && claude plugin install context-mode@context-mode";;
      *)                              bad "$p" "claude plugin install $p@claude-plugins-official";;
    esac
  fi
done
# 可选插件（装了更好，不装不算故障）
for p in context7 vercel; do
  if plugin_installed "$p"; then ok "$p"; else opt "$p" "claude plugin install $p@claude-plugins-official"; fi
done

# ---------- 5. 系统配置 ----------
sec "系统配置"
# rtk 是可选安装，分级自洽：
#   未装 rtk               → opt（整段跳过，不算故障）
#   装了但没挂 hook        → opt（装了没启用命令压缩，是用户选择，不算故障）
#   挂了 hook 但豁免不全    → bad（rtk 真在拦命令却配错 = 静默数据损坏，必须硬报）
if has_cmd rtk; then
  if hook_has "rtk"; then
    ok "RTK hook（PreToolUse Bash 命令优化）"
    # 修复命令整行替换 exclude_commands，兼容「空数组 / 已有部分值 / 已满」任意现状
    rtk_excludes_verbatim       && ok "RTK 压缩豁免（cat/diff/find/grep/curl/head/wc 原样透传）" || bad "RTK 压缩豁免"    'rtk config --create 2>/dev/null; sed -i "" '"'"'s/^[[:space:]]*exclude_commands[[:space:]]*=.*/exclude_commands = ["cat", "diff", "find", "grep", "curl", "head", "wc"]/'"'"' "$HOME/Library/Application Support/rtk/config.toml"'
  else
    opt "RTK hook（+ 压缩豁免）"  "rtk init -g --auto-patch（装了 rtk 但未挂 hook，命令压缩未启用）"
  fi
else
  opt "RTK（hook + 压缩豁免）"    "brew install rtk && rtk init -g --auto-patch（未装 rtk，跳过）"
fi
statusline_has "claude-hud"     && ok "状态栏 statusLine（claude-hud）"      || bad "claude-hud 状态栏" "在 CC 里运行 /claude-hud:setup"
[ -d "/Applications/CC Switch.app" ] && ok "cc-switch App"                  || opt "cc-switch App"    "brew install --cask cc-switch"

# ---------- 6. 配置基线 ----------
sec "配置基线"
defaultmode_is "bypassPermissions" && ok "bypassPermissions（免确认默认模式）" || bad "bypassPermissions" 'jq ".permissions.defaultMode=\"bypassPermissions\"" ~/.claude/settings.json'
claudejson_true "bypassPermissionsModeAccepted" && ok "bypass 警告已接受（免开机确认）" || bad "bypass 警告接受" 'jq ".bypassPermissionsModeAccepted=true" ~/.claude.json'
dir_trusted "$HOME"                && ok "~ 目录已信任（免文件夹信任弹窗）"    || bad "~ 目录信任" "jq '.projects[\"$HOME\"].hasTrustDialogAccepted=true' ~/.claude.json"
perm_allows "codegraph"            && ok "codegraph 只读工具白名单（permissions.allow）" || bad "codegraph 白名单" '把 "mcp__codegraph__*" 加进 ~/.claude/settings.json 的 permissions.allow'
env_is "DISABLE_AUTOUPDATER" "1"   && ok "自动更新已关闭（env.DISABLE_AUTOUPDATER）"    || bad "关闭自动更新" "jq '.env.DISABLE_AUTOUPDATER=\"1\"' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json"
[ -f "$HOME/.claude/CLAUDE.md" ]   && ok "全局 ~/.claude/CLAUDE.md"          || bad "全局 CLAUDE.md" "创建 ~/.claude/CLAUDE.md（全局规范）"
claudemd_has_chinese               && ok "全局规范含「始终中文回复」"          || bad "中文回复规范" $'printf \'\\n- **始终使用中文回复**（简体中文）。无论用户用什么语言提问、上下文/工具输出是什么语言，回复正文一律中文。\\n\' >> ~/.claude/CLAUDE.md'
claudemd_has_shortlink             && ok "全局规范含「代码位置用可点短链」"    || bad "代码短链规范" $'printf \'\\n- **引用代码位置一律用 markdown 可点短链**：IDEA 插件里裸文件名点不动会报 Cannot open file，须写成 [短名:行](绝对路径:行)。\\n\' >> ~/.claude/CLAUDE.md'
hook_has "notify"                  && ok "通知 hook（notify / claude-island）" || opt "通知 hook"        "配置 notify-config.json + hook（任务完成通知）"
[ -d "$HOME/.claude/projects" ]    && ok "项目 memory 目录"                   || opt "项目 memory"     "~/.claude/projects/<项目>/memory/ 跨会话记忆"

# ---------- 7. MCP 连接健康（仅 --health） ----------
if [ "$HEALTH" -eq 1 ]; then
  sec "MCP 连接健康（--health 实连检查）"
  MCP_HEALTH="$(claude mcp list 2>/dev/null || echo '')"
  # 核心 MCP：<名字正则> <显示名>
  mcp_healthy '^codegraph:'           && ok "codegraph 已连接"           || bad "codegraph 未连"           "codegraph serve --mcp 起不来，检查 codegraph install / 重启 CC"
  mcp_healthy '^lighthouse-mcp:'      && ok "lighthouse-mcp 已连接"      || bad "lighthouse-mcp 未连"      "检查 dist/index.js 路径，重跑 claude mcp add"
  mcp_healthy ':playwright:'          && ok "playwright 已连接（插件 MCP）" || bad "playwright 未连"        "npx @playwright/mcp@latest 起不来；先装浏览器 npx playwright install chromium"
else
  printf "\n${c_d}（跳过 MCP 连接健康检查；加 --health 参数可实连核对 codegraph/lighthouse/playwright）${c_0}\n"
fi

# ---------- 汇总 ----------
printf "\n${c_d}────────────────────────────────${c_0}\n"
printf "结果：${c_g}%d 正常${c_0} / ${c_r}%d 缺失(必需)${c_0} / ${c_y}%d 可选未装${c_0}\n" "$pass" "$fail" "$warn"
if [ "$fail" -eq 0 ]; then
  printf "${c_g}✓ 必备工具链齐全。${c_0}\n"
  exit 0
else
  printf "${c_r}✗ 有 %d 项必需工具缺失，按上面「修复」命令补齐后重跑本脚本。${c_0}\n" "$fail"
  printf "${c_d}提示：装完 MCP/插件/状态栏需重启 CC 会话才生效。${c_0}\n"
  exit 1
fi
