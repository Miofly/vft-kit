#!/usr/bin/env bash
set -euo pipefail

if ! command -v rtk >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    printf '  ✗ RTK 缺失且 Homebrew 不可用，无法自动安装\n' >&2
    exit 1
  fi

  brew install rtk
  command -v rtk >/dev/null 2>&1 || {
    printf '  ✗ Homebrew 执行完成，但仍未找到 RTK\n' >&2
    exit 1
  }
fi

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
if [ -n "${CODEX_AGENTS:-}" ]; then
  AGENTS="$CODEX_AGENTS"
elif [ -f "$CODEX_HOME/AGENTS.override.md" ]; then
  AGENTS="$CODEX_HOME/AGENTS.override.md"
else
  AGENTS="$CODEX_HOME/AGENTS.md"
fi
START_MARKER='<!-- >>> vft-kit rtk safe shell usage >>> -->'
END_MARKER='<!-- <<< vft-kit rtk safe shell usage <<< -->'

target_dir="$(dirname "$AGENTS")"
mkdir -p "$target_dir"
touch "$AGENTS"
start_count="$(grep -Fc "$START_MARKER" "$AGENTS" || true)"
end_count="$(grep -Fc "$END_MARKER" "$AGENTS" || true)"
if [ "$start_count" -ne "$end_count" ] || [ "$start_count" -gt 1 ]; then
  printf '  ✗ %s 的 RTK 托管块标记异常，未改写文件\n' "$AGENTS" >&2
  exit 1
fi

mode="$(stat -f '%Lp' "$AGENTS" 2>/dev/null || stat -c '%a' "$AGENTS" 2>/dev/null || printf '600')"
tmp="$(mktemp "$target_dir/.AGENTS.rtk.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

awk -v start="$START_MARKER" -v end="$END_MARKER" '
  $0 == start { managed=1; next }
  managed { if ($0 == end) managed=0; next }
  /^@.*\/RTK\.md[[:space:]]*$/ { next }
  { lines[++count]=$0 }
  END {
    while (count > 0 && lines[count] == "") count--
    for (i=1; i<=count; i++) print lines[i]
  }
' "$AGENTS" > "$tmp"

cat >> "$tmp" <<'EOF'

<!-- >>> vft-kit rtk safe shell usage >>> -->
## RTK 安全使用

- RTK 是受限使用的输出压缩器，不是 Shell 通用前缀。命令同时满足以下条件时必须使用 `rtk <command> ...`：属于 `rtk --help` 明确支持的子命令；没有 Shell 复合语法；输出只供人阅读；压缩不影响验收。常见适用命令包括 `git status`、`git diff`、`git log`、`rg`、`ls` 和受支持的测试命令。
- 以下情况直接运行原生命令，不加 RTK：Shell 内建或 RTK 未支持的命令；复杂 `find`；含管道、重定向、`&&`、`||`、`;` 的命令；stdout 会交给 `jq`、脚本或文件继续处理；需要完整原始输出；会生成或改写文件的命令。
- RTK 返回 usage、unsupported、参数解析或兼容性错误时，立即用原生命令重试一次。业务命令自身的非零退出码按原错误处理，不因使用 RTK 而吞掉失败。
<!-- <<< vft-kit rtk safe shell usage <<< -->
EOF

chmod "$mode" "$tmp" 2>/dev/null || true
mv "$tmp" "$AGENTS"
printf '  ✓ RTK 已安装（%s），安全规则已写入 %s\n' "$(rtk --version 2>/dev/null)" "$AGENTS"
