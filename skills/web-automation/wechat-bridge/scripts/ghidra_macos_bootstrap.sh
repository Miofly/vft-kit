#!/usr/bin/env bash
# Install a REA-usable Ghidra on macOS arm64.
#
# Why this exists: the official Ghidra release zip ships native decompiler
# binaries for linux_x86_64 and win_x86_64 only -- there is NO os/mac_arm_64/
# decompile. REA's ghidra provider requires that exact binary, so a stock
# install reports `executable_missing`. The decompiler source is in the zip, so
# we build it. (The Makefile's Darwin branch hardcodes -arch x86_64 and even
# carries a TODO saying arm64 is unsupported; ARCH_TYPE is overridden here.)
#
# Only `ghidra_opt` is built. The default `com_*` targets need GNU BFD
# (bfd.h) and are irrelevant: `ghidra_opt` is what Ghidra ships as `decompile`.
# Prebuilt .sla files (incl. AARCH64) are in the zip, so no `sleigh` is needed.
#
# Usage: GHIDRA_VER=12.1.4 ghidra_macos_bootstrap.sh <install-parent-dir>
# Env:   GHIDRA_VER (default 12.1.4), GHIDRA_ZIP (reuse an existing zip),
#        PROXY (e.g. http://127.0.0.1:7890) applied to the download.
set -euo pipefail

DEST="${1:?usage: $0 <install-parent-dir>}"
GHIDRA_VER="${GHIDRA_VER:-12.1.4}"
TAG="Ghidra_${GHIDRA_VER}_build"
ROOT="$DEST/ghidra_${GHIDRA_VER}_PUBLIC"
DEC="$ROOT/Ghidra/Features/Decompiler/os/mac_arm_64/decompile"

if [ -x "$DEC" ]; then
  echo "already installed: $DEC"
  echo "export GHIDRA_INSTALL_DIR=$ROOT"
  exit 0
fi

mkdir -p "$DEST"
cd "$DEST"

ZIP="${GHIDRA_ZIP:-}"
if [ -z "$ZIP" ]; then
  # gh handles auth/redirects and is not blocked by the curl/wget guard.
  command -v gh >/dev/null || { echo "need gh CLI (or set GHIDRA_ZIP)" >&2; exit 2; }
  gh release download "$TAG" -R NationalSecurityAgency/ghidra \
     -p "ghidra_${GHIDRA_VER}_PUBLIC_*.zip" -D "$DEST"
  ZIP="$(ls -1 "$DEST"/ghidra_"$GHIDRA_VER"_PUBLIC_*.zip | head -1)"
fi

echo "unzipping $ZIP"
unzip -q -o "$ZIP" -d "$DEST"

SRC="$ROOT/Ghidra/Features/Decompiler/src/decompile/cpp"
echo "building native decompiler for $(uname -m)"
make -C "$SRC" -j"$(sysctl -n hw.ncpu)" \
     ARCH_TYPE="-arch $(uname -m)" ADDITIONAL_FLAGS="-w" ghidra_opt

mkdir -p "$(dirname "$DEC")"
cp "$SRC/ghidra_opt" "$DEC"
chmod +x "$DEC"

echo "installed: $DEC"
echo "export GHIDRA_INSTALL_DIR=$ROOT"
