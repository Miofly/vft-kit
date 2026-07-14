#!/bin/bash
# vft-kit 桌面通知开通向导（方案 A）。
#
# 幂等、可反复跑。做这些事：
#   1. 装 terminal-notifier（没 brew 就退 osascript，仍能用，只是没自定义图标）
#   2. 把 notify.mjs + banner.swift 拷到「不随插件版本变」的稳定路径 ~/.claude/vft-kit/hooks/
#   2b. 有 swiftc 就把 banner.swift 编成二进制(自绘双屏横幅)；没有则跳过,通知退回原生
#   3. 幂等落一份「填满默认值」的 notify-config.json 模板（已存在不覆盖），供用户直接编辑
#   4. 用 jq 把 4 个事件的 hook 幂等写进 ~/.claude/settings.json（绝对路径，不用 ${CLAUDE_PLUGIN_ROOT}）
#   5. 弹一条测试通知，触发 macOS 授权弹窗
#
# 为什么不直接用插件自带 hooks.json：那份用 ${CLAUDE_PLUGIN_ROOT} + 带版本号的 cache 路径，
# 插件一升级路径就失效。本 skill 把脚本拷到稳定路径再写绝对路径，规避这个问题。
# 相应地，插件 hooks.json 里的 notify.mjs 已删（只留 usage-alert.sh），避免双重注册双弹。

set -u

# ── 定位自身与源脚本 ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts/ -> notify-setup/ -> skills/ -> <plugin root>
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SRC_NOTIFY="$PLUGIN_ROOT/hooks/notify.mjs"
SRC_BANNER="$PLUGIN_ROOT/hooks/banner.swift"

# ── 稳定路径与目标文件 ───────────────────────────────────────────
DATA_DIR="$HOME/.claude/vft-kit"
STABLE_HOOK_DIR="$DATA_DIR/hooks"
DEST_NOTIFY="$STABLE_HOOK_DIR/notify.mjs"
DEST_BANNER="$STABLE_HOOK_DIR/banner.swift"
BANNER_BIN="$DATA_DIR/bin/banner"
CONFIG_PATH="$DATA_DIR/notify-config.json"
SETTINGS="$HOME/.claude/settings.json"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m○\033[0m %s\n' "$1"; }
err()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }

echo "vft-kit 桌面通知开通向导"
echo "────────────────────────────"

# ── 1. 平台守卫 ─────────────────────────────────────────────────
if [ "$(uname)" != "Darwin" ]; then
  err "桌面通知仅支持 macOS（依赖 terminal-notifier / osascript）。当前系统：$(uname)，已跳过。"
  exit 0
fi

# ── 2. 依赖：node / jq / terminal-notifier ──────────────────────
if ! command -v node >/dev/null 2>&1; then
  err "未找到 node，无法运行 notify.mjs。请先装 Node.js 再重跑。"
  exit 1
fi

HAS_BREW=0
command -v brew >/dev/null 2>&1 && HAS_BREW=1

# jq 是写 settings.json 的硬依赖
if ! command -v jq >/dev/null 2>&1; then
  if [ "$HAS_BREW" = 1 ]; then
    echo "  安装 jq（写 settings.json 需要）…"
    brew install jq >/dev/null 2>&1 && ok "jq 已安装" || { err "jq 安装失败，请手动 brew install jq 后重跑。"; exit 1; }
  else
    err "缺 jq 且无 brew。请先装 jq（改 settings.json 必需）后重跑。"
    exit 1
  fi
else
  ok "jq 已就绪"
fi

# terminal-notifier 是可选增强，缺了退 osascript
if command -v terminal-notifier >/dev/null 2>&1; then
  ok "terminal-notifier 已就绪（通知带自定义图标）"
elif [ "$HAS_BREW" = 1 ]; then
  echo "  安装 terminal-notifier…"
  brew install terminal-notifier >/dev/null 2>&1 \
    && ok "terminal-notifier 已安装" \
    || warn "terminal-notifier 安装失败，将退回 osascript（通知无自定义图标，功能不受影响）"
else
  warn "未装 terminal-notifier 且无 brew，将退回 osascript（无自定义图标，功能不受影响）。如需图标：brew install terminal-notifier"
fi

# ── 3. 拷 notify.mjs 到稳定路径 ─────────────────────────────────
if [ ! -f "$SRC_NOTIFY" ]; then
  err "源脚本不存在：${SRC_NOTIFY}（插件结构异常，请重装 vft-kit）"
  exit 1
fi
mkdir -p "$STABLE_HOOK_DIR"
cp "$SRC_NOTIFY" "$DEST_NOTIFY" && ok "notify.mjs 已拷到稳定路径：$DEST_NOTIFY"

# ── 3a. 自绘双屏横幅：拷 banner.swift + 编译成二进制 ──────────────
# 有 swiftc(Xcode CLT) 就当场编译,横幅立即可用;没有则跳过——通知会自动退回原生,绝不失声。
# 注意:默认配置 allScreens=true 会「接管原生通知」,所以横幅编不出来时 notify.mjs 会退回原生。
if [ -f "$SRC_BANNER" ]; then
  cp "$SRC_BANNER" "$DEST_BANNER" && ok "banner.swift 已拷到稳定路径：$DEST_BANNER"
  if command -v swiftc >/dev/null 2>&1; then
    echo "  编译自绘横幅（swiftc，约 1-2 秒）…"
    mkdir -p "$(dirname "$BANNER_BIN")"
    if swiftc -O "$DEST_BANNER" -o "$BANNER_BIN" 2>/dev/null; then
      ok "双屏横幅已编译：$BANNER_BIN"
    else
      warn "banner.swift 编译失败，将退回原生通知（不影响功能）。可稍后重跑本向导重试。"
    fi
  else
    warn "未找到 swiftc（Xcode 命令行工具），跳过横幅编译，通知退回原生。如需双屏横幅：xcode-select --install"
  fi
else
  warn "banner.swift 源不存在，跳过双屏横幅（不影响原生通知）"
fi

# ── 3b. 幂等落「填满默认值」的配置模板（已存在则不覆盖）───────────
# 让用户能直接发现并编辑一个完整文件；因字段齐全，改任意一项都不会触发
# notify.mjs 浅合并（notifications.<类型> 整块替换）导致丢默认字段的坑。
# 内容须与 notify.mjs 的 DEFAULT_CONFIG 保持一致。
if [ -f "$CONFIG_PATH" ]; then
  ok "notify-config.json 已存在，保留不覆盖"
else
  cat > "$CONFIG_PATH" <<'JSON'
{
  "enabled": true,
  "iconPath": "~/Pictures/claude.icon.png",
  "notifications": {
    "taskComplete":         { "enabled": true, "title": "Claude Code", "subtitle": "任务完成 ✅",    "sound": "Hero"    },
    "taskError":            { "enabled": true, "title": "Claude Code", "subtitle": "任务失败 ❌",    "sound": "Basso"   },
    "waitingForInput":      { "enabled": true, "title": "Claude Code", "subtitle": "等待您的输入 ⏸️", "sound": "default" },
    "conversationComplete": { "enabled": true, "title": "Claude Code", "subtitle": "对话已完成 💬",  "sound": "Glass"   }
  },
  "debounce": { "enabled": true, "intervalSeconds": 5 },
  "dualScreenBanner": { "enabled": true, "allScreens": true, "durationSeconds": 5 }
}
JSON
  ok "已生成默认配置模板：$CONFIG_PATH"
fi

# ── 4. 幂等写 settings.json ─────────────────────────────────────
NODE_CMD="node \"$DEST_NOTIFY\""

# settings.json 不存在则建空对象；存在则校验 JSON，坏 JSON 只备份+退，绝不覆盖
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
  ok "新建 settings.json"
elif ! jq empty "$SETTINGS" >/dev/null 2>&1; then
  BAD_BAK="$SETTINGS.broken-$(date +%Y%m%d-%H%M%S).bak"
  cp "$SETTINGS" "$BAD_BAK"
  err "settings.json 不是合法 JSON，已备份到 $BAD_BAK 但未改动。请修好 JSON 后重跑。"
  exit 1
fi

# 改动前备份一次
BAK="$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$BAK"

# 往某事件幂等追加一条 command hook：已存在同 command 就跳过
add_hook() {
  local event="$1" timeout="$2" matcher="$3"
  local before after
  before="$(jq -c '.hooks // {}' "$SETTINGS")"
  jq --arg ev "$event" --arg cmd "$NODE_CMD" --argjson to "$timeout" --arg m "$matcher" '
    .hooks //= {} |
    .hooks[$ev] //= [] |
    if (.hooks[$ev] | map(.hooks // []) | add // [] | any(.command == $cmd))
    then .
    else
      .hooks[$ev] += [
        (if $m == "" then {} else {matcher: $m} end)
        + {hooks: [ {type: "command", command: $cmd, timeout: $to} ]}
      ]
    end
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  after="$(jq -c '.hooks // {}' "$SETTINGS")"
  if [ "$before" = "$after" ]; then
    warn "$event 已存在，跳过"
  else
    ok "$event 已写入"
  fi
}

add_hook "Stop"              10 ""
add_hook "PostToolUse"        5 ""
add_hook "PreToolUse"         5 "AskUserQuestion|ExitPlanMode"
add_hook "PermissionRequest"  5 ""

echo "  （已备份原 settings.json 到 ${BAK}）"

# ── 5. 弹测试通知，触发授权 ─────────────────────────────────────
TEST_MSG="通知已开通。若这是你第一次看到，请在弹出的授权里点「允许」。"
if command -v terminal-notifier >/dev/null 2>&1; then
  terminal-notifier -title "vft-kit" -message "$TEST_MSG" -sound Glass >/dev/null 2>&1
else
  osascript -e "display notification \"$TEST_MSG\" with title \"vft-kit\" sound name \"Glass\"" >/dev/null 2>&1
fi
ok "已发送测试通知"

# ── 6. 收尾提示 ─────────────────────────────────────────────────
echo
echo "完成。还需两步："
echo "  1. 若刚才没看到通知：打开「系统设置 › 通知」，允许 terminal-notifier（或「脚本编辑器」）发通知。"
echo "  2. 重启 Claude Code 会话，settings.json 里的 hook 才生效。"
echo
echo "双屏横幅（默认已开）：两块屏会同时弹一张仿原生的横幅，并已「接管」原生系统通知（不再重复弹）。"
echo "  · 想恢复原生通知：编辑 ${CONFIG_PATH}，把 dualScreenBanner.allScreens 改为 false（变成 主屏原生 + 副屏横幅）。"
echo "  · 想彻底关横幅只用原生：把 dualScreenBanner.enabled 改为 false。"
echo "  · 没装 swiftc / 编译失败时：横幅自动不显示，通知退回原生，绝不「零通知」。"
echo
echo "自定义（可选）：编辑 ${CONFIG_PATH}（已填满默认值）即可改文案/声音/图标/开关/横幅；改后需重启会话。"
exit 0
