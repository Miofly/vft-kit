#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$DIR")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/home/.claude" "$tmp/bin"
printf '%s\n' '#!/bin/sh' 'echo codegraph 1.5.0' > "$tmp/bin/codegraph"
chmod +x "$tmp/bin/codegraph"
cat > "$tmp/home/.claude/CLAUDE.md" <<'EOF'
## CodeGraph 自动初始化
新代码项目没有 .codegraph 时自动运行 codegraph init；旧索引用 codegraph update 或 codegraph init --force。
EOF

output="$(HOME="$tmp/home" PATH="$tmp/bin:$PATH" bash "$DIR/check.sh" 2>&1 || true)"
printf '%s' "$output" | grep -q '✗.*CodeGraph 自动初始化规范'
printf '%s' "$output" | grep -q 'codegraph sync'
printf '%s' "$output" | grep -q 'codegraph index -f'
printf '%s' "$output" | grep -q 'sed -i.bak'

! grep -q 'volta list all.*@colbymchenry/codegraph' "$DIR/check.sh"
! grep -q 'codegraph.*volta install @colbymchenry/codegraph' "$DIR/check.sh"
! grep -Fq 'codegraph update' "$DIR/check.sh" "$SKILL_DIR/SKILL.md" "$SKILL_DIR/CHANGELOG-codegraph-auto-init.md"
! grep -Fq 'codegraph init --force' "$DIR/check.sh" "$SKILL_DIR/SKILL.md" "$SKILL_DIR/CHANGELOG-codegraph-auto-init.md"

echo 'PASS: CodeGraph v1.5 baseline'
