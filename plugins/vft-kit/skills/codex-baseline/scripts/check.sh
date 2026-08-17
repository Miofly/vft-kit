#!/usr/bin/env bash
# codex-baseline —— 核对本机 Codex 是否符合装配基线。
# 只读，不改配置；缺什么就打印对应修复命令。
set -uo pipefail

HEALTH=0
for arg in "$@"; do [ "$arg" = "--health" ] && HEALTH=1; done

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CODEX_HOME/config.toml"
AGENTS="$CODEX_HOME/AGENTS.md"
PLUGIN_CACHE="$CODEX_HOME/plugins/cache"
SYSTEM_SKILLS="$CODEX_HOME/skills/.system"
NPM_ROOT="$(npm root -g 2>/dev/null || printf '')"
IMAGEGEN_CLI="${CODEX_IMAGEGEN_CLI:-$SYSTEM_SKILLS/imagegen/scripts/image_gen.py}"
IMAGEGEN_VENV="${CODEX_IMAGEGEN_VENV:-$CODEX_HOME/venvs/imagegen-cli}"
IMAGEGEN_WRAPPER="${CODEX_IMAGEGEN_WRAPPER:-$HOME/.local/bin/codex-imagegen}"
CC_SWITCH_APP_PATH="${CC_SWITCH_APP_PATH:-/Applications/CC Switch.app}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_HEALTH_SCRIPT="${MCP_HEALTH_SCRIPT:-$SCRIPT_DIR/check-mcp-health.mjs}"
CODEX_STATE_SCRIPT="${CODEX_STATE_SCRIPT:-$SCRIPT_DIR/inspect-codex-state.mjs}"
CODEX_STATE_NODE="${CODEX_STATE_NODE:-node}"
RTK_MD="$CODEX_HOME/RTK.md"
CODEGRAPH_INSTALL='curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh'

pass=0; fail=0; warn=0; declined=0

declined_item(){
  [ -n "${CODEX_BASELINE_SKIP:-}" ] || return 1
  local rest="${CODEX_BASELINE_SKIP}" kw
  while [ -n "$rest" ]; do
    case "$rest" in
      *,*) kw="${rest%%,*}"; rest="${rest#*,}" ;;
      *)   kw="$rest";       rest="" ;;
    esac
    kw="${kw#"${kw%%[![:space:]]*}"}"; kw="${kw%"${kw##*[![:space:]]}"}"
    [ -n "$kw" ] || continue
    case "$1" in *"$kw"*) return 0 ;; esac
  done
  return 1
}

c_g=$'\033[32m'; c_r=$'\033[31m'; c_y=$'\033[33m'; c_d=$'\033[2m'; c_0=$'\033[0m'
ok()  { printf "  ${c_g}✓${c_0} %s\n" "$1"; pass=$((pass+1)); }
bad() {
  if declined_item "$1"; then
    printf "  ${c_d}⊘ %-34s (刻意不装，已在 CODEX_BASELINE_SKIP 声明)${c_0}\n" "$1"
    declined=$((declined+1))
    return 0
  fi
  printf "  ${c_r}✗${c_0} %-34s ${c_d}→ 修复: %s${c_0}\n" "$1" "$2"
  fail=$((fail+1))
}
opt() { printf "  ${c_y}○${c_0} %-34s ${c_d}(可选) %s${c_0}\n" "$1" "$2"; warn=$((warn+1)); }
sec(){ printf "\n${c_d}== %s ==${c_0}\n" "$1"; }

has_cmd(){ command -v "$1" >/dev/null 2>&1; }
codex_feature_enabled(){
  has_cmd codex || return 1
  codex features list 2>/dev/null | awk -v feature="$1" '$1 == feature && $NF == "true" { found=1 } END { exit found?0:1 }'
}
npm_g_installed(){ [ -n "$NPM_ROOT" ] && [ -d "$NPM_ROOT/$1" ]; }
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
resolved_mcp_json(){
  has_cmd codex || return 1
  codex mcp get "$1" --json 2>/dev/null
}
mcp_present(){
  local json
  if json="$(resolved_mcp_json "$1")"; then
    printf '%s' "$json" | "$CODEX_STATE_NODE" "$CODEX_STATE_SCRIPT" mcp-present >/dev/null 2>&1
    return
  fi
  cfg_has_line "^\\[mcp_servers\\.($1|\"$1\")\\][[:space:]]*$"
}
mcp_configured(){ mcp_present "$1"; }
mcp_enabled(){
  local json
  if json="$(resolved_mcp_json "$1")"; then
    printf '%s' "$json" | "$CODEX_STATE_NODE" "$CODEX_STATE_SCRIPT" mcp-enabled >/dev/null 2>&1
    return
  fi
  ! cfg_section_has_line "[mcp_servers.$1]" '^[[:space:]]*enabled[[:space:]]*=[[:space:]]*false[[:space:]]*$'
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
PLUGIN_LIST_LOADED=0
PLUGIN_LIST_OK=0
PLUGIN_LIST_JSON=""
load_plugin_list(){
  [ "$PLUGIN_LIST_LOADED" -eq 1 ] && return
  PLUGIN_LIST_LOADED=1
  if has_cmd codex && PLUGIN_LIST_JSON="$(codex plugin list --json 2>/dev/null)"; then
    PLUGIN_LIST_OK=1
  fi
}
plugin_resolved(){
  load_plugin_list
  [ "$PLUGIN_LIST_OK" -eq 1 ] || return 2
  printf '%s' "$PLUGIN_LIST_JSON" | "$CODEX_STATE_NODE" "$CODEX_STATE_SCRIPT" plugin-enabled "$1" >/dev/null 2>&1
}
check_plugin(){
  local key="$1" required="$2" action="$3"
  local enabled=0 cached=0 detail="" resolved_status
  plugin_resolved "$key"
  resolved_status=$?
  if [ "$resolved_status" -eq 0 ]; then
    ok "${key}（installed + enabled）"
    return
  elif [ "$resolved_status" -ne 2 ]; then
    detail="未安装或未启用"
    if [ "$required" = "required" ]; then
      bad "${key}（${detail}）" "$action"
    else
      opt "${key}（${detail}）" "$action"
    fi
    return
  fi
  plugin_enabled "$key" && enabled=1
  plugin_cached "$key" && cached=1
  if [ "$enabled" -eq 1 ] && [ "$cached" -eq 1 ]; then
    ok "${key}（enabled + cache）"
    return
  fi
  [ "$enabled" -eq 1 ] || detail="未启用"
  [ "$cached" -eq 1 ] || detail="${detail:+${detail}、}cache 缺失"
  if [ "$required" = "required" ]; then
    bad "${key}（${detail}）" "$action"
  else
    opt "${key}（${detail}）" "$action"
  fi
}
github_plugin_active(){
  local status
  plugin_resolved "github@openai-api-curated"
  status=$?
  [ "$status" -eq 0 ] || { [ "$status" -eq 2 ] && plugin_enabled "github@openai-api-curated"; }
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
agents_has_parallel_policy(){
  [ -f "$AGENTS" ] || return 1
  grep -Eiq '默认并行|收到任务.*并行|立即.*多.*[Aa]gent|N.*2|≥2' "$AGENTS" || return 1
  grep -Eiq 'spawn_agent|多个 subagent|多.*[Aa]gent|扇出|fan-?out' "$AGENTS" || return 1
  grep -Eiq '共享.*工作区|文件.*重叠|所有权|同一文件|互不重叠' "$AGENTS" || return 1
  grep -Eiq '主.*汇总|结论汇总|最终验证|整合' "$AGENTS"
}
agents_has_codegraph_policy(){
  agents_has 'codegraph.*自动|\.codegraph.*自动建立|自动.*codegraph.*索引|codegraph.*新项目' || return 1
  agents_has 'codegraph[[:space:]]+sync' || return 1
  agents_has 'codegraph[[:space:]]+index[[:space:]]+-f' || return 1
  ! agents_has 'codegraph[[:space:]]+update|codegraph[[:space:]]+init[[:space:]]+--force'
}
agents_has_caveman_default(){
  agents_has 'Caveman.*默认.*full|caveman.*default.*full' || return 1
  agents_has '新会话|每个会话|SessionStart|session'
}
global_skill_exists(){
  [ -f "$CODEX_HOME/skills/$1/SKILL.md" ] || [ -f "$HOME/.agents/skills/$1/SKILL.md" ]
}
missing_global_skills(){
  local skill missing=""
  for skill in "$@"; do
    global_skill_exists "$skill" || missing="${missing}${missing:+, }$skill"
  done
  printf '%s' "$missing"
}
gsap_skills_installed(){
  local skill
  for skill in gsap-core gsap-frameworks gsap-performance gsap-plugins gsap-react gsap-scrolltrigger gsap-timeline gsap-utils; do
    global_skill_exists "$skill" || return 1
  done
}
rtk_codex_ready(){
  [ -f "$RTK_MD" ] && agents_has 'RTK\.md|rtk.*命令|token-optimized|token.*优化'
}
chromium_installed(){
  local dir
  for dir in "$HOME/Library/Caches/ms-playwright" "$HOME/.cache/ms-playwright"; do
    [ -d "$dir" ] && find "$dir" -mindepth 1 -maxdepth 1 -type d -name 'chromium*' | grep -q . && return 0
  done
  return 1
}
imagegen_deps_installed(){
  [ -x "$IMAGEGEN_VENV/bin/python" ] || return 1
  "$IMAGEGEN_VENV/bin/python" - <<'PY' >/dev/null 2>&1
import openai
import PIL
PY
}
imagegen_key_source_available(){
  [ -n "${OPENAI_API_KEY:-}" ] && return 0
  if [ "$(uname -s 2>/dev/null || printf unknown)" = "Darwin" ] && command -v security >/dev/null 2>&1; then
    security find-generic-password -a "${USER:-$(id -un)}" -s 'CC_SWITCH_CODEX_API_KEY' -w >/dev/null 2>&1 && return 0
  fi
  [ -f "$CODEX_HOME/auth.json" ] || return 1
  if has_cmd node; then
    node -e 'const fs=require("fs");try{const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.exit(typeof j.OPENAI_API_KEY==="string"&&j.OPENAI_API_KEY.length>0?0:1)}catch{process.exit(1)}' "$CODEX_HOME/auth.json" 2>/dev/null
  elif has_cmd jq; then
    jq -e '(.OPENAI_API_KEY // "") | length > 0' "$CODEX_HOME/auth.json" >/dev/null 2>&1
  else
    return 1
  fi
}
mcp_healthy(){
  has_cmd codex || return 1
  [ -f "$MCP_HEALTH_SCRIPT" ] || return 1
  codex mcp get "$1" --json 2>/dev/null | node "$MCP_HEALTH_SCRIPT" >/dev/null 2>&1
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
has_cmd brew  && ok "brew"                                                   || opt "brew" "安装 Homebrew（用于补齐常用 CLI）"
has_cmd jq    && ok "jq"                                                   || opt "jq" "brew install jq"
has_cmd gh    && ok "gh ($(gh --version 2>/dev/null | head -1 | awk '{print $3}'))" || opt "gh" "brew install gh（GitHub CLI：PR/Actions/仓库操作，可选）"
has_cmd vercel && ok "vercel ($(vercel --version 2>/dev/null | head -1))" || opt "vercel CLI" "npm i -g vercel"
if has_cmd rtk; then
  rtk_codex_ready && ok "RTK Codex 指令已接入" || opt "RTK Codex 指令" "rtk init --codex --global"
else
  opt "RTK" "brew install rtk && rtk init --codex --global"
fi

sec "dangerous full access 权限基线"
[ -f "$CONFIG" ] && ok "$CONFIG" || bad "config.toml" "创建 ~/.codex/config.toml"
cfg_has_line '^[[:space:]]*approval_policy[[:space:]]*=[[:space:]]*"never"[[:space:]]*$' && ok 'approval_policy = "never"' || bad "approval_policy" '在 ~/.codex/config.toml 顶层加入: approval_policy = "never"'
cfg_has_line '^[[:space:]]*sandbox_mode[[:space:]]*=[[:space:]]*"danger-full-access"[[:space:]]*$' && ok 'sandbox_mode = "danger-full-access"' || bad "sandbox_mode" '在 ~/.codex/config.toml 顶层加入: sandbox_mode = "danger-full-access"'
cfg_section_has_line "[notice]" '^[[:space:]]*hide_full_access_warning[[:space:]]*=[[:space:]]*true[[:space:]]*$' && ok "full access 警告已隐藏" || opt "full access 警告隐藏" '在 [notice] 下加入: hide_full_access_warning = true'

sec "项目与 hooks"
cfg_section_has_line "[features]" '^[[:space:]]*hooks[[:space:]]*=[[:space:]]*true[[:space:]]*$' && ok "features.hooks = true" || bad "hooks feature" '在 [features] 下加入: hooks = true'
cfg_section_has_line "[features]" '^[[:space:]]*memories[[:space:]]*=[[:space:]]*true[[:space:]]*$' && ok "features.memories = true" || bad "Codex Memories" '在 [features] 下加入: memories = true'
codex_feature_enabled "multi_agent" && ok "multi_agent feature 已启用" || bad "Codex multi_agent" '运行: codex features enable multi_agent；然后新开 Codex 会话'
cfg_has_line '^[[:space:]]*check_for_update_on_startup[[:space:]]*=[[:space:]]*false[[:space:]]*$' && ok "启动自动更新检查已关闭" || opt "启动自动更新检查" '仅由 Volta/Homebrew/公司统一管版本时，在 config.toml 顶层加入: check_for_update_on_startup = false'
if project_trusted "/"; then
  ok "/ 已信任"
elif project_trusted "$HOME/Documents/code/wfly"; then
  ok "$HOME/Documents/code/wfly 已信任"
else
  bad "项目 trust_level" '在 ~/.codex/config.toml 加入 [projects."/"] trust_level = "trusted" 或信任常用代码根'
fi

sec "Playwright MCP"
if mcp_configured "playwright"; then
  ok "playwright MCP 已配置"
  if mcp_enabled "playwright"; then
    ok "playwright MCP 已启用"
  else
    bad "playwright MCP 已禁用" '删除 [mcp_servers.playwright] 下的 enabled = false，或改为 enabled = true'
  fi
else
  bad "playwright MCP" "codex mcp add playwright -- npx --yes @playwright/mcp@latest"
fi
chromium_installed && ok "Playwright Chromium 内核" || bad "Playwright Chromium 内核" "npx --yes playwright install chromium"

sec "代码与审计 MCP（必需）"
if npm_g_installed "@danielsogl/lighthouse-mcp"; then ok "@danielsogl/lighthouse-mcp"; else bad "@danielsogl/lighthouse-mcp" "npm i -g @danielsogl/lighthouse-mcp"; fi
if has_cmd codegraph; then ok "codegraph CLI ($(codegraph -V 2>/dev/null))"; else bad "codegraph CLI" "$CODEGRAPH_INSTALL"; fi
if mcp_configured "codegraph"; then
  ok "codegraph MCP 已配置"
  has_cmd codegraph && ok "codegraph MCP 命令可执行" || bad "codegraph MCP 命令不可执行" "$CODEGRAPH_INSTALL"
  mcp_enabled "codegraph" && ok "codegraph MCP 已启用" || bad "codegraph MCP 已禁用" '删除 [mcp_servers.codegraph] 下的 enabled = false，或改为 enabled = true'
else
  bad "codegraph MCP" "codex mcp add codegraph -- codegraph serve --mcp"
fi
if mcp_configured "lighthouse-mcp"; then
  ok "lighthouse-mcp MCP 已配置"
  npm_g_installed "@danielsogl/lighthouse-mcp" && ok "lighthouse-mcp 载体存在" || bad "lighthouse-mcp 载体缺失" "npm i -g @danielsogl/lighthouse-mcp"
  mcp_enabled "lighthouse-mcp" && ok "lighthouse-mcp MCP 已启用" || bad "lighthouse-mcp MCP 已禁用" '删除 [mcp_servers.lighthouse-mcp] 下的 enabled = false，或改为 enabled = true'
else
  bad "lighthouse-mcp MCP" "npm i -g @danielsogl/lighthouse-mcp && codex mcp add lighthouse-mcp -- node \"\$(npm root -g)/@danielsogl/lighthouse-mcp/dist/index.js\""
fi

sec "文档与部署 MCP"
if mcp_configured "openaiDeveloperDocs"; then
  ok "OpenAI Developer Docs MCP 已配置"
  mcp_enabled "openaiDeveloperDocs" && ok "OpenAI Developer Docs MCP 已启用" || bad "OpenAI Developer Docs MCP 已禁用" '删除 [mcp_servers.openaiDeveloperDocs] 下的 enabled = false，或改为 enabled = true'
else
  bad "OpenAI Developer Docs MCP" "codex mcp add openaiDeveloperDocs --url https://developers.openai.com/mcp"
fi
if mcp_configured "context7"; then
  ok "context7 MCP 已配置"
  mcp_enabled "context7" && ok "context7 MCP 已启用" || opt "context7 MCP 已禁用" '删除 [mcp_servers.context7] 下的 enabled = false，或改为 enabled = true'
else
  opt "context7 MCP" "codex mcp add context7 -- npx -y @upstash/context7-mcp@latest"
fi
if mcp_configured "vercel"; then
  ok "Vercel MCP 已配置"
  mcp_enabled "vercel" && ok "Vercel MCP 已启用" || opt "Vercel MCP 已禁用" '删除 [mcp_servers.vercel] 下的 enabled = false，或改为 enabled = true'
else
  opt "Vercel MCP" "codex mcp add vercel --url https://mcp.vercel.com"
fi

sec "CLI 插件（合并 scope 后 installed + enabled）"
check_plugin "github@openai-api-curated" required "codex plugin add github@openai-api-curated"
if github_plugin_active; then
  if [ -n "${GITHUB_PAT_TOKEN:-}" ]; then
    ok "GITHUB_PAT_TOKEN 已注入"
  elif has_cmd gh && gh auth token >/dev/null 2>&1; then
    bad "GITHUB_PAT_TOKEN 未注入（gh 已登录）" '执行: printf '\''\nexport GITHUB_PAT_TOKEN="$(gh auth token 2>/dev/null)"\n'\'' >> ~/.zshrc；然后重启 Codex'
  else
    bad "GITHUB_PAT_TOKEN 未注入" '先运行 gh auth login；再执行: printf '\''\nexport GITHUB_PAT_TOKEN="$(gh auth token 2>/dev/null)"\n'\'' >> ~/.zshrc；然后重启 Codex'
  fi
fi
check_plugin "superpowers@openai-api-curated" optional "codex plugin add superpowers@openai-api-curated"
check_plugin "build-web-apps@openai-api-curated" required "codex plugin add build-web-apps@openai-api-curated"
check_plugin "ponytail@ponytail" required "codex plugin marketplace add DietrichGebert/ponytail；再运行 codex plugin add ponytail@ponytail"
check_plugin "context-mode@context-mode" required "codex plugin marketplace add https://github.com/mksglu/claude-context-mode.git；再运行 codex plugin add context-mode@context-mode"
check_plugin "diagram-design@diagram-design" optional "codex plugin marketplace add cathrynlavery/diagram-design；再运行 codex plugin add diagram-design@diagram-design"

sec "兼容 Agent Skills"
global_skill_exists "caveman" && ok "caveman skill" || bad "caveman skill" "npx skills add JuliusBrussee/caveman -a codex"
agents_has_caveman_default && ok "Caveman 默认 full 自动启用" || bad "Caveman 默认 full 自动启用" "bash \"$SCRIPT_DIR/install-caveman-default.sh\""
gsap_skills_installed && ok "GSAP 官方 skills（8 项）" || bad "GSAP 官方 skills" "npx skills add https://github.com/greensock/gsap-skills --agent codex"
global_skill_exists "anysearch" && ok "anysearch skill（联网实时搜索）" || opt "anysearch skill" "bash \"$SCRIPT_DIR/install-anysearch.sh\""
global_skill_exists "grill-me" && ok "grill-me skill（深度访谈）" || opt "grill-me skill" "npx skills add mattpocock/skills --skill grill-me --agent codex --global --yes"
emil_required_missing="$(missing_global_skills animate review-animations apple-design)"
if [ -z "$emil_required_missing" ]; then
  ok "Emil 动效 skills（必装 3 项）"
else
  bad "Emil 动效 skills（缺 ${emil_required_missing}）" "npx skills add emilkowalski/skills --skill animate --skill review-animations --skill apple-design --agent codex --global --yes"
fi
emil_optional_missing="$(missing_global_skills animation-vocabulary ask-sonner emil-design-eng find-animation-opportunities improve-animations pick-ui-library prototype)"
if [ -z "$emil_optional_missing" ]; then
  ok "Emil 扩展 skills（可选 7 项）"
else
  opt "Emil 扩展 skills（缺 ${emil_optional_missing}）" "按项目用 npx skills add emilkowalski/skills --skill <name> --agent codex --global --yes 单独安装"
fi
global_skill_exists "understand" && ok "understand-anything skills（代码知识图谱）" || opt "understand-anything skills" "curl -fsSL https://raw.githubusercontent.com/Egonex-AI/Understand-Anything/main/install.sh | bash -s codex（首次全量分析耗 token）"
if global_skill_exists "create-prd" || {
  [ -f "$HOME/.agents/.skill-lock.json" ] && "$CODEX_STATE_NODE" -e 'const j=require(process.argv[1]);process.exit(Object.values(j.skills||{}).some(v=>v.source==="phuryn/pm-skills")?0:1)' "$HOME/.agents/.skill-lock.json" 2>/dev/null
}; then
  ok "pm-skills（产品工作流）"
else
  opt "pm-skills" "npx skills add phuryn/pm-skills --agent codex --global --yes"
fi

sec "系统 skills"
for s in openai-docs imagegen skill-creator plugin-creator skill-installer; do
  skill_exists "$s" && ok "$s" || bad "$s" "恢复 $SYSTEM_SKILLS/$s/SKILL.md"
done

sec "图片生成 CLI/API"
[ -f "$IMAGEGEN_CLI" ] && ok "imagegen CLI 脚本" || bad "imagegen CLI 脚本" "恢复 $IMAGEGEN_CLI"
[ -x "$IMAGEGEN_VENV/bin/python" ] && ok "imagegen Python venv" || bad "imagegen Python venv" "bash \"$SCRIPT_DIR/prepare-imagegen-cli-env.sh\""
imagegen_deps_installed && ok "imagegen 依赖 openai + pillow" || bad "imagegen Python 依赖" "bash \"$SCRIPT_DIR/prepare-imagegen-cli-env.sh\""
[ -x "$IMAGEGEN_WRAPPER" ] && ok "codex-imagegen 命令" || bad "codex-imagegen 命令" "bash \"$SCRIPT_DIR/prepare-imagegen-cli-env.sh\""
imagegen_key_source_available && ok "OPENAI_API_KEY 注入源" || bad "OPENAI_API_KEY 注入源" "bash \"$SCRIPT_DIR/sync-cc-switch-openai-env.sh\"；或在 ~/.codex/auth.json 写入 OPENAI_API_KEY"

sec "全局 AGENTS 规范"
[ -f "$AGENTS" ] && ok "$AGENTS" || bad "全局 AGENTS.md" "创建 ~/.codex/AGENTS.md"
agents_has '中文回复|简体中文|一律中文|reply.*[Cc]hinese' && ok "全局规范含「始终中文回复」" || bad "中文回复规范" $'printf \'\\n- 始终使用简体中文回复。\\n\' >> ~/.codex/AGENTS.md'
agents_has '可点短链|短链|markdown 可点|Cannot open file' && ok "全局规范含「代码位置可点短链」" || bad "代码短链规范" $'printf \'\\n- 引用代码位置使用 markdown 可点短链：[短名:行](绝对路径:行)。\\n\' >> ~/.codex/AGENTS.md'
agents_has '上下文压缩|压缩取舍|保留决策和状态' && ok "全局规范含「压缩取舍规则」" || bad "压缩取舍规范" $'printf \'\\n- 上下文压缩时保留决策和状态，丢弃可重跑恢复的噪音。\\n\' >> ~/.codex/AGENTS.md'
agents_has '代理兜底|走代理重试|外网.*代理|127\.0\.0\.1:78|http\.proxy|https_proxy' && ok "全局规范含「外网操作代理兜底」" || bad "代理兜底规范" $'printf \'\\n- 外网操作连不通或慢得反常时，先复用 https_proxy/http_proxy/all_proxy；没有则探测常见本地代理端口，再用 curl -x、git -c http.proxy 或环境变量走代理重试。\\n\' >> ~/.codex/AGENTS.md'
agents_has_parallel_policy && ok "全局规范含「多 Agent 并行执行」" || bad "多 Agent 并行规范" $'cat >> ~/.codex/AGENTS.md <<\'RULE\'\n\n## 多 Agent 并行执行（默认并行，能加速就上）\n\n收到任务先判断能否拆成至少 2 个互不依赖、边界清晰的工作流；能拆就立即使用 Codex 子 Agent 并行执行，不等用户提醒。数量词（每个、所有、批量、一批、分别、多个、全部、整个）、重复动作、多文件、多模块、多目标调研、批量整改和多视角复核都是触发信号。单个小任务直接处理；强依赖链串行或只并行其中无依赖部分。\n\n编排时连续调用 `spawn_agent` 启动多个子 Agent，不逐个等待；每个子 Agent 只接一个具体、可独立验收的任务，并明确目录、文件或问题边界。子 Agent 与主 Agent 共享工作区，必须分配互不重叠的文件所有权，禁止多个 Agent 同时修改同一文件。主 Agent 同时继续可独立推进的工作，之后用协作工具收集结果；需要补充工作时复用已有 Agent。\n\n主 Agent 负责汇总结论、检查共享工作区改动、处理冲突并运行最终整体验证。子 Agent 回传精炼结论和验证结果，不把大段原始文件内容塞回主上下文。\nRULE'
if has_cmd codegraph; then
  agents_has_codegraph_policy && ok "全局规范含「CodeGraph 自动初始化与索引刷新」" || bad "CodeGraph 索引刷新规范" $'sed -i.bak -e \'s/codegraph update/codegraph sync/g\' -e \'s/codegraph init --force/codegraph index -f/g\' ~/.codex/AGENTS.md && printf \'\\n- 进入代码项目时，没有 .codegraph 就执行 codegraph init；已有索引执行 codegraph sync，完整重建执行 codegraph index -f。\\n\' >> ~/.codex/AGENTS.md'
else
  ok "CodeGraph 自动初始化规范（codegraph 未装，无需配置）"
fi
if mcp_present "context7" && mcp_enabled "context7"; then
  agents_has 'context7|[Cc]ontext7|官方文档|最新文档|库.*框架.*文档|SDK.*文档|API.*文档' && ok "全局规范含「context7 官方文档优先」" || bad "context7 调用规范" $'printf \'\\n- 涉及库、框架、SDK、API、CLI 或云服务的用法、配置、迁移和报错排查时，优先使用 context7 查询当前官方文档。\\n\' >> ~/.codex/AGENTS.md'
else
  ok "context7 调用规范（MCP 未启用，无需配置）"
fi
if global_skill_exists "anysearch"; then
  agents_has 'anysearch' && ok "全局规范含「anysearch 联网搜索优先」" || bad "anysearch 调用规范" $'printf \'\\n- 需要联网检索、事实核查或读取网页正文时优先使用 anysearch；不可用时回退内置网页搜索。\\n\' >> ~/.codex/AGENTS.md'
else
  ok "anysearch 调用规范（skill 未装，无需配置）"
fi
agents_has 'codex-imagegen generate|不要先声明“我会走 imagegen skill”|不要先跑 `codex-imagegen --help` 做探测' && ok "全局规范含「生图直接走 codex-imagegen」" || bad "生图 codex-imagegen 全局规则" "bash \"$SCRIPT_DIR/install-imagegen-agents-rule.sh\""

sec "系统辅助工具（可选）"
[ -d "$CC_SWITCH_APP_PATH" ] && ok "cc-switch App" || opt "cc-switch App" "brew install --cask cc-switch"
if cfg_has_line '^\[mcp_servers\.(node_repl|"node_repl")\][[:space:]]*$' && mcp_enabled "node_repl"; then
  node_repl_command="$(awk '
    $0 ~ /^\[mcp_servers\.(node_repl|"node_repl")\][[:space:]]*$/ { in_section=1; next }
    /^\[/ { in_section=0 }
    in_section && /^[[:space:]]*command[[:space:]]*=/ {
      value=$0; sub(/^[^"]*"/, "", value); sub(/".*$/, "", value); print value; exit
    }
  ' "$CONFIG")"
  if [ -n "$node_repl_command" ]; then
    case "$node_repl_command" in
      */*) [ -e "$node_repl_command" ] || opt "node_repl command 不存在" "禁用该 MCP，或修正 command: $node_repl_command" ;;
      *) has_cmd "$node_repl_command" || opt "node_repl command 不存在" "禁用该 MCP，或修正 command: $node_repl_command" ;;
    esac
  fi
fi

if [ "$HEALTH" -eq 1 ]; then
  sec "MCP 实连健康检查"
  mcp_healthy "playwright" && ok "playwright MCP 已连接" || bad "playwright MCP 未连接" "检查 MCP 启动命令与 Chromium 内核"
  if mcp_configured "codegraph" && mcp_enabled "codegraph"; then
    mcp_healthy "codegraph" && ok "codegraph MCP 已连接" || bad "codegraph MCP 未连接" "检查 codegraph serve --mcp"
  fi
  if mcp_configured "lighthouse-mcp" && mcp_enabled "lighthouse-mcp"; then
    mcp_healthy "lighthouse-mcp" && ok "lighthouse-mcp MCP 已连接" || bad "lighthouse-mcp MCP 未连接" "检查全局 npm 包与 dist/index.js 路径"
  fi
fi

printf "\n${c_d}────────────────────────────────${c_0}\n"
printf "结果：${c_g}%d 正常${c_0} / ${c_r}%d 缺失(必需)${c_0} / ${c_y}%d 可选提醒${c_0} / ${c_d}%d 刻意不装${c_0}\n" "$pass" "$fail" "$warn" "$declined"
if [ "$fail" -eq 0 ]; then
  printf "${c_g}✓ Codex 必备基线齐全。${c_0}\n"
  printf "${c_d}提示：配置变更后新开 Codex 会话才稳定生效。${c_0}\n"
  exit 0
else
  printf "${c_r}✗ 有 %d 项必需基线缺失，按上面修复命令补齐后重跑。${c_0}\n" "$fail"
  printf "${c_d}提示：配置变更后新开 Codex 会话才稳定生效。${c_0}\n"
  exit 1
fi
