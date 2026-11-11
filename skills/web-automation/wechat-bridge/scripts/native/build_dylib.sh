#!/usr/bin/env bash
# Build the in-process sender dylib.
#
# Arch: build a fat arm64+arm64e dylib. Which one the WeChat process needs is not
# what `lipo -archs` on the app says — Tencent's arm64 slice is signed/run such
# that dyld can demand arm64e at insert time ("have 'arm64', need 'arm64e'").
# Shipping both slices sidesteps the guess; dyld picks by process arch.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$DIR/wechat_send.dylib}"
SLICES=()
for A in arm64 arm64e; do
  if clang -arch "$A" -O2 -dynamiclib -fno-objc-arc \
        -framework Foundation -lpthread \
        -o "$OUT.$A" "$DIR/wechat_send.c" 2>/dev/null; then
    SLICES+=("$OUT.$A")
  else
    echo "skip arch $A (build failed)" >&2
  fi
done
[ ${#SLICES[@]} -gt 0 ] || { echo "no slice built" >&2; exit 2; }
lipo -create "${SLICES[@]}" -output "$OUT"
rm -f "${SLICES[@]}"
codesign --force -s - "$OUT" 2>/dev/null || true
echo "built: $OUT"
file "$OUT"
