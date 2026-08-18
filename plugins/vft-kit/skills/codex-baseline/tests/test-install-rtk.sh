#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/brew" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_LOG"
printf '%s\n' '#!/usr/bin/env bash' 'printf "rtk test\n"' > "$FAKE_RTK"
chmod +x "$FAKE_RTK"
EOF
chmod +x "$tmp/bin/brew"

PATH="$tmp/bin:/usr/bin:/bin" TEST_LOG="$tmp/brew.log" FAKE_RTK="$tmp/bin/rtk" bash "$SKILL_DIR/scripts/install-rtk.sh"
PATH="$tmp/bin:/usr/bin:/bin" TEST_LOG="$tmp/brew.log" FAKE_RTK="$tmp/bin/rtk" bash "$SKILL_DIR/scripts/install-rtk.sh"

[ "$(wc -l < "$tmp/brew.log" | tr -d ' ')" = 1 ] || { printf 'FAIL: Homebrew should run exactly once\n' >&2; exit 1; }
[ "$(cat "$tmp/brew.log")" = 'install rtk' ] || { printf 'FAIL: wrong Homebrew command\n' >&2; exit 1; }
printf 'PASS: RTK is installed when missing and skipped when present\n'
