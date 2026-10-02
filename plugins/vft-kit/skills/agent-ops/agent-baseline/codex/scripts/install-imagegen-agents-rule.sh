#!/usr/bin/env bash
# Install the global instruction that routes image generation requests to codex-imagegen.
set -u

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
AGENTS="${CODEX_AGENTS:-$CODEX_HOME/AGENTS.md}"
START_MARKER='<!-- >>> vft-kit imagegen cli preference >>> -->'
END_MARKER='<!-- <<< vft-kit imagegen cli preference <<< -->'

notice() { printf '  ○ %s\n' "$1"; }
success() { printf '  ✓ %s\n' "$1"; }

write_managed_block() {
  local target_dir tmp mode
  target_dir="$(dirname "$AGENTS")"
  mkdir -p "$target_dir" || return 1
  touch "$AGENTS" || return 1
  mode="$(stat -f '%Lp' "$AGENTS" 2>/dev/null || stat -c '%a' "$AGENTS" 2>/dev/null || printf '600')"
  tmp="$(mktemp "$target_dir/.AGENTS.vft-kit.XXXXXX")" || return 1

  awk -v start="$START_MARKER" -v end="$END_MARKER" '
    $0 == start { managed=1; next }
    managed { if ($0 == end) managed=0; next }
    { lines[++count]=$0 }
    END {
      while (count > 0 && lines[count] == "") count--
      for (i=1; i<=count; i++) print lines[i]
    }
  ' "$AGENTS" > "$tmp" || { rm -f "$tmp"; return 1; }

  cat >> "$tmp" <<'EOF'

<!-- >>> vft-kit imagegen cli preference >>> -->
- 当用户要求生成图片、编辑图片、测试图片生成、出图或生图时，直接使用 `codex-imagegen generate` 或 `codex-imagegen edit` 调用 imagegen CLI/OpenAI API；不要用手写 PNG/SVG/HTML/CSS 占位来冒充图片模型结果。
- 普通生图请求不要先声明“我会走 imagegen skill”、不要先解释环境里是否有内置 `image_gen` 工具、不要先跑 `codex-imagegen --help` 做探测；除非命令失败或用户明确询问流程，否则直接构造 prompt、执行 CLI、检查输出文件并回报路径。
<!-- <<< vft-kit imagegen cli preference <<< -->
EOF

  chmod "$mode" "$tmp" 2>/dev/null || true
  mv "$tmp" "$AGENTS"
}

write_managed_block || {
  notice "写入 $AGENTS 的 imagegen CLI 全局规则失败"
  exit 1
}

success "imagegen CLI 全局规则已写入 $AGENTS"
