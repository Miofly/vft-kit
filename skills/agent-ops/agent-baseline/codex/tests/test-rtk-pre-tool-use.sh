#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$SKILL_DIR/scripts/rtk-pre-tool-use.mjs"
NODE_BIN="$(node -p 'process.execPath')"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/rtk"
chmod +x "$tmp/rtk"

run_hook() {
  local command="$1"
  "$NODE_BIN" -e 'process.stdout.write(JSON.stringify({hook_event_name:"PreToolUse",tool_name:"exec_command",tool_input:{command:process.argv[1],timeout_ms:123}}))' "$command" |
    PATH="$tmp:/usr/bin:/bin" "$NODE_BIN" "$HOOK"
}

assert_wrapped() {
  local command="$1" expected="$2" output
  output="$(run_hook "$command")"
  [ -n "$output" ] || { printf 'FAIL: expected wrapped command: %s\n' "$command" >&2; exit 1; }
  "$NODE_BIN" -e '
    const value = JSON.parse(process.argv[1]).hookSpecificOutput;
    if (value.updatedInput.command !== process.argv[2] || value.updatedInput.timeout_ms !== 123) process.exit(1);
  ' "$output" "$expected" || { printf 'FAIL: wrong rewrite: %s\n' "$command" >&2; exit 1; }
}

assert_skipped() {
  local command="$1" output
  output="$(run_hook "$command")"
  [ -z "$output" ] || { printf 'FAIL: unsafe command was wrapped: %s\n' "$command" >&2; exit 1; }
}

assert_wrapped 'git status --short' 'rtk git status --short'
assert_wrapped 'git diff -- README.md' 'rtk git diff -- README.md'
assert_wrapped 'git log -3 --oneline' 'rtk git log -3 --oneline'
assert_wrapped 'rg TODO src' 'rtk rg TODO src'
assert_wrapped 'ls -la' 'rtk ls -la'

assert_skipped 'find .. -name AGENTS.md -o -name AGENTS.override.md'
assert_skipped 'git status --short | jq .'
assert_skipped 'git diff > patch.txt'
assert_skipped 'git status && echo done'
assert_skipped 'git diff --check'
assert_skipped 'git status --porcelain=v1'
assert_skipped 'rg --json TODO src'
assert_skipped 'rg --files'
assert_skipped 'printf hello'
assert_skipped 'rtk git status --short'

without_rtk="$(
  "$NODE_BIN" -e 'process.stdout.write(JSON.stringify({hook_event_name:"PreToolUse",tool_input:{command:"git status"}}))' |
    PATH="/usr/bin:/bin" "$NODE_BIN" "$HOOK"
)"
[ -z "$without_rtk" ] || { printf 'FAIL: missing RTK must leave command unchanged\n' >&2; exit 1; }

printf 'not-json' | PATH="$tmp:/usr/bin:/bin" "$NODE_BIN" "$HOOK" >/dev/null
printf 'PASS: RTK hook wraps only safe human-readable commands\n'
