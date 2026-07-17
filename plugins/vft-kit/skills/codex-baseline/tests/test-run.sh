#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SCRIPT="$SKILL_DIR/scripts/run.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

cat > "$TMP_ROOT/sync-fails.sh" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
cat > "$TMP_ROOT/check-fails.sh" <<'EOF'
#!/usr/bin/env bash
printf 'check-ran\n'
exit 23
EOF
chmod +x "$TMP_ROOT/sync-fails.sh" "$TMP_ROOT/check-fails.sh"

set +e
output="$(SYNC_SCRIPT="$TMP_ROOT/sync-fails.sh" CHECK_SCRIPT="$TMP_ROOT/check-fails.sh" bash "$RUN_SCRIPT" 2>&1)"
status=$?
set -e

[ "$status" -eq 23 ] || { printf 'FAIL: expected checker status 23, got %s\n' "$status" >&2; exit 1; }
grep -Fq 'check-ran' <<< "$output" || { printf 'FAIL: checker did not run\n' >&2; exit 1; }
grep -Fq '同步异常' <<< "$output" || { printf 'FAIL: sync warning absent\n' >&2; exit 1; }

printf 'PASS: run orchestration\n'
