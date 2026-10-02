#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/home/.claude" "$tmp/bin"
cat > "$tmp/bin/code-review-graph" <<'EOF'
#!/bin/sh
echo 'code-review-graph 2.3.7'
EOF
cat > "$tmp/bin/claude" <<'EOF'
#!/bin/sh
if [ "$*" = 'mcp list' ]; then
  echo 'code-review-graph: code-review-graph serve - Connected'
else
  echo '2.1.0'
fi
EOF
chmod +x "$tmp/bin/code-review-graph" "$tmp/bin/claude"

cat > "$tmp/home/.claude.json" <<'EOF'
{"mcpServers":{"code-review-graph":{"command":"code-review-graph","args":["serve"]}}}
EOF
cat > "$tmp/home/.claude/CLAUDE.md" <<'EOF'
## Code Review Graph 优先
所有代码审查（code review）优先用 code-review-graph MCP 获取最小上下文、影响半径和相关测试，再按结果读取源码。首次建立或完整重建图谱用 `code-review-graph build`，日常增量刷新用 `code-review-graph update`，检查图谱状态用 `code-review-graph status`。
EOF

output="$(HOME="$tmp/home" PATH="$tmp/bin:$PATH" bash "$DIR/check.sh" --health 2>&1 || true)"
printf '%s' "$output" | grep -q '✓.*code-review-graph (code-review-graph 2.3.7)'
printf '%s' "$output" | grep -q '✓.*code-review-graph MCP'
printf '%s' "$output" | grep -q '✓.*Code Review Graph 优先规范'
printf '%s' "$output" | grep -q '✓.*code-review-graph 已连接'

grep -Fq 'pipx install code-review-graph' "$DIR/check.sh"
grep -Fq 'claude mcp add code-review-graph -s user -- code-review-graph serve' "$DIR/check.sh"
! grep -Fq 'mcp__code-review-graph__*' "$DIR/check.sh"

echo 'PASS: code-review-graph Claude baseline'
