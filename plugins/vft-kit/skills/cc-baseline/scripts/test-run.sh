#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf '%s\n' '#!/usr/bin/env bash' 'printf "caveman\n" >> "$TEST_LOG"' > "$tmp/caveman.sh"
printf '%s\n' '#!/usr/bin/env bash' 'printf "check:%s\n" "$*" >> "$TEST_LOG"' 'exit 7' > "$tmp/check.sh"
chmod +x "$tmp/caveman.sh" "$tmp/check.sh"

set +e
TEST_LOG="$tmp/log" CAVEMAN_SCRIPT="$tmp/caveman.sh" CHECK_SCRIPT="$tmp/check.sh" bash "$DIR/run.sh" --health
status=$?
set -e

[ "$status" -eq 7 ] || { printf 'FAIL: checker exit code not propagated\n' >&2; exit 1; }
[ "$(sed -n '1p' "$tmp/log")" = 'caveman' ] || { printf 'FAIL: Caveman installer did not run first\n' >&2; exit 1; }
[ "$(sed -n '2p' "$tmp/log")" = 'check:--health' ] || { printf 'FAIL: checker args not forwarded\n' >&2; exit 1; }

printf 'PASS: CC baseline run enables Caveman before checking\n'
