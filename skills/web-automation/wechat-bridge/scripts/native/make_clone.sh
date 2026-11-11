#!/usr/bin/env bash
# Create a re-signed WeChat clone that loads wechat_send.dylib, and launch it.
#
# No load-command patching and no debugger: an ad-hoc signed (non-hardened) copy
# honours DYLD_INSERT_LIBRARIES. The clone has its own bundle id and its own
# chat data; the user's main WeChat is untouched.
#
# Usage: make_clone.sh [SRC_APP] [CLONE_APP] [DYLIB]
set -euo pipefail
SRC="${1:-/Applications/WeChat.app}"
CLONE="${2:-$HOME/Applications/WeChatSend.app}"
DYLIB="${3:-$(cd "$(dirname "$0")" && pwd)/wechat_send.dylib}"
BUNDLE_ID="${WXS_CLONE_BUNDLE_ID:-com.tencent.xinWeChat.send}"

[ -x "$DYLIB" ] || { echo "dylib not built: $DYLIB (run build_dylib.sh)" >&2; exit 2; }
[ -d "$SRC" ] || { echo "no such app: $SRC" >&2; exit 2; }
if [ -d "$CLONE" ]; then echo "clone exists: $CLONE (delete it first to recreate)" >&2; exit 2; fi

mkdir -p "$(dirname "$CLONE")"
ditto "$SRC" "$CLONE"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CLONE/Contents/Info.plist"

ENT="$(mktemp -t wxs-ent).plist"
cat > "$ENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.get-task-allow</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict></plist>
PLIST

echo "signing $CLONE (ad-hoc + get-task-allow, no hardened runtime)"
codesign --force --deep --sign - --entitlements "$ENT" "$CLONE"
codesign -d --entitlements - "$CLONE" 2>&1 | head -5

echo
echo "launching with DYLD_INSERT_LIBRARIES=$DYLIB"
echo "first run: scan the QR code to log this clone in."
# -u __CFBundleIdentifier: launcher (Claude Code / Orca) sets it to the host app
#   id, which makes AppKit resolve localizations against that host -> English UI.
# -u LANG/LC_*: same reason; without this the clone comes up in English.
env -u __CFBundleIdentifier -u __CF_USER_TEXT_ENCODING -u LANG -u LC_ALL -u LC_CTYPE \
    DYLD_INSERT_LIBRARIES="$DYLIB" nohup "$CLONE/Contents/MacOS/WeChat" >/tmp/wxs_clone.log 2>&1 &
echo "sender socket: ${WXS_SOCKET:-/tmp/wechat_send.sock}"
echo 'try: printf "%s" "hello" | nc -U /tmp/wechat_send.sock'
