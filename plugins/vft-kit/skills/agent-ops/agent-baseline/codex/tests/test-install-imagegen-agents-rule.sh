#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SCRIPT="$SKILL_DIR/scripts/install-imagegen-agents-rule.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/.codex"
cat > "$TMP_ROOT/.codex/AGENTS.md" <<'EOF'
# Existing

<!-- >>> vft-kit imagegen cli preference >>> -->
- old rule
<!-- <<< vft-kit imagegen cli preference <<< -->
EOF

CODEX_HOME="$TMP_ROOT/.codex" bash "$INSTALL_SCRIPT" >/tmp/codex-baseline-install-imagegen-agents-rule.out

AGENTS="$TMP_ROOT/.codex/AGENTS.md"
grep -Fq '# Existing' "$AGENTS" || { printf 'FAIL: existing content removed\n' >&2; exit 1; }
grep -Fq 'direct' "$AGENTS" && { printf 'FAIL: unexpected English placeholder\n' >&2; exit 1; }
grep -Fq 'old rule' "$AGENTS" && { printf 'FAIL: old managed block remained\n' >&2; exit 1; }
grep -Fq '直接使用 `codex-imagegen generate` 或 `codex-imagegen edit`' "$AGENTS" || { printf 'FAIL: direct CLI rule missing\n' >&2; exit 1; }
grep -Fq '不要先声明“我会走 imagegen skill”' "$AGENTS" || { printf 'FAIL: no-process-noise rule missing\n' >&2; exit 1; }
grep -Fq '不要先跑 `codex-imagegen --help` 做探测' "$AGENTS" || { printf 'FAIL: no-help-probe rule missing\n' >&2; exit 1; }

printf 'PASS: imagegen AGENTS rule install\n'
