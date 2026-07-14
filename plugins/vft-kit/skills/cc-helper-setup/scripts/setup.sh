#!/bin/bash
# cc-helper-setup —— 安装预编译的 cc-helper.app(无需源码/工具链)。
# vft-kit 里存的是编译好的成品 zip;安装 = 解压 → 去隔离 → 装到 ~/Applications → 启动。
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  PLUGIN_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fi
ZIP="$PLUGIN_ROOT/apps/cc-helper/cc-helper.app.zip"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/cc-helper.app"

echo "▸ 环境检查"
if [ "$(uname)" != "Darwin" ]; then
  echo "✗ cc-helper 仅支持 macOS"; exit 1
fi
if [ "$(uname -m)" != "arm64" ]; then
  echo "⚠ 预编译成品是 Apple Silicon(arm64)。你是 $(uname -m),可能无法运行。"
  echo "  需要 Intel 版请找源码(私有 vft-ai/apps/cc-helper)自行 swift build。"
fi
if [ ! -f "$ZIP" ]; then
  echo "✗ 未找到成品 $ZIP"; exit 1
fi

echo "▸ 解压成品"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ditto -x -k "$ZIP" "$TMP"
BUILT="$TMP/cc-helper.app"
[ -d "$BUILT" ] || { echo "✗ 解压后未见 cc-helper.app"; exit 1; }

echo "▸ 去除隔离属性(ad-hoc 签名的成品,Gatekeeper 会拦)"
xattr -dr com.apple.quarantine "$BUILT" 2>/dev/null || true

echo "▸ 安装到 $DEST_APP"
mkdir -p "$DEST_DIR"
pkill -f "cc-helper.app/Contents/MacOS/cc-helper" 2>/dev/null || true
sleep 1
rm -rf "$DEST_APP"
cp -R "$BUILT" "$DEST_APP"
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

echo "▸ 启动"
open "$DEST_APP"

cat <<'DONE'

✓ cc-helper 已安装并启动。

接数据(两步):
  1) 菜单栏点 ⚙ 设置… → 「数据管道」页:
       · 安装 / 更新 statusLine wrapper   (接实时用量)
       · 安装 / 更新 通知 hook            (接任务通知)
  2) 重开一个 Claude Code 会话 生效。

提示:菜单栏若没看到用量项,多半是当前前台 App 菜单太长把状态项挤掉了,
      切到菜单短的 App 就会显示(macOS 菜单栏溢出机制,非故障)。
      想开机自启:设置 → 通用 → 勾「开机自启」。
DONE
