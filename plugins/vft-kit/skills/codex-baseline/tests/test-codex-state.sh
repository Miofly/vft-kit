#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SKILL_DIR/scripts/inspect-codex-state.mjs"

printf '%s' '{"name":"context7","enabled":true,"transport":{"type":"streamable_http","url":"https://example.com"}}' |
  node "$SCRIPT" mcp-present
printf '%s' '{"name":"context7","enabled":true,"transport":{"type":"streamable_http","url":"https://example.com"}}' |
  node "$SCRIPT" mcp-enabled

set +e
printf '%s' '{"name":"context7","enabled":false,"transport":{"type":"stdio","command":"npx"}}' |
  node "$SCRIPT" mcp-enabled
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: disabled MCP should fail enabled check\n' >&2; exit 1; }

printf '%s' '{"installed":[{"pluginId":"ponytail@ponytail","installed":true,"enabled":true}]}' |
  node "$SCRIPT" plugin-enabled ponytail@ponytail

set +e
printf '%s' '{"installed":[]}' | node "$SCRIPT" plugin-enabled ponytail@ponytail
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: absent plugin should fail\n' >&2; exit 1; }

printf 'PASS: codex state parser\n'
