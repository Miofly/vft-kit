#!/usr/bin/env bash
# Build (once) and run wxapkg-cli, a CLI wrapper over github.com/wux1an/wxapkg.
#
#   wxapkg.sh paths                         # show detected WeChat package roots
#   wxapkg.sh scan [-grep TEXT] [-json]     # list cached mini programs, newest first
#   wxapkg.sh unpack WXID -o OUT_DIR        # unpack latest cached version to OUT_DIR/WXID
#   wxapkg.sh --rebuild ...                 # force re-pull and rebuild
#   wxapkg.sh selftest                      # build + round-trip a synthetic package
#
# Needs git and go (>= 1.25). Upstream clone and binary live in
# ~/.cache/vft-kit/wxapkg (reusable dependency cache).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${VFT_WXAPKG_CACHE:-$HOME/.cache/vft-kit/wxapkg}"
REPO_DIR="$CACHE_DIR/wux1an-wxapkg"
BIN="$CACHE_DIR/bin/wxapkg-cli"
REPO_URL="https://github.com/wux1an/wxapkg"

build() {
  command -v go >/dev/null || { echo "go not found: brew install go" >&2; exit 1; }
  mkdir -p "$CACHE_DIR/bin"
  if [ ! -d "$REPO_DIR/.git" ]; then
    git clone -q --depth 1 "$REPO_URL" "$REPO_DIR"
  elif [ "${1:-}" = "pull" ]; then
    git -C "$REPO_DIR" pull -q --ff-only || true
  fi
  mkdir -p "$REPO_DIR/cmd/wxapkg-cli"
  cp "$SCRIPT_DIR/wxapkg-cli/main.go" "$REPO_DIR/cmd/wxapkg-cli/main.go"
  (cd "$REPO_DIR" && go build -o "$BIN" ./cmd/wxapkg-cli)
}

selftest() {
  build
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  # Build a minimal plain wxapkg: header BE .. ED, index, one file.
  python3 - "$tmp/test.wxapkg" <<'PY'
import struct, sys
files = [("/app.json", b'{"pages":["pages/index/index"]}'), ("/pages/index/index.wxss", b".a{color:red}")]
index = struct.pack(">I", len(files))
entries = []
for name, _ in files:
    entries.append(name.encode())
index_len = 4 + sum(4 + len(n) + 8 for n in entries)
offset = 14 + index_len
body = b""
for (name, data), n in zip(files, entries):
    index += struct.pack(">I", len(n)) + n + struct.pack(">II", offset + len(body), len(data))
    body += data
header = struct.pack(">BIIIB", 0xBE, 0, index_len, len(body), 0xED)
open(sys.argv[1], "wb").write(header + index + body)
PY
  "$BIN" unpack "$tmp/test.wxapkg" -o "$tmp/out" --no-beautify >/dev/null
  grep -q 'color:red' "$tmp/out/test/pages/index/index.wxss"
  grep -q 'pages/index/index' "$tmp/out/test/app.json"
  echo "selftest ok"
}

case "${1:-}" in
  --rebuild) shift; build pull ;;
  selftest) selftest; exit 0 ;;
  *) [ -x "$BIN" ] || build ;;
esac

exec "$BIN" "$@"
