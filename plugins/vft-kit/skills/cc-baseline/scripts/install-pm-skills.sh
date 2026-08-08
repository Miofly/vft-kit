#!/usr/bin/env bash
# 安装 pm-skills marketplace 的 9 个 PM 插件（68 skills + 42 链式工作流）。
# 来源：github.com/phuryn/pm-skills（MIT）。可选项——只在用户明确要装时跑。

set -uo pipefail

MARKETPLACE="phuryn/pm-skills"
MARKET_NAME="pm-skills"
PLUGINS=(
  pm-toolkit
  pm-product-strategy
  pm-product-discovery
  pm-market-research
  pm-data-analytics
  pm-marketing-growth
  pm-go-to-market
  pm-execution
  pm-ai-shipping
)

command -v claude >/dev/null 2>&1 || { echo "错误：缺少 claude CLI"; exit 1; }

echo "== 1/2 添加 marketplace: $MARKETPLACE =="
# 已添加过会报错，视作幂等成功（和 ponytail/gsap-skills 同一处理方式）
if claude plugin marketplace add "$MARKETPLACE" 2>&1 | tee /tmp/pm-skills-market.log; then
  echo "  marketplace 就绪"
else
  if grep -qiE 'already|exists' /tmp/pm-skills-market.log; then
    echo "  marketplace 已存在，跳过"
  else
    echo "  ✗ marketplace 添加失败，见上方输出"
    exit 1
  fi
fi

echo
echo "== 2/2 安装 9 个 PM 插件 =="
failed=()
for p in "${PLUGINS[@]}"; do
  printf '  %-24s ' "$p"
  if out=$(claude plugin install "${p}@${MARKET_NAME}" 2>&1); then
    echo "✓"
  elif printf '%s' "$out" | grep -qiE 'already installed'; then
    echo "✓ (已装)"
  else
    echo "✗"
    failed+=("$p")
  fi
done

echo
if [ ${#failed[@]} -eq 0 ]; then
  echo "✓ pm-skills 全部 9 个插件已装。重启 CC 会话生效。"
  echo "  入口命令：/discover /strategy /write-prd /plan-launch /north-star /ship-check"
else
  echo "✗ 以下插件安装失败，可手动重试："
  for p in "${failed[@]}"; do echo "    claude plugin install ${p}@${MARKET_NAME}"; done
  exit 1
fi
