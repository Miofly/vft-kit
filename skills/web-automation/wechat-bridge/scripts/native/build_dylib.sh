#!/usr/bin/env bash
# Build to a NEW output path; never replace an image mapped by a logged-in clone.
# Both slices are retained for the observed arm64/arm64e loader requirements.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:?Usage: build_dylib.sh /absolute/path/to/NEW-wechat_send.dylib}"
[[ "$OUT" = /* ]] || { printf 'output must be an absolute path\n' >&2; exit 2; }
[[ ! -e "$OUT" && ! -L "$OUT" ]] || { printf 'output exists; choose a new path\n' >&2; exit 2; }
TMP="$(mktemp -d "${OUT%/*}/.wxs-build.XXXXXX")"
trap 'rm -f "$TMP/arm64.dylib" "$TMP/arm64e.dylib" "$TMP/universal.dylib"; rmdir "$TMP"' EXIT
for ARCH in arm64 arm64e; do
  clang -arch "$ARCH" -O2 -Wall -Wextra -Werror -Wno-unused-function -dynamiclib \
    -framework Foundation -lpthread -o "$TMP/$ARCH.dylib" "$DIR/wechat_send.c"
done
lipo -create "$TMP/arm64.dylib" "$TMP/arm64e.dylib" -output "$TMP/universal.dylib"
codesign --force --sign - "$TMP/universal.dylib"
codesign --verify --strict "$TMP/universal.dylib"
# Staging lives on the destination filesystem; link refuses an existing path.
ln "$TMP/universal.dylib" "$OUT"
printf 'built (probe-only; not loaded): %s\n' "$OUT"
file "$OUT"
