#!/usr/bin/env bash
# Prepare a re-signed clone offline. Never launch, log in, or replace an existing clone.
#
# No load-command patching and no debugger: an ad-hoc signed (non-hardened) copy
# honours DYLD_INSERT_LIBRARIES. The clone has its own bundle id and its own
# chat data; the user's main WeChat is untouched.
#
# Usage: make_clone.sh [SRC_APP] [CLONE_APP] [DYLIB]
set -euo pipefail
SRC="${1:-/Applications/WeChat.app}"
CLONE="${2:-$HOME/Applications/WeChatSend.app}"
DYLIB="${3:?Pass the absolute path to a separately built dylib}"
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
echo "clone prepared, NOT launched: $CLONE"
echo "probe-only dylib: $DYLIB"
echo "Keep an already-logged-in clone running; this script never initiates login."
echo "Use the external wechat_probe tool for read-only inspection before any launch change."
