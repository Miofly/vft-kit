#!/bin/bash
# cc-helper-setup —— 构建内嵌的 cc-helper 源码为 .app 并安装到 ~/Applications。
# 仅 macOS,需 Swift 工具链。
set -euo pipefail

# 定位:优先用 CLAUDE_PLUGIN_ROOT,回退按脚本相对路径
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  PLUGIN_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fi
APP_SRC="$PLUGIN_ROOT/apps/cc-helper"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/cc-helper.app"

echo "▸ 环境检查"
if [ "$(uname)" != "Darwin" ]; then
  echo "✗ cc-helper 仅支持 macOS"; exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
  echo "✗ 未找到 swift。请先装 Xcode 命令行工具:  xcode-select --install"; exit 1
fi
if [ ! -f "$APP_SRC/Package.swift" ]; then
  echo "✗ 未找到源码 $APP_SRC/Package.swift"; exit 1
fi

echo "▸ 编译 + 打包 .app(首次较慢)"
bash "$APP_SRC/scripts/build-app.sh" 0.1.0

BUILT="$APP_SRC/dist/cc-helper.app"
[ -d "$BUILT" ] || { echo "✗ 打包失败,未生成 $BUILT"; exit 1; }

echo "▸ 安装到 $DEST_APP"
mkdir -p "$DEST_DIR"
# 若已在运行,先退出旧实例
pkill -f "cc-helper.app/Contents/MacOS/cc-helper" 2>/dev/null || true
sleep 1
rm -rf "$DEST_APP"
cp -R "$BUILT" "$DEST_APP"

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
