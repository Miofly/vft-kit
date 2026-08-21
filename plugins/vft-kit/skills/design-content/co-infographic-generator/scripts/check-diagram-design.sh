#!/usr/bin/env bash
# 检查 diagram-design 插件是否已安装
# 退出码：0=已安装，1=未安装
set -uo pipefail

INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"

# 方法 1：检查 installed_plugins.json（最快最准）
if [ -f "$INSTALLED_PLUGINS" ]; then
  # 重试 3 次，防止文件正在被写入
  for i in 1 2 3; do
    if node -e "const j=require('$INSTALLED_PLUGINS').plugins||{};process.exit(Object.keys(j).some(k=>k.split('@')[0]==='diagram-design')?0:1)" 2>/dev/null; then
      exit 0
    fi
    # 能解析 JSON 但没找到插件 = 真的没装
    node -e "require('$INSTALLED_PLUGINS')" 2>/dev/null && exit 1
    sleep 0.3
  done
fi

# 方法 2：检查插件缓存目录
if [ -d "$HOME/.claude/plugins/cache/diagram-design" ]; then
  exit 0
fi

# 都没找到 = 未安装
exit 1
