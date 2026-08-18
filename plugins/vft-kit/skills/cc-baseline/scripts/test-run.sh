#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf '%s\n' '#!/usr/bin/env bash' 'printf "caveman\n" >> "$TEST_LOG"' > "$tmp/caveman.sh"
printf '%s\n' '#!/usr/bin/env bash' 'printf "rtk\n" >> "$TEST_LOG"' > "$tmp/rtk.sh"
printf '%s\n' '#!/usr/bin/env bash' 'printf "check:%s\n" "$*" >> "$TEST_LOG"' 'exit 7' > "$tmp/check.sh"
chmod +x "$tmp/rtk.sh" "$tmp/caveman.sh" "$tmp/check.sh"

set +e
TEST_LOG="$tmp/log" RTK_SCRIPT="$tmp/rtk.sh" CAVEMAN_SCRIPT="$tmp/caveman.sh" CHECK_SCRIPT="$tmp/check.sh" bash "$DIR/run.sh" --health
status=$?
set -e

[ "$status" -eq 7 ] || { printf 'FAIL: checker exit code not propagated\n' >&2; exit 1; }
[ "$(sed -n '1p' "$tmp/log")" = 'rtk' ] || { printf 'FAIL: RTK installer did not run first\n' >&2; exit 1; }
[ "$(sed -n '2p' "$tmp/log")" = 'caveman' ] || { printf 'FAIL: Caveman installer did not run second\n' >&2; exit 1; }
[ "$(sed -n '3p' "$tmp/log")" = 'check:--health' ] || { printf 'FAIL: checker args not forwarded\n' >&2; exit 1; }

printf 'PASS: CC baseline run installs RTK and enables Caveman before checking\n'
