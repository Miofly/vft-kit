#!/bin/bash
# vft-kit 用量告警开通向导（方案 C：自动配置 claude-hud）。
#
# 幂等、可反复跑。usage-alert.sh 本身已由插件 hooks.json 自动注册（Stop 事件），
# 但它不自己读用量——官方 hook payload 没有用量数据，唯一能拿到 rate_limits 的是 statusline。
# 所以它读 claude-hud 落盘的快照。本 skill 负责把这条「数据管道」接上：
#   1. 装 jq（脚本本体与本向导都需要）
#   2. 检测 claude-hud 是否安装（没装则引导，不自动装）
#   3. 往 claude-hud 的 config.json 写 display.externalUsageWritePath，指向 usage-alert 默认读取的快照路径
#   4. 幂等落一份「填满默认值」的 usage-alert-config.json 模板（阈值/声音/新鲜度/快照路径），供用户直接编辑
#
# claude-hud 侧只要 externalUsageWritePath 非空即开始落盘（源码 index.ts:
#   shouldWriteUsage = Boolean(config.display.externalUsageWritePath)），无额外开关。

set -u

# ── 目标路径 ────────────────────────────────────────────────────
# 必须与 usage-alert.sh 默认读取值一致：${CLAUDE_USAGE_SNAPSHOT:-$HOME/.claude/usage-snapshot.json}
SNAPSHOT_PATH="$HOME/.claude/usage-snapshot.json"
HUD_DIR="$HOME/.claude/plugins/claude-hud"
HUD_CFG="$HUD_DIR/config.json"
DATA_DIR="$HOME/.claude/vft-kit"
ALERT_CFG="$DATA_DIR/usage-alert-config.json"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m○\033[0m %s\n' "$1"; }
err()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }

echo "vft-kit 用量告警开通向导"
echo "────────────────────────────"

# ── 1. 平台守卫（usage-alert.sh 用 osascript + stat -f，仅 macOS）──
if [ "$(uname)" != "Darwin" ]; then
  err "用量告警仅支持 macOS（依赖 osascript / stat -f）。当前系统：$(uname)，已跳过。"
  exit 0
fi

# ── 2. jq（硬依赖）─────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "  安装 jq…"
    brew install jq >/dev/null 2>&1 && ok "jq 已安装" || { err "jq 安装失败，请手动 brew install jq 后重跑。"; exit 1; }
  else
    err "缺 jq 且无 brew。usage-alert.sh 与本向导都需要 jq，请先装后重跑。"
    exit 1
  fi
else
  ok "jq 已就绪"
fi

# ── 3. 检测 claude-hud（不自动装）───────────────────────────────
if [ ! -d "$HUD_DIR" ]; then
  err "未检测到 claude-hud（$HUD_DIR 不存在）。"
  echo "     用量告警依赖 claude-hud 落盘用量快照。请先安装 claude-hud 插件，再重跑本向导："
  echo "       /plugin install claude-hud@<你的 marketplace>"
  exit 0
fi
ok "claude-hud 已安装"

# ── 4. 写 claude-hud config：display.externalUsageWritePath ──────
if [ ! -f "$HUD_CFG" ]; then
  jq -n --arg p "$SNAPSHOT_PATH" '{display: {externalUsageWritePath: $p}}' > "$HUD_CFG" \
    && ok "新建 claude-hud config 并写入快照路径" \
    || { err "写 $HUD_CFG 失败"; exit 1; }
elif ! jq empty "$HUD_CFG" >/dev/null 2>&1; then
  BAD_BAK="$HUD_CFG.broken-$(date +%Y%m%d-%H%M%S).bak"
  cp "$HUD_CFG" "$BAD_BAK"
  err "claude-hud config 不是合法 JSON，已备份到 ${BAD_BAK} 但未改动。请修好后重跑。"
  exit 1
else
  CURRENT="$(jq -r '.display.externalUsageWritePath // ""' "$HUD_CFG")"
  if [ "$CURRENT" = "$SNAPSHOT_PATH" ]; then
    ok "claude-hud 已指向快照路径，跳过（${SNAPSHOT_PATH}）"
  else
    BAK="$HUD_CFG.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$HUD_CFG" "$BAK"
    [ -n "$CURRENT" ] && warn "claude-hud 原本指向 ${CURRENT}，为与 usage-alert 对齐已改为 ${SNAPSHOT_PATH}"
    jq --arg p "$SNAPSHOT_PATH" '.display = (.display // {}) | .display.externalUsageWritePath = $p' \
      "$HUD_CFG" > "$HUD_CFG.tmp" && mv "$HUD_CFG.tmp" "$HUD_CFG" \
      && ok "已写入快照路径（原 config 备份到 ${BAK}）" \
      || { err "写 $HUD_CFG 失败"; exit 1; }
  fi
fi

# ── 4b. 幂等落用量告警配置模板（已存在则不覆盖）─────────────────
# 内容须与 usage-alert.sh 的内建默认一致（thresholds 保持每 5% 一档，不改变现有行为）。
mkdir -p "$DATA_DIR"
if [ -f "$ALERT_CFG" ]; then
  ok "usage-alert-config.json 已存在，保留不覆盖"
else
  cat > "$ALERT_CFG" <<'JSON'
{
  "thresholds": [70, 75, 80, 85, 90, 95, 100],
  "sound": "Glass",
  "maxAgeSeconds": 600,
  "snapshotPath": "~/.claude/usage-snapshot.json"
}
JSON
  ok "已生成用量告警配置模板：$ALERT_CFG"
fi

# ── 5. 收尾提示 ─────────────────────────────────────────────────
echo
echo "完成。还需注意："
echo "  1. 重启 Claude Code 会话，claude-hud 才会重载 config 并开始落盘快照（每 ~30s 节流写一次）。"
echo "  2. 仅订阅账号（Pro/Max）有限额窗口才会告警；API key 账号无限额窗口，快照为空 → 不告警（正常）。"
echo "  3. 自定义阈值/声音：编辑 ${ALERT_CFG}（已填满默认值）。也可用环境变量 CLAUDE_USAGE_THRESHOLDS=\"80 95\" 临时覆盖（优先级最高）。"
echo
echo "验证：跑几个 turn 后，cat ${SNAPSHOT_PATH} 应能看到 five_hour / seven_day 的 used_percentage。"
exit 0
