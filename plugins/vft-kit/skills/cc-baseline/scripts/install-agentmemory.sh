#!/usr/bin/env bash
# 自动安装 agentmemory 作为必装 MCP 服务器。
# agentmemory 提供跨会话持久化记忆：自动捕获观察、压缩合并、混合检索、上下文注入。
# 架构：基于 iii engine，12 个生命周期 Hook，BM25 + Vector + Graph 混合检索。

set -euo pipefail

CLAUDE_JSON="$HOME/.claude.json"
SETTINGS="$HOME/.claude/settings.json"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
DATA_DIR="$HOME/Library/Application Support/agentmemory"

c_g=$'\033[32m'; c_r=$'\033[31m'; c_y=$'\033[33m'; c_d=$'\033[2m'; c_0=$'\033[0m'

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "${c_r}错误：缺少命令 $1${c_0}"
    return 1
  }
}

# 检查 agentmemory 是否已在 MCP 配置中注册
mcp_registered() {
  [ -f "$CLAUDE_JSON" ] || return 1
  node -e "
    const j = require('$CLAUDE_JSON');
    const servers = j.mcpServers || {};
    if (servers.agentmemory) process.exit(0);
    for (const proj in (j.projects || {})) {
      const s = j.projects[proj].mcpServers;
      if (s && s.agentmemory) process.exit(0);
    }
    process.exit(1);
  " 2>/dev/null
}

# 全局 CLAUDE.md 是否含 agentmemory 调用规范
claudemd_has_agentmemory() {
  [ -f "$CLAUDE_MD" ] || return 1
  grep -Eiq 'agentmemory|记忆.*agentmemory|持久化记忆' "$CLAUDE_MD"
}

# 注册 agentmemory 到 ~/.claude.json (user scope)
register_mcp() {
  echo "正在注册 agentmemory MCP 到 Claude Code..."

  local tmp_file
  tmp_file="$(mktemp)"

  node -e "
    const fs = require('fs');
    const path = '$CLAUDE_JSON';
    let config = {};

    if (fs.existsSync(path)) {
      config = JSON.parse(fs.readFileSync(path, 'utf8'));
    }

    config.mcpServers = config.mcpServers || {};
    config.mcpServers.agentmemory = {
      command: 'npx',
      args: ['@agentmemory/agentmemory', 'mcp'],
      env: {}
    };

    fs.writeFileSync('$tmp_file', JSON.stringify(config, null, 2));
  " || {
    echo "${c_r}错误：注册 MCP 失败${c_0}"
    rm -f "$tmp_file"
    return 1
  }

  mv "$tmp_file" "$CLAUDE_JSON"
  echo "${c_g}✓ agentmemory MCP 已注册到 $CLAUDE_JSON${c_0}"
}

# 追加 agentmemory 使用规范到全局 CLAUDE.md
ensure_agentmemory_instruction() {
  mkdir -p "$(dirname "$CLAUDE_MD")"
  touch "$CLAUDE_MD"

  if claudemd_has_agentmemory; then
    return 0
  fi

  cat >> "$CLAUDE_MD" <<'EOF'

## agentmemory 持久化记忆（自动管理跨会话记忆）

**agentmemory 已安装并自动工作**，无需手动调用。通过 12 个生命周期 Hook 自动捕获所有交互，定时压缩成结构化记忆，会话启动时自动注入相关上下文（~1900 tokens）。

### 自动工作的部分（零手动操作）
- **SessionStart** - 会话启动时自动注入相关记忆
- **UserPromptSubmit** - 用户提问时自动记录
- **PreToolUse / PostToolUse** - 工具调用前后自动捕获
- **SessionEnd** - 会话结束时生成摘要
- **后台压缩** - 定时自动压缩相似观察为结构化记忆

### 需要主动调用的场景（通过 MCP 工具）
1. **强制保存重要信息** - 用户说"记住xx"时，调用 `remember` 工具
2. **主动检索历史** - 用户问"之前怎么xx"时，调用 `recall` 工具
3. **生成会话摘要** - 用户说"总结一下"时，调用 `recap` 工具
4. **删除过时记忆** - 用户说"忘掉xx"时，调用 `forget` 工具
5. **跨 Agent 交接** - 多 Agent 场景交接上下文时，调用 `handoff` 工具

### 数据存储
- 位置：`~/Library/Application Support/agentmemory`（macOS）
- 与现有 `~/.claude/projects/.../memory/` 文件系统并存
- memory 文件存决策和规范，agentmemory 存细节和上下文

### 注意事项
- agentmemory 服务必须在后台运行（`npx @agentmemory/agentmemory` 已通过 MCP 自动启动）
- 修改配置后需重启 Claude Code 会话
- 使用本地 embeddings（all-MiniLM-L6-v2）时零成本，使用 OpenAI embeddings 约 $10/年
EOF

  echo "${c_g}✓ 已追加 agentmemory 使用规范到 $CLAUDE_MD${c_0}"
}

# 创建数据目录（首次安装）
ensure_data_dir() {
  if [ ! -d "$DATA_DIR" ]; then
    mkdir -p "$DATA_DIR"
    echo "${c_g}✓ 已创建 agentmemory 数据目录：$DATA_DIR${c_0}"
  fi
}

# 测试 agentmemory 包是否可访问（不实际安装，只验证可达性）
test_package_availability() {
  echo "正在验证 @agentmemory/agentmemory 包..."

  if npm view @agentmemory/agentmemory version >/dev/null 2>&1; then
    echo "${c_g}✓ @agentmemory/agentmemory 包可访问${c_0}"
    return 0
  else
    echo "${c_y}警告：无法访问 npm registry，可能需要代理${c_0}"
    return 1
  fi
}

# 主流程
main() {
  need_cmd node
  need_cmd npm
  need_cmd npx

  echo "${c_d}=== agentmemory 安装 ===${c_0}"

  # 1. 测试包可达性
  test_package_availability || echo "${c_y}继续安装，运行时会通过 npx 自动下载${c_0}"

  # 2. 创建数据目录
  ensure_data_dir

  # 3. 注册 MCP
  if mcp_registered; then
    echo "${c_g}✓ agentmemory MCP 已注册，跳过${c_0}"
  else
    register_mcp || exit 1
  fi

  # 4. 追加使用规范到全局 CLAUDE.md
  ensure_agentmemory_instruction

  echo ""
  echo "${c_g}===== 安装完成 =====${c_0}"
  echo "MCP 配置：$CLAUDE_JSON"
  echo "数据目录：$DATA_DIR"
  echo "使用规范：$CLAUDE_MD"
  echo ""
  echo "${c_y}重要：重启 Claude Code 会话后 agentmemory 才会生效${c_0}"
  echo ""
  echo "${c_d}agentmemory 将自动：${c_0}"
  echo "  • 捕获所有工具调用和交互"
  echo "  • 定时压缩为结构化记忆"
  echo "  • 会话启动时注入相关上下文"
  echo "  • 与现有 memory 文件系统并存互补"
}

main "$@"
