#!/usr/bin/env bash
# 清理测试生成的截图。
# 默认清理 Playwright 产物的中央目录（所有 MCP 产物都落这里），而不是当前项目目录——
# 避免误删项目文件、也符合"产物不落项目根"的规范。
#
# 中央目录按优先级取：
#   1. 命令行参数 $1
#   2. 环境变量 FE_TEST_OUTPUT_DIR  ← 本机若把 playwright MCP 的 --output-dir 指到别处，
#      在这里设成同一个路径，两边才对得上（否则截图落 A、清理扫 B，永远清不到）
#   3. $HOME/.claude/playwright（默认）
#
# 用法:
#   cleanup-screenshots.sh            # 清理中央目录里的 test-*/page-* 截图
#   cleanup-screenshots.sh <目录>      # 清理指定目录
#
# 只删命名规范内的截图：test-*.png/jpeg、page-*.png/jpeg（Playwright 默认名）。
# 刻意不递归、不 rm -rf，只删本目录第一层、确定是测试截图的文件。

set -uo pipefail

# 注意：DIR 的默认值必须用 $HOME 而不是 ~ —— `"${1:-~/x}"` 里的 ~ 在双引号中不做波浪号展开，
# 会得到字面量 "~/x"，于是 [ -d ] 恒假、脚本每次都报"目录不存在"然后空转（清理从未生效过）。
DIR="${1:-${FE_TEST_OUTPUT_DIR:-$HOME/.claude/playwright}}"

if [ ! -d "$DIR" ]; then
  echo "目录不存在，跳过清理: $DIR"
  echo "（若截图实际落在别处，用 FE_TEST_OUTPUT_DIR 指到 playwright MCP 的 --output-dir 同一路径）"
  exit 0
fi

shopt -s nullglob
cleaned=0
for f in "$DIR"/test-*.png "$DIR"/test-*.jpeg "$DIR"/test-*.jpg \
         "$DIR"/page-*.png "$DIR"/page-*.jpeg "$DIR"/page-*.jpg; do
  rm -f "$f" && cleaned=$((cleaned + 1))
done
shopt -u nullglob

if [ "$cleaned" -gt 0 ]; then
  echo "已清理 $cleaned 个测试截图（目录: ${DIR}）"
else
  echo "没有找到需要清理的截图（目录: ${DIR}）"
fi
