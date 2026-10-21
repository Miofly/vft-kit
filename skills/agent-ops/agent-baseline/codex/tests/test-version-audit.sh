#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

cat > "$TMP_ROOT/codex" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then
  printf 'codex-cli 0.9.10\n'
  exit 0
fi
exit 1
EOF

cat > "$TMP_ROOT/npm" <<'EOF'
#!/usr/bin/env bash
if [ "${FAKE_NPM_FAIL:-0}" = "1" ]; then
  exit 1
fi
case "$*" in
  *'@openai/codex'*) printf '0.10.0\n' ;;
  *'@colbymchenry/codegraph'*) printf '1.6.0\n' ;;
  *) exit 1 ;;
esac
EOF

cat > "$TMP_ROOT/rtk" <<'EOF'
#!/usr/bin/env bash
printf 'rtk 0.45.0\n'
EOF

cat > "$TMP_ROOT/brew" <<'EOF'
#!/usr/bin/env bash
printf '{"formulae":[{"versions":{"stable":"0.45.0"}}]}\n'
EOF

cat > "$TMP_ROOT/codegraph" <<'EOF'
#!/usr/bin/env bash
printf '1.5.0\n'
EOF

cat > "$TMP_ROOT/code-review-graph" <<'EOF'
#!/usr/bin/env bash
printf 'code-review-graph 2.3.7\n'
EOF

cat > "$TMP_ROOT/git" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

chmod +x "$TMP_ROOT/codex" "$TMP_ROOT/npm" "$TMP_ROOT/git" \
  "$TMP_ROOT/rtk" "$TMP_ROOT/brew" "$TMP_ROOT/codegraph" "$TMP_ROOT/code-review-graph"

cat > "$TMP_ROOT/plugins.json" <<'EOF'
{"installed":[{"name":"demo","pluginId":"demo@demo","version":"1.0.0","enabled":true,"marketplaceName":"demo","source":{"source":"local","path":"/missing/demo"}},{"name":"builtin","pluginId":"builtin@local","version":"9.9.9","enabled":true,"marketplaceName":"local"}]}
EOF

cat > "$TMP_ROOT/marketplaces.json" <<'EOF'
{"marketplaces":[{"name":"demo","root":"/missing","marketplaceSource":{"sourceType":"git","source":"https://github.com/example/missing.git"}},{"name":"local","root":"/missing/local","marketplaceSource":{"sourceType":"local","source":"/missing/local"}}]}
EOF

cat > "$TMP_ROOT/pypi.json" <<'EOF'
{"info":{"version":"2.3.8"}}
EOF

run_audit() {
  CODEX_VERSION_AUDIT_CODEX_BIN="$TMP_ROOT/codex" \
  CODEX_VERSION_AUDIT_NPM_BIN="$TMP_ROOT/npm" \
  CODEX_VERSION_AUDIT_GIT_BIN="$TMP_ROOT/git" \
  CODEX_VERSION_AUDIT_RTK_BIN="$TMP_ROOT/rtk" \
  CODEX_VERSION_AUDIT_BREW_BIN="$TMP_ROOT/brew" \
  CODEX_VERSION_AUDIT_CODEGRAPH_BIN="$TMP_ROOT/codegraph" \
  CODEX_VERSION_AUDIT_CODE_REVIEW_GRAPH_BIN="$TMP_ROOT/code-review-graph" \
  CODEX_VERSION_AUDIT_CODE_REVIEW_GRAPH_PYPI_JSON="$TMP_ROOT/pypi.json" \
  CODEX_VERSION_AUDIT_PLUGIN_LIST_JSON="$TMP_ROOT/plugins.json" \
  CODEX_VERSION_AUDIT_MARKETPLACE_LIST_JSON="$TMP_ROOT/marketplaces.json" \
  CODEX_VERSION_AUDIT_TIMEOUT_MS=200 \
  node "$SKILL_DIR/scripts/check-versions.mjs"
}

output="$(run_audit)"
printf '%s' "$output" | grep -F 'Codex | @openai/codex | 0.9.10 | 0.10.0 | 可更新'
printf '%s' "$output" | grep -F 'CLI | rtk | 0.45.0 | 0.45.0 | 已是最新'
printf '%s' "$output" | grep -F 'CLI | codegraph | 1.5.0 | 1.6.0 | 可更新'
printf '%s' "$output" | grep -F 'CLI | code-review-graph | 2.3.7 | 2.3.8 | 可更新'
printf '%s' "$output" | grep -F '插件 | demo@demo | 1.0.0 | 无法判断 | 无法判断'
if printf '%s' "$output" | grep -F 'builtin@local'; then
  printf 'FAIL: local marketplace plugin should not be audited\n' >&2
  exit 1
fi
printf '%s' "$output" | grep -F 'VERSION_AUDIT_DONE'

failed_output="$(FAKE_NPM_FAIL=1 run_audit)"
printf '%s' "$failed_output" | grep -F 'Codex | @openai/codex | 0.9.10 | 无法判断 | 无法判断'
printf '%s' "$failed_output" | grep -F 'VERSION_AUDIT_DONE'

printf 'PASS: version audit covers external tools and plugins\n'
