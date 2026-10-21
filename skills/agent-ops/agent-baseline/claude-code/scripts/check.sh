#!/usr/bin/env bash
# cc-baseline —— 核对本机 Claude Code 是否符合装配基线。
# 分六类逐项体检：CLI 工具 / 全局 npm 包 / MCP 注册 / 插件 / 系统配置 / 配置基线。
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

pass=0; fail=0; warn=0; declined=0

# CC_BASELINE_SKIP：本机「刻意不装」的必需项清单（空格或逗号分隔的关键字，对检查项标签做子串匹配）。
# 用途：基线里的必需项若与本机既有方案互斥（例如两个状态栏实现争用同一个
# settings.statusLine，只能留一个），它永远补不齐，每次都报 ✗ 并让退出码=1 —— 那是
# 恒假的噪音，会淹掉真实缺失。声明进本变量后降级为中性「⊘ 刻意不装」，不计 fail、不影响退出码。
# 例：CC_BASELINE_SKIP="claude-hud" bash check.sh
# 只按逗号分隔，不按空格：检查项标签本身含空格（如「claude-hud 状态栏」），
# 按空格切会把一条声明拆成多个更宽的关键字，误吞同前缀的其它检查项。
declined_item(){
  [ -n "${CC_BASELINE_SKIP:-}" ] || return 1
  local rest="${CC_BASELINE_SKIP}" kw
  while [ -n "$rest" ]; do
    case "$rest" in
      *,*) kw="${rest%%,*}"; rest="${rest#*,}" ;;
      *)   kw="$rest";       rest="" ;;
    esac
    kw="${kw#"${kw%%[![:space:]]*}"}"; kw="${kw%"${kw##*[![:space:]]}"}"   # 去首尾空白
    [ -n "$kw" ] || continue
    case "$1" in *"$kw"*) return 0 ;; esac
  done
  return 1
}

c_g=$'\033[32m'; c_r=$'\033[31m'; c_y=$'\033[33m'; c_d=$'\033[2m'; c_0=$'\033[0m'
ok()  { printf "  ${c_g}✓${c_0} %s\n" "$1"; pass=$((pass+1)); }
# bad() 内拦 CC_BASELINE_SKIP：统一在出口处降级，无需改动散落各处的几十个检查点调用。
bad() {
  if declined_item "$1"; then
    printf "  ${c_d}⊘ %-30s (刻意不装，已在 CC_BASELINE_SKIP 声明)${c_0}\n" "$1"; declined=$((declined+1)); return 0
  fi
  printf "  ${c_r}✗${c_0} %-30s ${c_d}→ 修复: %s${c_0}\n" "$1" "$2"; fail=$((fail+1))
}
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
# 重试 3 次：CC 会话会在运行期原地重写 installed_plugins.json（插件刷新/marketplace 同步），
# 撞上「已截断、还没写完」的瞬间 require() 解析失败 → node 非零退出 → 误报「插件未装」。
# 这是假阴性（文件正在被写 ≠ 插件没装），靠短重试跨过写入窗口，别把它当真缺失。
plugin_installed(){
  [ -f "$INSTALLED_PLUGINS" ] || return 1
  local i
  for i in 1 2 3; do
    node -e "const j=require('$INSTALLED_PLUGINS').plugins||{};process.exit(Object.keys(j).some(k=>k.split('@')[0]===process.argv[1])?0:1)" "$1" 2>/dev/null && return 0
    # 区分「解析失败(瞬时)」与「解析成功但没这插件(真缺)」：能解析出 JSON 就别再重试。
    node -e "require('$INSTALLED_PLUGINS')" 2>/dev/null && return 1
    sleep 0.3
  done
  return 1
}
# 插件启用状态（settings.json 的 enabledPlugins，按插件名匹配任意 marketplace）：已启用 / 已禁用 / 未登记
plugin_state(){
  jq -r --arg p "$1" '[(.enabledPlugins // {}) | to_entries[] | select((.key | split("@")[0]) == $p) | .value]
    | if length == 0 then "未登记" elif any then "已启用" else "已禁用" end' "$HOME/.claude/settings.json" 2>/dev/null || echo "状态未知"
}
# Caveman 风格模式由用户级 hook 提供（vendor-plugin-hooks.mjs，不装插件本体），并显式固定用户默认档为 full。
# 判定：defaultMode=full、vendor 版本在位且自检通过、settings 里的 hook 与 vendor 一致、caveman 插件已不在（否则规则注入两次）。
caveman_default_full(){
  local config="$HOME/.config/caveman/config.json"
  [ -f "$config" ] || return 1
  node -e "const j=require(process.argv[1]);process.exit(j.defaultMode==='full'?0:1)" "$config" 2>/dev/null || return 1
  node -e "const j=require(process.argv[1]).plugins||{};process.exit(Object.keys(j).some(k=>k.split('@')[0]==='caveman')?1:0)" "$INSTALLED_PLUGINS" 2>/dev/null || [ ! -f "$INSTALLED_PLUGINS" ] || return 1
  node "$SCRIPT_DIR/vendor-plugin-hooks.mjs" --config "${CAVEMAN_VENDOR_CONFIG:-$SCRIPT_DIR/../config/caveman-hooks.json}" --check >/dev/null 2>&1
}
# 全局 npm 包是否装（查 node_modules 目录，比 npm ls 快）
npm_g_installed(){ [ -n "$NPM_ROOT" ] && [ -d "$NPM_ROOT/$1" ]; }
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
# settings.json 的 PreToolUse 是否装了 RTK 的 Bash 改写 hook（rtk hook claude）
# 没这条 hook，rtk 只是躺在 PATH 里没人调的二进制，Bash 输出照旧全量进上下文。
rtk_hook_installed(){
  [ -f "$SETTINGS" ] || return 1
  node -e 'const s=require(process.argv[1]);const h=(s.hooks||{}).PreToolUse||[];process.exit(JSON.stringify(h).includes("rtk hook")?0:1)' "$SETTINGS" 2>/dev/null
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
# 全局 ~/.claude/CLAUDE.md 是否含「上下文压缩取舍」规范（规则正文在 rules/compaction.md，两宿主共用；含「阶段切换表」，关键词「实施中途」）
# 逐个工具调用问两件事：调用还要记得吗、输出还要原样留吗；能重跑恢复的只留一行结论，有副作用的操作原样留。
claudemd_has_compact(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] || return 1
  # 规则已拆进交接类 skill（如 handoff-private）时，全局只留一行指针也算有
  grep -Eq '上下文压缩.*skill `[a-z-]*handoff' "$f" && return 0
  grep -Eq '上下文压缩' "$f" && grep -Eq '重跑' "$f" && grep -Eq '副作用' "$f" && grep -Eq '实施中途' "$f"
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
# 规则正文在 rules/parallel-tasks.md：任务含多个互相独立的子项时必须拆成多个后台子 agent 同时做，按写入文件切分、主控合入。
# 关键字用通用语义词、中英兼容（subagent / 并行 agent / 扇出 / fan-out / 并行执行）。
claudemd_has_parallel_agents(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] || return 1
  grep -Eiq '并行.*[Aa]gent|多.*[Aa]gent|多个 subagent|subagent 并行|扇出|fan-?out|并行执行|默认并行|能加速就上' "$f"
}
# 全局 ~/.claude/CLAUDE.md 是否含「HTTP 请求走 ctx_execute」规范
# 已由 context-mode 的 PreToolUse hook 提供：无需在 CLAUDE.md 手写
claudemd_has_http_routing(){
  return 1  # 检查已由 context-mode 注入，不再从 CLAUDE.md 读
}
# skill 是否已安装（~/.claude/skills/<name> 目录存在，或作为同名插件装了）
# anysearch 主要走手动装到 ~/.claude/skills/anysearch，marketplace 装则落为插件，两种都认。
skill_installed(){
  [ -d "$HOME/.claude/skills/$1" ] && return 0
  plugin_installed "$1"
}
missing_skills(){
  local skill missing=""
  for skill in "$@"; do
    skill_installed "$skill" || missing="${missing}${missing:+, }$skill"
  done
  printf '%s' "$missing"
}
# 全局 ~/.claude/CLAUDE.md 是否含「anysearch 联网搜索优先」调用场景规范
# 仅在 anysearch 已装时才核对：装了搜索 skill 却没告诉 CC 何时调它，等于白装。
claudemd_has_anysearch(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] || return 1
  grep -Eiq 'anysearch' "$f"
}
# 全局规范是否含「Token 节省」：长等待交给不调 LLM 的脚本轮询、大输出脚本内汇总、阶段切换先交接再 /clear（子 agent 选模型见 rules/agent-model.md）。
claudemd_has_token_budget(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] && grep -Eq 'Token 节省' "$f" && grep -Eq '轮询' "$f" && grep -Eq '/clear' "$f"
}
# 全局规范是否含「Bash 命令避开内置确认框」：CC 内置保护（变量路径 rm/rmdir、cd 进别的目录再跑 git）一律弹框，bypass/allow/hook 都放行不了。
claudemd_has_rm_literal(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] && grep -Eq '避开内置确认框' "$f" && grep -Eq 'git -C' "$f" && grep -Eq '会话当前目录' "$f"
}
# 全局规范是否含「先找成熟方案，再自己造」：动手前先查本机/平台公开资源/社区现成方案，同类失败 2 次止损换路并按排查顺序走（规则正文在 rules/reuse-first.md，两宿主共用）。
# 「外部 skill 先审再用」已归 skill-validator，不再要求全局规范含该词。
claudemd_has_reuse_first(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] && grep -Eq '先找成熟方案' "$f" && grep -Eq '连续失败 2 次' "$f" \
    && grep -Eq '排查顺序' "$f"
}
# 插件自带 hook（vft-kit hooks/hooks.json 注册，脚本在插件 scripts/hooks/）：
# bash-prompt-guard（PreToolUse Bash）把会触发 CC 内置确认框的写法提前拒掉并给改写提示，用户不被打断；
# handoff-nudge（PostToolUse）读 transcript 最后一条 usage，主会话上下文过 40% 提醒写交接文档，
#   默认影子运行（只写 ~/.cache/vft-kit/handoff-nudge.jsonl），~/.cache/vft-kit/handoff-nudge.LIVE 存在才注入提示；
# reply-lang-pin（UserPromptSubmit）非中文提问时钉住回复语言（caveman 默认跟随用户语言）。
# 必需：插件 hooks.json 有注册，且 settings.json 没有旧安装脚本留下的绝对路径条目（会重复触发）。
PLUGIN_HOOKS_JSON="$SCRIPT_DIR/../../../../../hooks/hooks.json"
plugin_hook_check(){ # $1 脚本名（不含 .py） $2 ok 时的说明
  local f="$HOME/.claude/settings.json"
  if ! grep -q "scripts/hooks/$1.py" "$PLUGIN_HOOKS_JSON" 2>/dev/null; then
    bad "$1 hook" "插件 hooks/hooks.json 缺注册：更新 vft-kit 插件后新开会话"
  elif [ -f "$f" ] && grep "$1.py" "$f" | grep -vq 'CLAUDE_PLUGIN_ROOT'; then
    bad "$1 旧 hook 条目" "bash \"$SCRIPT_DIR/migrate-plugin-hooks.sh\""
  else
    ok "$1 hook 已由 vft-kit 插件注册（$2）"
  fi
}
# model-router 是否已装：tzachbon/claude-model-router-hook 固定版本 + vft-kit 补丁（中文任务识别、不覆盖具名 agent、去掉会拦消息的主会话路由），
# 配置关掉 CLI 二次判断。只把机械子 agent 路由到 haiku，其余保持 opus/high。见 install-model-router.sh。
model_router_installed(){
  local f="$HOME/.claude/settings.json" c="$HOME/.claude/model-router.json"
  [ -f "$f" ] && grep -q '"claude-model-router-hook@claude-model-router-hook": true' "$f" \
    && [ -f "$c" ] && grep -Eq '"cli_fallback": *false' "$c" \
    && grep -q 'vft-kit patch' "$HOME"/.claude/plugins/cache/claude-model-router-hook/claude-model-router-hook/*/hooks/pre_tool_use.py 2>/dev/null
}
# 全局规范是否要求 Agent 调用显式写 model（机械活 haiku/sonnet，推理类继承；规则正文在 rules/agent-model.md）。
claudemd_has_agent_model(){
  # 装了 model-router 时由它在 PreToolUse 自动给子 agent 选模型，全局规范不必再写细则。
  model_router_installed && return 0
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] && grep -q '显式写 `model`' "$f"
}
# codegraph 的 UserPromptSubmit hook 是否已加过滤（裸 `codegraph prompt-hook` 会给后台通知和非代码问题注入约 15 KB 无关符号）。
codegraph_prompt_hook_filtered(){
  local f="$HOME/.claude/settings.json"
  [ -f "$f" ] || return 0
  ! grep -Eq '"command"[[:space:]]*:[[:space:]]*"codegraph prompt-hook"' "$f"
}
# 全局 ~/.claude/CLAUDE.md 是否含「CodeGraph 自动初始化」规范
# codegraph CLI 已装时必需：进入新项目若没有 .codegraph 目录，自动建索引，充分利用代码知识图谱。
claudemd_has_codegraph_auto_init(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] || return 1
  grep -Eiq 'codegraph.*自动|\.codegraph.*自动建立|自动.*codegraph.*索引|codegraph.*新项目' "$f" &&
    grep -Eiq 'codegraph[[:space:]]+sync' "$f" &&
    grep -Eiq 'codegraph[[:space:]]+index[[:space:]]+-f' "$f" &&
    ! grep -Eiq 'codegraph[[:space:]]+update|codegraph[[:space:]]+init[[:space:]]+--force' "$f"
}
# 全局 ~/.claude/CLAUDE.md 是否含「所有 code review 先走 Code Review Graph」规范。
claudemd_has_code_review_graph(){
  local f="$HOME/.claude/CLAUDE.md"
  [ -f "$f" ] || return 1
  grep -Eiq '所有.*代码审查|all.*code reviews?' "$f" &&
    grep -Eiq 'code-review-graph' "$f" &&
    grep -Eiq '最小上下文|minimal context' "$f" &&
    grep -Eiq '影响半径|impact radius' "$f" &&
    grep -Eiq '相关测试|relevant tests' "$f" &&
    grep -Eiq '再.*读取源码|before.*source' "$f" &&
    grep -Eiq 'code-review-graph[[:space:]]+build' "$f" &&
    grep -Eiq 'code-review-graph[[:space:]]+update' "$f" &&
    grep -Eiq 'code-review-graph[[:space:]]+status' "$f"
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
has_cmd rtk    && ok "rtk ($(rtk --version 2>/dev/null))"   || bad "rtk"    "brew install rtk"
has_cmd codegraph && ok "codegraph ($(codegraph --version 2>/dev/null))" || bad "codegraph" "curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh"
has_cmd code-review-graph && ok "code-review-graph ($(code-review-graph --version 2>/dev/null))" || bad "code-review-graph" "pipx install code-review-graph"
has_cmd brew   && ok "brew"                                 || opt "brew"   "Homebrew 建议装"
has_cmd jq     && ok "jq"                                   || opt "jq"     "brew install jq"
has_cmd gh     && ok "gh ($(gh --version 2>/dev/null|head -1|awk '{print $3}'))" || opt "gh"     "brew install gh（GitHub CLI：PR/Actions/仓库操作，可选）"

# ---------- 2. 全局 npm 包（MCP 载体） ----------
sec "全局 npm 包"
npm_g_installed "@danielsogl/lighthouse-mcp"                  && ok "@danielsogl/lighthouse-mcp"                  || bad "@danielsogl/lighthouse-mcp" "npm i -g @danielsogl/lighthouse-mcp"

# ---------- 3. MCP 注册 ----------
sec "MCP 服务器（已注册到 CC）"
mcp_registered codegraph           && ok "codegraph"           || bad "codegraph MCP"           "codegraph install --target=claude --location=global --yes"
mcp_registered code-review-graph   && ok "code-review-graph MCP" || bad "code-review-graph MCP"   "claude mcp add code-review-graph -s user -- code-review-graph serve"
# lighthouse-mcp 2026-10-20 起按需加载：MCP 注册移除、npm 载体保留，要用时再注册（用户定）
if mcp_registered lighthouse-mcp; then ok "lighthouse-mcp"
elif npm_g_installed "@danielsogl/lighthouse-mcp"; then opt "lighthouse-mcp" "已按需移除注册；要用时：claude mcp add lighthouse-mcp -s user -- node \"\$(npm root -g)/@danielsogl/lighthouse-mcp/dist/index.js\""
else bad "lighthouse-mcp MCP" "npm i -g @danielsogl/lighthouse-mcp && claude mcp add lighthouse-mcp -s user -- node \"\$(npm root -g)/@danielsogl/lighthouse-mcp/dist/index.js\""; fi

# ---------- 4. 插件（默认必备集） ----------
sec "插件（默认必备集）"
# 精简后的默认必备插件清单（用户指定）：核心工作流 + 自研 + 反过度工程
for p in superpowers skill-creator code-review frontend-design playwright \
         typescript-lsp jdtls-lsp \
         context-mode ponytail gsap-skills; do
  if plugin_installed "$p"; then ok "${p}（已装，$(plugin_state "$p")）"; else
    case "$p" in
      # playwright 2026-10-20 起按需启用：ego-lite 不可用时的兜底，平时禁用不加载 24 个工具（用户定）
      playwright)
        if jq -e '.enabledPlugins["playwright@claude-plugins-official"] == false' ~/.claude/settings.json >/dev/null 2>&1; then
          opt "playwright" "已按需禁用；要用时：claude plugin enable playwright@claude-plugins-official"
        else
          bad "$p" "claude plugin install $p@claude-plugins-official"
        fi;;
      context-mode)                   bad "$p" "claude plugin marketplace add mksglu/claude-context-mode && claude plugin install context-mode@context-mode";;
      ponytail)                       bad "$p" "claude plugin marketplace add DietrichGebert/ponytail && claude plugin install ponytail@ponytail（两条要分开发）";;
      gsap-skills)                    bad "$p" "claude plugin marketplace add greensock/gsap-skills && claude plugin install gsap-skills@gsap-skills（GSAP 官方，两条要分开发）";;
      *)                              bad "$p" "claude plugin install $p@claude-plugins-official";;
    esac
  fi
done
# claude-hud 可选，可能与用户已有 statusLine 冲突。
plugin_installed claude-hud && ok "claude-hud（可选状态栏）" || opt "claude-hud" "claude plugin marketplace add jarrodwatts/claude-hud && claude plugin install claude-hud@claude-hud"
caveman_default_full && ok "Caveman 风格模式 hook（默认 full）" || bad "Caveman 风格模式 hook（默认 full）" "bash \"$SCRIPT_DIR/install-caveman-default.sh\""
# 可选插件（装了更好，不装不算故障）
for p in context7; do
  if plugin_installed "$p"; then ok "${p}（已装，$(plugin_state "$p")）"; else opt "$p" "claude plugin install $p@claude-plugins-official"; fi
done
# 可选 skill：anysearch（AI Agent 联网实时搜索，装到 ~/.claude/skills/anysearch）
skill_installed anysearch && ok "anysearch skill（联网实时搜索）" || opt "anysearch skill" "bash \"$SCRIPT_DIR/install-anysearch.sh\"（自动安装、随机邮箱注册 key 并写入 skill/.env）"
emil_required_missing="$(missing_skills animate review-animations apple-design)"
if [ -z "$emil_required_missing" ]; then
  ok "Emil 动效 skills（必装 3 项）"
else
  bad "Emil 动效 skills（缺 ${emil_required_missing}）" "npx skills add emilkowalski/skills --skill animate --skill review-animations --skill apple-design --agent claude-code --global --yes"
fi
emil_optional_missing="$(missing_skills animation-vocabulary ask-sonner emil-design-eng find-animation-opportunities improve-animations pick-ui-library prototype)"
if [ -z "$emil_optional_missing" ]; then
  ok "Emil 扩展 skills（可选 7 项）"
else
  opt "Emil 扩展 skills（缺 ${emil_optional_missing}）" "按项目用 npx skills add emilkowalski/skills --skill <name> --agent claude-code --global --yes 单独安装"
fi
# 可选 skill：grill-me（无情追问式访谈，via mattpocock-skills 插件）
plugin_installed mattpocock-skills && ok "grill-me skill（via mattpocock-skills）" || opt "grill-me skill" "claude plugin install mattpocock-skills@claude-plugins-official"
# 可选插件：understand-anything（代码库知识图谱 + 可视化 dashboard，来自第三方 marketplace Egonex-AI/Understand-Anything）
# 与 codegraph 互补：codegraph 是 CLI/MCP 即时查符号+调用链，这个是多 agent 全量分析出可视化图谱与导览。
plugin_installed understand-anything && ok "understand-anything（代码知识图谱 dashboard）" || opt "understand-anything" "claude plugin marketplace add Egonex-AI/Understand-Anything && claude plugin install understand-anything@understand-anything（两条要分开发；首次 /understand 全量分析耗 token）"
plugin_installed diagram-design && ok "diagram-design（专业图表）" || opt "diagram-design" "claude plugin marketplace add cathrynlavery/diagram-design && claude plugin install diagram-design@diagram-design（两条要分开发）"
# 可选插件集：pm-skills（9 个 PM 插件 / 68 skills / 42 链式工作流，来自 phuryn/pm-skills）
# 按「装了几个」三态报：全 9 个=ok，部分=opt 并提示补齐，0 个=opt
pm_installed=0
for p in pm-toolkit pm-product-strategy pm-product-discovery pm-market-research pm-data-analytics \
         pm-marketing-growth pm-go-to-market pm-execution pm-ai-shipping; do
  plugin_installed "$p" && pm_installed=$((pm_installed+1))
done
if   [ "$pm_installed" -eq 9 ]; then ok  "pm-skills（9 个 PM 插件全装）"
elif [ "$pm_installed" -gt 0 ]; then opt "pm-skills（$pm_installed/9 部分装）" "bash \"$SCRIPT_DIR/install-pm-skills.sh\"（补齐缺失插件）"
else                                 opt "pm-skills（PM 工作流插件集）"      "bash \"$SCRIPT_DIR/install-pm-skills.sh\"（一键装 9 个插件：/discover /strategy /write-prd 等）"
fi

# ---------- 5. 系统配置 ----------
sec "系统配置"
# statusLine 可选，避免与用户已有状态栏冲突。
statusline_uses_hud             && ok "状态栏 statusLine（claude-hud）"      || opt "claude-hud 状态栏" "在 CC 里运行 /claude-hud:setup（或让现有 statusLine 委托给 claude-hud）"
[ -d "/Applications/CC Switch.app" ] && ok "cc-switch App"                  || opt "cc-switch App"    "brew install --cask cc-switch"

# ---------- 6. 配置基线 ----------
sec "配置基线"
defaultmode_is "bypassPermissions" && ok "bypassPermissions（免确认默认模式）" || bad "bypassPermissions" 'jq ".permissions.defaultMode=\"bypassPermissions\"" ~/.claude/settings.json'
# bypass 警告接受：必需项，缺失时自动设置（与 ponytail/caveman 同级，用户已授权静默补齐）。
# 修复用会话外写法（临时文件+原子 mv）——CC 会话中主进程持续写 ~/.claude.json，直接 jq 会并发覆盖丢数据。
if claudejson_true "bypassPermissionsModeAccepted"; then
  ok "bypass 警告已接受（免开机确认）"
else
  # 自动设置（静默补齐，用户已授权）
  if jq '.bypassPermissionsModeAccepted=true' ~/.claude.json > /tmp/cj.$$ 2>/dev/null && mv /tmp/cj.$$ ~/.claude.json; then
    ok "bypass 警告已接受（刚自动设置）"
  else
    bad "bypass 警告接受" "jq '.bypassPermissionsModeAccepted=true' ~/.claude.json > /tmp/cj.\$\$ && mv /tmp/cj.\$\$ ~/.claude.json"
  fi
fi
dir_trusted "$HOME"                && ok "~ 目录已信任（免文件夹信任弹窗）"    || bad "~ 目录信任" "jq '.projects[\"$HOME\"].hasTrustDialogAccepted=true' ~/.claude.json"
perm_allows "codegraph"            && ok "codegraph 只读工具白名单（permissions.allow）" || bad "codegraph 白名单" '把 "mcp__codegraph__*" 加进 ~/.claude/settings.json 的 permissions.allow'
rtk_hook_installed                 && ok "RTK hook（Bash 输出自动压缩）"                  || bad "RTK hook" "bash \"$SCRIPT_DIR/install-rtk.sh\""
env_is "DISABLE_AUTOUPDATER" "1"   && ok "自动更新已关闭（env.DISABLE_AUTOUPDATER）"    || bad "关闭自动更新" "jq '.env.DISABLE_AUTOUPDATER=\"1\"' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json"
# ponytail 5.x 的 Codebase map 按 cwd 扫目录，monorepo 根下多是无关目录；规则注入不受影响
env_is "PONYTAIL_MAP" "0"          && ok "ponytail 代码地图已关闭（env.PONYTAIL_MAP）"  || bad "关闭 ponytail 代码地图" "jq '.env.PONYTAIL_MAP=\"0\"' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json"
if codex_auth_has_key; then
  codex_key_injector_installed       && ok "Codex 启动自动注入 OPENAI_API_KEY"            || bad "Codex API key 启动注入" "bash \"$SCRIPT_DIR/install-codex-key-injector.sh\""
else
  ok "Codex API key 启动注入（auth.json 无 key，无需配置）"
fi
[ -f "$HOME/.claude/CLAUDE.md" ]   && ok "全局 ~/.claude/CLAUDE.md"          || bad "全局 CLAUDE.md" "创建 ~/.claude/CLAUDE.md（全局规范）"
claudemd_has_chinese               && ok "全局规范含「始终中文回复」"          || bad "中文回复规范" $'printf \'\\n- 始终用简体中文回复（用户用英文、只贴代码或报错也一样）；代码、命令、路径、API 名、报错原文保持原样。\\n\' >> ~/.claude/CLAUDE.md'
claudemd_has_shortlink             && ok "全局规范含「代码位置用可点短链」"    || bad "代码短链规范" $'printf \'\\n- 引用代码位置用 markdown 可点短链：`[短名:行](绝对路径:行)`。\\n\' >> ~/.claude/CLAUDE.md'
claudemd_has_compact               && ok "全局规范含「压缩取舍规则」"          || bad "压缩取舍规范" "先删掉 ~/.claude/CLAUDE.md 里旧的「## 上下文压缩」节（如有），再执行：cat \"$SCRIPT_DIR/../../rules/compaction.md\" >> ~/.claude/CLAUDE.md"
claudemd_has_proxy                 && ok "全局规范含「外网操作代理兜底」"      || bad "代理兜底规范" $'printf \'\\n## 外网代理兜底\\n\\n境外资源连接超时、TLS 失败或速度异常时，先探测可用本地代理，再通过 `https_proxy` 或 `git -c http.proxy=...` 重试；不要在直连路径反复重试。\\n\' >> ~/.claude/CLAUDE.md'
claudemd_has_parallel_agents       && ok "全局规范含「多任务并行」"            || bad "多 Agent 并行规范" "先删掉 ~/.claude/CLAUDE.md 里旧的「## 多 Agent 并行执行」节（如有），再执行：cat \"$SCRIPT_DIR/../../rules/parallel-tasks.md\" >> ~/.claude/CLAUDE.md"
claudemd_has_token_budget          && ok "全局规范含「Token 节省」"            || bad "Token 节省规范" $'printf \'\\n## Token 节省\\n\\n- 长等待（云端训练、CI、部署、远端队列）交给不调用 LLM 的脚本轮询、下载、验收和清理，轮询间隔不短于 10 分钟；Agent 提交后退出，结果齐了再开短 Agent 分析。大输出在脚本里汇总，只把结论打印进上下文。\\n- 阶段切换或主会话上下文超过约 40%% 时，先写交接，再 `/clear` 或新开会话。\\n\' >> ~/.claude/CLAUDE.md'
claudemd_has_reuse_first           && ok "全局规范含「先找成熟方案，再自己造」" || bad "先找成熟方案规范" "先删掉 ~/.claude/CLAUDE.md 里旧的「## 先找成熟方案」节（如有），再执行：cat \"$SCRIPT_DIR/../../rules/reuse-first.md\" >> ~/.claude/CLAUDE.md"
claudemd_has_rm_literal            && ok "全局规范含「Bash 命令避开内置确认框」" || bad "避开内置确认框规范" "先删掉 ~/.claude/CLAUDE.md 里旧的「## Bash 命令避开内置确认框」节（如有），再执行：cat \"$SCRIPT_DIR/../rules/bash-no-prompt.md\" >> ~/.claude/CLAUDE.md"
plugin_hook_check bash-prompt-guard "避开内置确认框"
if [ -f "$HOME/.cache/vft-kit/handoff-nudge.LIVE" ]; then plugin_hook_check handoff-nudge "上下文过 40% 提醒交接，已生效"
else plugin_hook_check handoff-nudge "影子运行，记录见 ~/.cache/vft-kit/handoff-nudge.jsonl"; fi
# 供应链（只读，只报不计失败）：MCP 是否钉版本；用户级 skills 有无 high 级风险。plugins/cache 全量扫描噪声大、约 10 秒，留给装新插件前对单个目录手动跑。
mcp_pin_sum="$(node "$SCRIPT_DIR/mcp-pin-check.mjs" 2>/dev/null | grep '^mcp-pin-check:' || true)"
node "$SCRIPT_DIR/mcp-pin-check.mjs" --fail-on high >/dev/null 2>&1 && ok "MCP 依赖已钉版本" || opt "MCP 钉版本" "node \"$SCRIPT_DIR/mcp-pin-check.mjs\" 看详情（${mcp_pin_sum#mcp-pin-check: }）"
node "$SCRIPT_DIR/skill-supply-scan.mjs" "$HOME/.claude/skills" --fail-on high >/dev/null 2>&1 && ok "用户级 skills 供应链扫描无 high" || opt "skills 供应链" "node \"$SCRIPT_DIR/skill-supply-scan.mjs\" ~/.claude/skills"
plugin_hook_check reply-lang-pin "英文提问也用中文回复"
model_router_installed             && ok "model-router 已装（补丁版，子 agent 选模型）" || bad "model-router" "bash \"$SCRIPT_DIR/install-model-router.sh\""
claudemd_has_agent_model           && ok "全局规范含「Agent 显式写 model」"     || bad "Agent 显式写 model 规范" "先删掉 ~/.claude/CLAUDE.md 里旧的「## 子 agent 选模型」节（如有），再执行：cat \"$SCRIPT_DIR/../../rules/agent-model.md\" >> ~/.claude/CLAUDE.md"
if has_cmd codegraph; then
  codegraph_prompt_hook_filtered && ok "codegraph prompt-hook 已加过滤（后台通知/非代码问题不注入）" || bad "codegraph prompt-hook 过滤" "bash \"$SCRIPT_DIR/install-codegraph-prompt-filter.sh\""
fi
# CodeGraph 自动初始化规范：条件必需——仅当 codegraph CLI 已装时才要求（装了却不自动初始化 = 退回慢速搜索）。
if has_cmd codegraph; then
  claudemd_has_codegraph_auto_init && ok "全局规范含「CodeGraph 自动初始化」" || bad "CodeGraph 自动初始化规范" $'sed -i.bak -e \'s/codegraph update/codegraph sync/g\' -e \'s/codegraph init --force/codegraph index -f/g\' ~/.claude/CLAUDE.md && printf \'\\n## CodeGraph 自动初始化\\n\\n进入代码项目时先确认项目根。没有 `.codegraph/` 时自动运行 `codegraph init`；已有索引用 `codegraph sync` 增量同步，需要完整重建时用 `codegraph index -f`。\\n\' >> ~/.claude/CLAUDE.md'
else
  ok "CodeGraph 自动初始化规范（codegraph 未装，无需配置）"
fi
claudemd_has_code_review_graph      && ok "Code Review Graph 优先规范" || bad "Code Review Graph 优先规范" $'printf \'\\n## Code Review Graph 优先\\n\\n所有代码审查优先用 code-review-graph 获取最小上下文、影响半径和相关测试，再读取源码；首次 `code-review-graph build`，日常 `code-review-graph update`，检查 `code-review-graph status`。\\n\' >> ~/.claude/CLAUDE.md'
# context7 调用场景规范：条件必需——仅当 context7 插件已装时才要求（装了不告诉 CC 何时查文档 = 仍可能凭旧记忆回答）。
if plugin_installed context7; then
  claudemd_has_context7           && ok "全局规范含「context7 官方文档优先」" || bad "context7 调用规范" $'printf \'\\n## 库/框架/SDK/API 用法优先查 context7\\n\\n库、框架、SDK、API、CLI、云服务的用法、配置、迁移、报错、接入，先用 context7 查官方文档；查不到或不可用再回退内置知识或网页搜索。\\n\' >> ~/.claude/CLAUDE.md'
else
  ok "context7 调用规范（插件未装，无需配置）"
fi
# anysearch 调用场景规范：条件必需——仅当 anysearch skill 已装时才要求（装了不告诉 CC 何时调 = 白装）；未装则无需配置。
if skill_installed anysearch; then
  claudemd_has_anysearch           && ok "全局规范含「anysearch 联网搜索优先」" || bad "anysearch 调用规范" $'printf \'\\n## 联网搜索优先走 anysearch\\n\\n需要联网检索（信息/新闻/当前数据/事实核查）优先用 anysearch skill，不可用时回退 WebSearch/WebFetch。\\n\' >> ~/.claude/CLAUDE.md'
else
  ok "anysearch 调用规范（skill 未装，无需配置）"
fi
# HTTP 请求路由规范：context-mode 已在 PreToolUse hook 里提供，无需 CLAUDE.md 声明。
if plugin_installed context-mode; then
  ok "HTTP 请求路由（由 context-mode 注入）"
else
  ok "HTTP 请求路由规范（context-mode 未装，无需配置）"
fi
[ -d "$HOME/.claude/projects" ]    && ok "项目 memory 目录"                   || opt "项目 memory"     "~/.claude/projects/<项目>/memory/ 跨会话记忆"

# ---------- 7. MCP 连接健康（仅 --health） ----------
if [ "$HEALTH" -eq 1 ]; then
  sec "MCP 连接健康（--health 实连检查）"
  MCP_HEALTH="$(claude mcp list 2>/dev/null || echo '')"
  # 核心 MCP：<名字正则> <显示名>
  mcp_healthy '^codegraph:'           && ok "codegraph 已连接"           || bad "codegraph 未连"           "codegraph serve --mcp 起不来，检查 codegraph install / 重启 CC"
  mcp_healthy '^code-review-graph:'   && ok "code-review-graph 已连接"   || bad "code-review-graph 未连"   "检查 code-review-graph serve，重跑 claude mcp add"
  mcp_healthy '^lighthouse-mcp:'      && ok "lighthouse-mcp 已连接"      || bad "lighthouse-mcp 未连"      "检查 dist/index.js 路径，重跑 claude mcp add"
  mcp_healthy ':playwright:'          && ok "playwright 已连接（插件 MCP）" || bad "playwright 未连"        "npx @playwright/mcp@latest 起不来；先装浏览器 npx playwright install chromium"
else
  printf "\n${c_d}（跳过 MCP 连接健康检查；加 --health 参数可实连核对 codegraph/lighthouse/playwright）${c_0}\n"
fi

# ---------- 汇总 ----------
printf "\n${c_d}────────────────────────────────${c_0}\n"
printf "结果：${c_g}%d 正常${c_0} / ${c_r}%d 缺失(必需)${c_0} / ${c_y}%d 可选未装${c_0}" "$pass" "$fail" "$warn"
[ "$declined" -gt 0 ] && printf " / ${c_d}%d 刻意不装${c_0}" "$declined"
printf "\n"
if [ "$fail" -eq 0 ]; then
  printf "${c_g}✓ 必备工具链齐全。${c_0}\n"
  exit 0
else
  printf "${c_r}✗ 有 %d 项必需工具缺失，按上面「修复」命令补齐后重跑本脚本。${c_0}\n" "$fail"
  printf "${c_d}提示：装完 MCP/插件/状态栏需重启 CC 会话才生效。${c_0}\n"
  exit 1
fi
