#!/bin/bash
# 把 cc-helper 打包成 macOS .app(LSUIElement 无 Dock 图标),ad-hoc 签名。
# 产物:dist/cc-helper.app  —— 可双击启动、可被 SMAppService 注册为登录项。
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/dist/cc-helper.app"
VERSION="${1:-0.1.0}"

echo "▸ 编译 release…"
swift build -c release

BIN="$ROOT/.build/release/cc-helper"
[ -x "$BIN" ] || { echo "✗ 未找到可执行文件 $BIN"; exit 1; }

echo "▸ 组装 $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/cc-helper"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>cc-helper</string>
    <key>CFBundleDisplayName</key><string>cc-helper</string>
    <key>CFBundleIdentifier</key><string>com.wfly.cc-helper</string>
    <key>CFBundleExecutable</key><string>cc-helper</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "▸ ad-hoc 签名…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (签名跳过/失败,本地仍可运行)"

echo "✓ 完成: $APP"
echo "  启动: open \"$APP\"   或双击"
