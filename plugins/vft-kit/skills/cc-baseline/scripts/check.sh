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
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CODEX_AUTH="$HOME/.codex/auth.json"
ZSHENV="${ZDOTDIR:-$HOME}/.zshenv"

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
# statusLine 最终是否渲染 claude-hud——含直接引用与委托链（如 island-statusline → *-delegate → claude-hud）。
# 只 grep command 字符串本身、其指向的脚本、及同目录的 *statusline*/*delegate* 伴生脚本，不整目录扫。
statusline_uses_hud(){
  [ -f "$SETTINGS" ] || return 1
  local cmd; cmd=$(node -e "const s=require('$SETTINGS');process.stdout.write((s.statusLine&&s.statusLine.command)||'')" 2>/dev/null)
  [ -n "$cmd" ] || return 1
  printf '%s' "$cmd" | grep -qi 'claude-hud' && return 0   # 直接引用
  local tok f dir base g                                    # 委托链
  for tok in $cmd; do
    case "$tok" in /*) f="$tok" ;; *) continue ;; esac
    [ -f "$f" ] || continue
    grep -qi 'claude-hud' "$f" 2>/dev/null && return 0
    dir=$(dirname "$f"); base=$(basename "$f")
    for g in "$dir/$base"* "$dir/"*delegate* "$dir/"*statusline*; do
      [ -f "$g" ] && grep -qi 'claude-hud' "$g" 2>/dev/null && return 0
    done
  done
  return 1
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
# ~/.codex/auth.json 是否含非空 OPENAI_API_KEY（只判断，不输出 key）
codex_auth_has_key(){
  [ -f "$CODEX_AUTH" ] || return 1
  node -e 'const fs=require("fs");try{const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.exit(typeof j.OPENAI_API_KEY==="string"&&j.OPENAI_API_KEY.length>0?0:1)}catch{process.exit(1)}' "$CODEX_AUTH" 2>/dev/null
}
# ~/.zshenv 是否装有 vft-kit 管理的 Codex key 注入器
codex_key_injector_installed(){
  [ -f "$ZSHENV" ] || return 1
  grep -Fq '# >>> vft-kit codex auth env >>>' "$ZSHENV" &&
    grep -Fq '# <<< vft-kit codex auth env <<<' "$ZSHENV"
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
# 全局 ~/.claude/CLAUDE.md 是否含「上下文压缩取舍规则」规范
# 见 SKILL.md：compact/摘要时该留什么(架构决策/改过的文件/阻塞/失败方案)、该丢什么(冗长输出/已入 git 的内容)。
claudemd_has_compact(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] || return 1
  grep -Eq '上下文压缩|压缩取舍|保留决策和状态' "$f"
}
# 全局 ~/.claude/CLAUDE.md 是否含「外网操作代理兜底」规范
# 见 SKILL.md：境外访问连不上/被 RST/超时/慢得反常时，先探到可用本地代理走代理重试，别在直连路径反复重试。
# 关键字用通用语义词，不绑死具体端口/软件——别人机器可能是 v2rayN(10809)/clash verge(7897) 等。
claudemd_has_proxy(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] || return 1
  grep -Eiq '代理兜底|走代理重试|外网.*代理|127\.0\.0\.1:78|http\.proxy|https_proxy' "$f"
}
# 全局 ~/.claude/CLAUDE.md 是否含「多 Agent 并行执行」规范
# 见 SKILL.md：任务含多个互相独立的子项时主动起多个 subagent 并行执行、别串行干等。
# 关键字用通用语义词、中英兼容（subagent / 并行 agent / 扇出 / fan-out / 并行执行）。
claudemd_has_parallel_agents(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] || return 1
  grep -Eiq '并行.*[Aa]gent|多.*[Aa]gent|多个 subagent|subagent 并行|扇出|fan-?out|并行执行|默认并行|能加速就上' "$f"
}
# skill 是否已安装（~/.claude/skills/<name> 目录存在，或作为同名插件装了）
# anysearch 主要走手动装到 ~/.claude/skills/anysearch，marketplace 装则落为插件，两种都认。
skill_installed(){
  [ -d "$HOME/.claude/skills/$1" ] && return 0
  plugin_installed "$1"
}
# 全局 ~/.claude/CLAUDE.md 是否含「anysearch 联网搜索优先」调用场景规范
# 仅在 anysearch 已装时才核对：装了搜索 skill 却没告诉 CC 何时调它，等于白装。
claudemd_has_anysearch(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] || return 1
  grep -Eiq 'anysearch' "$f"
}
# 全局 ~/.claude/CLAUDE.md 是否含「agentmemory 持久化记忆」使用规范
# agentmemory 是必装 MCP，必须告诉 CC 何时主动调用（remember/recall/recap/forget/handoff）及自动工作机制。
claudemd_has_agentmemory(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] || return 1
  grep -Eiq 'agentmemory|持久化记忆.*agentmemory|记忆.*自动管理' "$f"
}
# 全局 ~/.claude/CLAUDE.md 是否含「CodeGraph 自动初始化」规范
# codegraph CLI 已装时必需：进入新项目若没有 .codegraph 目录，自动建索引，充分利用代码知识图谱。
claudemd_has_codegraph_auto_init(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] || return 1
  grep -Eiq 'codegraph.*自动|\.codegraph.*自动建立|自动.*codegraph.*索引|codegraph.*新项目' "$f"
}
# 全局 ~/.claude/CLAUDE.md 是否含「context7 官方文档优先」调用场景规范
# 仅在 context7 已装时才核对：装了文档 MCP 却没告诉 CC 何时查，容易继续凭旧记忆答库/框架/API 用法。
claudemd_has_context7(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] || return 1
  grep -Eiq 'context7|[Cc]ontext7|官方文档|最新文档|库.*框架.*文档|SDK.*文档|API.*文档' "$f"
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
has_cmd gh     && ok "gh ($(gh --version 2>/dev/null|head -1|awk '{print $3}'))" || opt "gh"     "brew install gh（GitHub CLI：PR/Actions/仓库操作，可选）"

# ---------- 2. 全局 npm 包（MCP 载体） ----------
sec "全局 npm 包"
npm_g_installed "@colbymchenry/codegraph"                     && ok "@colbymchenry/codegraph"                     || bad "@colbymchenry/codegraph" "npm i -g @colbymchenry/codegraph"
npm_g_installed "@danielsogl/lighthouse-mcp"                  && ok "@danielsogl/lighthouse-mcp"                  || bad "@danielsogl/lighthouse-mcp" "npm i -g @danielsogl/lighthouse-mcp"

# ---------- 3. MCP 注册 ----------
sec "MCP 服务器（已注册到 CC）"
mcp_registered codegraph           && ok "codegraph"           || bad "codegraph MCP"           "codegraph install -t claude -l global -y"
mcp_registered lighthouse-mcp      && ok "lighthouse-mcp"      || bad "lighthouse-mcp MCP"      "claude mcp add lighthouse-mcp -s user -- node \"\$(npm root -g)/@danielsogl/lighthouse-mcp/dist/index.js\""
mcp_registered agentmemory         && ok "agentmemory"         || bad "agentmemory MCP"         "bash \"$SCRIPT_DIR/install-agentmemory.sh\""

# ---------- 4. 插件（默认必备集） ----------
sec "插件（默认必备集）"
# 精简后的默认必备插件清单（用户指定）：核心工作流 + 自研 + 反过度工程
for p in superpowers skill-creator code-review frontend-design playwright \
         claude-hud remember typescript-lsp jdtls-lsp security-guidance \
         claude-md-management context-mode ponytail caveman gsap-skills; do
  if plugin_installed "$p"; then ok "$p"; else
    case "$p" in
      claude-hud)                     bad "$p" "claude plugin marketplace add jarrodwatts/claude-hud && claude plugin install claude-hud@claude-hud";;
      context-mode)                   bad "$p" "claude plugin marketplace add mksglu/claude-context-mode && claude plugin install context-mode@context-mode";;
      ponytail)                       bad "$p" "claude plugin marketplace add DietrichGebert/ponytail && claude plugin install ponytail@ponytail（两条要分开发）";;
      caveman)                        bad "$p" "claude plugin marketplace add JuliusBrussee/caveman && claude plugin install caveman@caveman（两条要分开发，省 65% 输出 token）";;
      gsap-skills)                    bad "$p" "claude plugin marketplace add greensock/gsap-skills && claude plugin install gsap-skills@gsap-skills（GSAP 官方，两条要分开发）";;
      *)                              bad "$p" "claude plugin install $p@claude-plugins-official";;
    esac
  fi
done
# 可选插件（装了更好，不装不算故障）
for p in context7 vercel; do
  if plugin_installed "$p"; then ok "$p"; else opt "$p" "claude plugin install $p@claude-plugins-official"; fi
done
# 可选 skill：anysearch（AI Agent 联网实时搜索，装到 ~/.claude/skills/anysearch）
skill_installed anysearch && ok "anysearch skill（联网实时搜索）" || opt "anysearch skill" "bash \"$SCRIPT_DIR/install-anysearch.sh\"（自动安装、随机邮箱注册 key 并写入 skill/.env）"

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
statusline_uses_hud             && ok "状态栏 statusLine（claude-hud）"      || bad "claude-hud 状态栏" "在 CC 里运行 /claude-hud:setup（或让现有 statusLine 委托给 claude-hud）"
[ -d "/Applications/CC Switch.app" ] && ok "cc-switch App"                  || opt "cc-switch App"    "brew install --cask cc-switch"

# ---------- 6. 配置基线 ----------
sec "配置基线"
defaultmode_is "bypassPermissions" && ok "bypassPermissions（免确认默认模式）" || bad "bypassPermissions" 'jq ".permissions.defaultMode=\"bypassPermissions\"" ~/.claude/settings.json'
# bypass 警告接受：仅便利项（免一次开机确认弹窗），缺失不影响功能，故降级为不计 fail 的中性提示。
# 修复用会话外写法（临时文件+原子 mv）——CC 会话中主进程持续写 ~/.claude.json，直接 jq 会并发覆盖丢数据。
if claudejson_true "bypassPermissionsModeAccepted"; then
  ok "bypass 警告已接受（免开机确认）"
else
  printf "  ${c_y}○${c_0} %-30s ${c_d}(便利项,缺=启动多点一次确认) → 退出 CC 会话后执行: jq '.bypassPermissionsModeAccepted=true' ~/.claude.json > /tmp/cj.\$\$ && mv /tmp/cj.\$\$ ~/.claude.json${c_0}\n" "bypass 警告接受"
  warn=$((warn+1))
fi
dir_trusted "$HOME"                && ok "~ 目录已信任（免文件夹信任弹窗）"    || bad "~ 目录信任" "jq '.projects[\"$HOME\"].hasTrustDialogAccepted=true' ~/.claude.json"
perm_allows "codegraph"            && ok "codegraph 只读工具白名单（permissions.allow）" || bad "codegraph 白名单" '把 "mcp__codegraph__*" 加进 ~/.claude/settings.json 的 permissions.allow'
env_is "DISABLE_AUTOUPDATER" "1"   && ok "自动更新已关闭（env.DISABLE_AUTOUPDATER）"    || bad "关闭自动更新" "jq '.env.DISABLE_AUTOUPDATER=\"1\"' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json"
if codex_auth_has_key; then
  codex_key_injector_installed       && ok "Codex 启动自动注入 OPENAI_API_KEY"            || bad "Codex API key 启动注入" "bash \"$SCRIPT_DIR/install-codex-key-injector.sh\""
else
  ok "Codex API key 启动注入（auth.json 无 key，无需配置）"
fi
[ -f "$HOME/.claude/CLAUDE.md" ]   && ok "全局 ~/.claude/CLAUDE.md"          || bad "全局 CLAUDE.md" "创建 ~/.claude/CLAUDE.md（全局规范）"
claudemd_has_chinese               && ok "全局规范含「始终中文回复」"          || bad "中文回复规范" $'printf \'\\n- **始终使用中文回复**（简体中文）。无论用户用什么语言提问、上下文/工具输出是什么语言，回复正文一律中文。\\n\' >> ~/.claude/CLAUDE.md'
claudemd_has_shortlink             && ok "全局规范含「代码位置用可点短链」"    || bad "代码短链规范" $'printf \'\\n- **引用代码位置一律用 markdown 可点短链**：IDEA 插件里裸文件名点不动会报 Cannot open file，须写成 [短名:行](绝对路径:行)。\\n\' >> ~/.claude/CLAUDE.md'
claudemd_has_compact               && ok "全局规范含「压缩取舍规则」"          || bad "压缩取舍规范" $'printf \'\\n## 上下文压缩（compact）取舍规则\\n做上下文压缩/生成摘要时，保留决策和状态，丢掉噪音：必留①架构决策及理由②改过的文件及改动③阻塞报错④进行中的工作与下一步⑤验证状态⑥失败过的方案及原因⑦待办与回滚；可丢冗长工具输出(留结论)、无关探索、死胡同中间步骤、已入 git 的文件内容。\\n\' >> ~/.claude/CLAUDE.md'
claudemd_has_proxy                 && ok "全局规范含「外网操作代理兜底」"      || bad "代理兜底规范" $'printf \'\\n## 外网操作走代理兜底（连不通或慢得反常就切代理）\\n**触发信号**：任何境外资源访问（GitHub/raw.githubusercontent/googleapis 等域、brew bottle、npm/pip/cargo 下载、kaggle 上传下载、curl 探测、WebFetch）出现①TLS 握手后被 RST／连接超时／SSL 报错，或②下载速率慢得反常（几 KB/s、卡住不动）——两者任一都视作被墙干扰，别归因于「网络就是慢」在直连路径反复重试。\\n**先探到可用代理，端口和协议都别写死**（因代理软件/机器而异）：优先复用已设的 $https_proxy/$http_proxy/$all_proxy；没有则依次探常见本地端口、每个端口 http 与 socks5h 都试，取第一个通的（含 scheme）——`for p in 7890 7897 10809 1087 7891 10808 1080; do for s in http socks5h; do curl -fsm2 -x $s://127.0.0.1:$p https://www.gstatic.com/generate_204 >/dev/null 2>&1 && { echo $s://127.0.0.1:$p; break 2; }; done; done`（7890=clash/mihomo 混合口、7897=clash verge rev、10809/10808=v2rayN http/socks、7891=clash socks、1080/1087=ss 等；http 混合口优先命中，socks 口兜底）。都不通说明没开代理，如实告知用户别硬试。\\n**切法按工具选**（下文 $PROXY=探到的地址，形如 http://127.0.0.1:7890 或 socks5h://127.0.0.1:7891，curl/git/环境变量三种都认这两种 scheme）：`curl` 加 `-x $PROXY`；`git` 加 `-c http.proxy=$PROXY`；`brew`/`npm`/`pip`/`kaggle`/`gh` 等吃环境变量的用 `https_proxy=$PROXY http_proxy=$PROXY <命令>`；`WebFetch`/`ctx_fetch`/`Playwright` 无法传代理就直接弃用、改用 `curl -x` 或 `git -c http.proxy` 完成同样抓取。\\n**为什么**：Node 的 fetch/undici（WebFetch 等工具底层）默认不认系统代理与 HTTP_PROXY 环境变量，所以「系统装了代理」不等于「工具会走代理」，必须显式把代理传给每条命令；国内裸直连 GitHub 等域常被 GFW 干扰、成功率很低，走本地代理才稳。**优先命令级/环境变量级代理、不强依赖 TUN 或系统全局代理**——命令级更精准、零系统改动、可随时回退，也不影响其它进程。\\n\' >> ~/.claude/CLAUDE.md'
claudemd_has_parallel_agents       && ok "全局规范含「多 Agent 并行执行」"      || bad "多 Agent 并行规范" $'printf \'\\n## 多 Agent 并行执行（默认并行，能加速就上）\\n\\n### 🚨 铁律：收到任务立即判断能否并行，能并行就立即启动多 Agent，别等用户提醒\\n\\n**自动触发检查（每个任务的第一步）：**\\n\\n1. **数量信号** — 任务涉及 ≥2 个独立对象（文件/模块/功能/站点/问题）？\\n   - ✅ 是 → 继续检查\\n   - ❌ 否 → 串行执行\\n\\n2. **依赖检查** — 这些对象之间有先后依赖吗？\\n   - ✅ 无依赖或部分无依赖 → 并行执行（有依赖的串起来）\\n   - ❌ 强依赖链条 → 串行执行\\n\\n3. **关键词触发（自动识别）** — 任务描述出现这些词立即并行：\\n   - **数量词**：「每个」「所有」「批量」「一批」「分别」「逐个」「多个」\\n   - **具体数字**：「9 个功能」「5 个模块」「3 个文件」\\n   - **重复动作**：「同一套」「相同的」「类似的」「重复」\\n   - **范围词**：「全部」「整个」「所有的」\\n\\n**判定结果：满足 1+2 或出现任一关键词 → 立即启动多 Agent 并行，不问用户**\\n\\n---\\n\\n### 典型并行场景（见到就上）\\n\\n1. **批量 CRUD** — N 个功能/模块的 VO + Controller + Service + Vue（每个一个 Agent）\\n2. **多文件读/改** — 要读/改一批文件、跑一批测试、查一批独立问题（每个文件一个 Agent）\\n3. **大范围调研** — 跨多个子系统/模块摸底（每个子系统一个 Agent）\\n4. **多视角分析** — 多方案对比、交叉验证、对抗式复核（每个视角一个 Agent）\\n5. **迁移/审计** — 批量整改、每个站点/每个组件（每个对象一个 Agent）\\n\\n**核心原则：凡是「同一动作重复施加到 N 个独立对象」就立即扇出，N≥2 就值得并行**\\n\\n---\\n\\n### 怎么做\\n\\n- **立即启动** — 一条消息里同时发多个 Agent 调用（独立任务并发跑，别一个个等）\\n- **任务模板** — 给每个 Agent 相同的任务模板（如「实现 XX 功能的 VO+Controller+Service+Vue」）\\n- **结论汇总** — 主线程只收集各 Agent 的结论，不吞原始文件内容\\n\\n---\\n\\n### 为什么这样做\\n\\n- **速度** — 串行 3 小时 vs 并行 30 分钟，加速比可达 5-10x\\n- **上下文** — 子代理各自独立上下文，主线程不会被大量文件内容挤爆\\n- **用户体验** — 用户等 30 分钟比等 3 小时爽得多\\n\\n---\\n\\n### 唯一例外（才串行）\\n\\n- **单个小任务** — 改一个函数、查一个已知文件、写一个脚本 → 直接自己干\\n- **强依赖链** — A 必须先完成才能开始 B，B 必须完成才能开始 C → 串行或部分并行\\n\\n**记住：默认并行，能加速就上，别等用户提醒！**\\n\' >> ~/.claude/CLAUDE.md'
# CodeGraph 自动初始化规范：条件必需——仅当 codegraph CLI 已装时才要求（装了却不自动初始化 = 退回慢速搜索）。
if has_cmd codegraph; then
  claudemd_has_codegraph_auto_init && ok "全局规范含「CodeGraph 自动初始化」" || bad "CodeGraph 自动初始化规范" $'printf \'\\n## CodeGraph 自动初始化\\n\\n进入新项目时，若发现项目根目录（通过 git 仓库判断或当前工作目录）下没有 `.codegraph/` 目录，自动执行 `codegraph init` 建立代码知识图谱索引。好处：\\n- 从一开始就能用 `codegraph_explore` MCP 工具或 `codegraph explore "<query>"` shell 命令，一次返回相关符号的完整源码 + 调用链\\n- 避免退回到低效的 grep + Read 循环\\n- 动态派发（接口实现、虚函数）的调用路径 grep 跟不动，CodeGraph 能追踪\\n\\n**什么时候建**：识别到这是一个代码项目（有 package.json / pom.xml / Cargo.toml / go.mod 等或明显的源码目录结构）且没有 `.codegraph/` 时，立即初始化。对于非代码目录（纯文档 / 配置仓库 / 个人笔记），跳过。\\n\\n**怎么建**：在项目根目录运行 `codegraph init`（会自动识别语言、扫描源码、建立索引）。索引进 `.codegraph/` 目录（已在 .gitignore 模板中，不入版本控制）。对于大型仓库（10 万+ 行），首次索引可能需要几秒到几十秒；增量更新很快。\\n\\n**注意事项**：\\n- 初始化前先确认是在项目根目录（git 根目录或主 build 文件所在目录），不要在子目录建索引\\n- 如果项目已有 `.codegraph/` 但索引陈旧（代码大改过），用 `codegraph update` 增量更新或 `codegraph init --force` 重建\\n- 非代码项目不要强制建索引（浪费时间且无收益）\\n\' >> ~/.claude/CLAUDE.md'
else
  ok "CodeGraph 自动初始化规范（codegraph 未装，无需配置）"
fi
# context7 调用场景规范：条件必需——仅当 context7 插件已装时才要求（装了不告诉 CC 何时查文档 = 仍可能凭旧记忆回答）。
if plugin_installed context7; then
  claudemd_has_context7           && ok "全局规范含「context7 官方文档优先」" || bad "context7 调用规范" $'printf \'\\n## 库/框架/SDK/API 用法优先查 context7\\n涉及库、框架、SDK、API、CLI 或云服务的用法、配置、版本迁移、报错排查、接入步骤时，优先用 context7 查询当前官方文档与示例；没有匹配文档或 context7 不可用时再回退内置知识或网页搜索。\\n\' >> ~/.claude/CLAUDE.md'
else
  ok "context7 调用规范（插件未装，无需配置）"
fi
# anysearch 调用场景规范：条件必需——仅当 anysearch skill 已装时才要求（装了不告诉 CC 何时调 = 白装）；未装则无需配置。
if skill_installed anysearch; then
  claudemd_has_anysearch           && ok "全局规范含「anysearch 联网搜索优先」" || bad "anysearch 调用规范" $'printf \'\\n## 联网搜索优先走 anysearch\\n需要联网检索时优先用 anysearch skill（已装于 ~/.claude/skills/anysearch），覆盖：①查信息/新闻/文档/当前数据 ②事实核查 ③读网页正文（超出摘要）④垂直领域查询（股票 Stock:/漏洞 CVE:/论文 DOI: 等带标识符）⑤多意图并行搜索。anysearch 不可用（无 key/超配额/服务错误/断网）时告知用户并可回退内置 WebSearch/WebFetch。\\n\' >> ~/.claude/CLAUDE.md'
else
  ok "anysearch 调用规范（skill 未装，无需配置）"
fi
# agentmemory 使用规范：必需——agentmemory 是必装 MCP，必须告诉 CC 自动工作机制与主动调用场景。
claudemd_has_agentmemory           && ok "全局规范含「agentmemory 持久化记忆」" || bad "agentmemory 使用规范" "bash \"$SCRIPT_DIR/install-agentmemory.sh\"（会自动追加规范到 CLAUDE.md）"
[ -d "$HOME/.claude/projects" ]    && ok "项目 memory 目录"                   || opt "项目 memory"     "~/.claude/projects/<项目>/memory/ 跨会话记忆"

# ---------- 7. MCP 连接健康（仅 --health） ----------
if [ "$HEALTH" -eq 1 ]; then
  sec "MCP 连接健康（--health 实连检查）"
  MCP_HEALTH="$(claude mcp list 2>/dev/null || echo '')"
  # 核心 MCP：<名字正则> <显示名>
  mcp_healthy '^codegraph:'           && ok "codegraph 已连接"           || bad "codegraph 未连"           "codegraph serve --mcp 起不来，检查 codegraph install / 重启 CC"
  mcp_healthy '^lighthouse-mcp:'      && ok "lighthouse-mcp 已连接"      || bad "lighthouse-mcp 未连"      "检查 dist/index.js 路径，重跑 claude mcp add"
  mcp_healthy '^agentmemory:'         && ok "agentmemory 已连接"         || bad "agentmemory 未连"         "npx @agentmemory/agentmemory 起不来，检查网络或重启 CC"
  mcp_healthy ':playwright:'          && ok "playwright 已连接（插件 MCP）" || bad "playwright 未连"        "npx @playwright/mcp@latest 起不来；先装浏览器 npx playwright install chromium"
else
  printf "\n${c_d}（跳过 MCP 连接健康检查；加 --health 参数可实连核对 codegraph/lighthouse/agentmemory/playwright）${c_0}\n"
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
