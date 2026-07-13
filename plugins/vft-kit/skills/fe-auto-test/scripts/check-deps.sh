#!/usr/bin/env bash
# fe-auto-test 前置依赖检查 + 自动补装 —— 闭环第 0 步，先跑它再跑别的。
#
# 设计要点：**永不因缺依赖而中断闭环。**
#
# 关键认知：本 skill 的全部能力都能不靠 MCP 完成 —— playwright 和 lighthouse 都是普通 npm 包，
# 直接当库调用（scripts/*.mjs 走的就是这条路），装完立即可用、无需重启会话。
# 而 MCP（browser_* / lighthouse MCP）新注册后当次会话拿不到工具，必须重启才加载。
# 所以这里把依赖分成两层：
#
#   [硬依赖] npm 包 + chromium 内核 —— 缺了自动装，装完本次就能用。这层齐了就能跑全套。
#   [软依赖] MCP / 插件           —— 缺了也照跑（走脚本路径），顺手注册好，下次重启即得。
#
# 用法:
#   check-deps.sh              检查 + 自动补装硬依赖，顺带注册软依赖（默认）
#   check-deps.sh --no-install 只检查不装，用于纯诊断
#
# 退出码:
#   0 = 可以跑闭环（硬依赖齐全；MCP 有没有都不挡路，用 MCP_READY 标记告知走哪条路）
#   1 = 硬依赖装失败，确实跑不了（网络/权限问题，需人工介入）
#
# stdout 末尾输出机器可读标记，供调用方决定走哪条路。
# **两个能力分开判**——playwright 插件在、lighthouse MCP 不在是最常见的组合，
# 若合成一个总开关，会因为缺 lighthouse 就连 browser_* 的交互式调试一起放弃：
#   PW_READY=1   → browser_* 可用（交互式渲染 / console / 截图 / 点击）
#   LH_READY=1   → lighthouse MCP 可用（否则用 lighthouse-audit.mjs，能力等价）
#   MCP_READY=1  → 两者皆备（保留此行是为了兼容旧调用，别只看它）
set -uo pipefail

DO_INSTALL=1
for a in "$@"; do [ "$a" = "--no-install" ] && DO_INSTALL=0; done

CLAUDE_JSON="$HOME/.claude.json"
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
NPM_ROOT="$(npm root -g 2>/dev/null || echo '')"
LH_PKG="@danielsogl/lighthouse-mcp"   # 一包两用：既是 MCP 载体，其 node_modules 里的 lighthouse 也供脚本直接 import

c_g=$'\033[32m'; c_r=$'\033[31m'; c_y=$'\033[33m'; c_d=$'\033[2m'; c_0=$'\033[0m'
ok()   { printf "  ${c_g}✓${c_0} %s\n" "$1"; }
miss() { printf "  ${c_y}○${c_0} %-30s ${c_d}%s${c_0}\n" "$1" "$2"; }
fail() { printf "  ${c_r}✗${c_0} %s\n" "$1"; }
info() { printf "${c_d}%s${c_0}\n" "$1"; }

# —— 探测函数（与 cc-baseline/scripts/check.sh 同款：确定性读文件，不调 claude plugin list 那种慢命令）——
plugin_installed() {
  [ -f "$INSTALLED_PLUGINS" ] || return 1
  node -e "const j=require('$INSTALLED_PLUGINS').plugins||{};process.exit(Object.keys(j).some(k=>k.split('@')[0]===process.argv[1])?0:1)" "$1" 2>/dev/null
}
mcp_registered() {
  [ -f "$CLAUDE_JSON" ] || return 1
  node -e "const j=require('$CLAUDE_JSON');const s=new Set(Object.keys(j.mcpServers||{}));for(const p in (j.projects||{})){const m=j.projects[p].mcpServers;if(m)Object.keys(m).forEach(k=>s.add(k))}process.exit(s.has(process.argv[1])?0:1)" "$1" 2>/dev/null
}
npm_g_installed() { [ -n "$NPM_ROOT" ] && [ -d "$NPM_ROOT/$1" ]; }
chromium_installed() {
  local d
  for d in "$HOME/Library/Caches/ms-playwright" "$HOME/.cache/ms-playwright"; do
    [ -d "$d" ] && ls "$d" 2>/dev/null | grep -q '^chromium' && return 0
  done
  return 1
}

printf "${c_d}fe-auto-test 依赖检查${c_0}\n"

# ========== 第一层：硬依赖（缺了自动装，装完本次即可用）==========
printf "\n${c_d}== 硬依赖（脚本路径，装完立即生效）==${c_0}\n"
HARD_FAIL=0

if npm_g_installed playwright; then
  ok "playwright（npm 包）"
else
  miss "playwright" "补装中..."
  if [ "$DO_INSTALL" -eq 1 ] && npm i -g playwright >/dev/null 2>&1; then
    ok "playwright 已装"
  else
    fail "playwright 装失败 → 手动: npm i -g playwright"; HARD_FAIL=1
  fi
fi

if chromium_installed; then
  ok "chromium 内核"
else
  miss "chromium 内核" "下载中（约 100MB，不改任何配置）..."
  if [ "$DO_INSTALL" -eq 1 ] && npx --yes playwright install chromium >/dev/null 2>&1; then
    ok "chromium 内核已装"
  else
    fail "chromium 装失败 → 手动: npx playwright install chromium"; HARD_FAIL=1
  fi
fi

# lighthouse 库：装 $LH_PKG 即可，它的 node_modules 里带着 lighthouse + chrome-launcher，
# _lh.mjs 会去那儿找。同一个包又能拿去注册 MCP，一包两用。
if npm_g_installed "$LH_PKG"; then
  ok "lighthouse（库，供 lighthouse-audit.mjs 直接调用）"
else
  miss "lighthouse" "补装中..."
  if [ "$DO_INSTALL" -eq 1 ] && npm i -g "$LH_PKG" >/dev/null 2>&1; then
    ok "lighthouse 已装"
  else
    fail "lighthouse 装失败 → 手动: npm i -g $LH_PKG"; HARD_FAIL=1
  fi
fi

# ========== 第二层：软依赖（缺了不挡路，顺手注册，下次重启生效）==========
printf "\n${c_d}== 软依赖（MCP 路径，需重启会话才生效）==${c_0}\n"
PW_READY=1
LH_READY=1

# playwright 插件装在官方 marketplace 下，install 必须带 @marketplace 后缀，裸名装不上。
PW_MARKETPLACE="claude-plugins-official"

if plugin_installed playwright; then
  ok "playwright 插件（browser_* 工具）"
else
  PW_READY=0
  miss "playwright 插件" "注册中（本次会话仍走脚本路径）..."
  if [ "$DO_INSTALL" -eq 1 ]; then
    if claude plugin install "playwright@${PW_MARKETPLACE}" >/dev/null 2>&1; then
      ok "playwright 插件已装（重启后可用 browser_*）"
    else
      info "     装不上也没关系，脚本路径能覆盖。手动: claude plugin install playwright@${PW_MARKETPLACE}"
    fi
  fi
fi

if mcp_registered lighthouse-mcp; then
  ok "lighthouse-mcp（已注册）"
else
  LH_READY=0
  miss "lighthouse-mcp" "注册中（本次会话仍走 lighthouse-audit.mjs）..."
  if [ "$DO_INSTALL" -eq 1 ] && npm_g_installed "$LH_PKG"; then
    claude mcp add lighthouse-mcp -s user -- node "$NPM_ROOT/$LH_PKG/dist/index.js" >/dev/null 2>&1 \
      && ok "lighthouse-mcp 已注册（重启后生效）" \
      || info "     注册失败也没关系，lighthouse-audit.mjs 能覆盖"
  fi
fi

# ========== 结论 ==========
if [ "$HARD_FAIL" -eq 1 ]; then
  printf "\n${c_r}硬依赖缺失且自动补装失败，闭环跑不了。按上面的手动命令装一下。${c_0}\n"
  echo "PW_READY=0"; echo "LH_READY=0"; echo "MCP_READY=0"
  exit 1
fi

printf "\n${c_g}依赖齐全，继续跑闭环。${c_0}\n"
# 两个能力各自降级，互不牵连：缺 lighthouse MCP 不该连 browser_* 一起放弃。
if [ "$PW_READY" -eq 0 ]; then
  info "渲染 / console / 截图 → 走脚本：route-audit.mjs、resilience-audit.mjs、ssr-status-sweep.mjs"
  info "（playwright 插件刚注册，CC 的 MCP 要重启会话才加载；重启后 browser_* 交互式调试可用）"
else
  info "渲染 / console / 截图 → browser_* 可用（交互式）"
fi
if [ "$LH_READY" -eq 0 ]; then
  info "全维度体检           → 走脚本：lighthouse-audit.mjs（评分、指标、未用 JS/CSS、a11y 全都有，能力等价）"
else
  info "全维度体检           → lighthouse MCP 可用（也可直接用 lighthouse-audit.mjs，更省 token）"
fi

MCP_READY=0
[ "$PW_READY" -eq 1 ] && [ "$LH_READY" -eq 1 ] && MCP_READY=1
echo "PW_READY=$PW_READY"
echo "LH_READY=$LH_READY"
echo "MCP_READY=$MCP_READY"
exit 0
