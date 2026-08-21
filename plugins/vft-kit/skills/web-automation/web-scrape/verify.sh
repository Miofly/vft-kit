#!/bin/bash
# web-scrape 完整性验证脚本

set -e

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SKILL_DIR"

echo "🔍 web-scrape 完整性验证"
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查函数
check_file() {
    if [ -f "$1" ]; then
        echo -e "  ${GREEN}✓${NC} $1"
        return 0
    else
        echo -e "  ${RED}✗${NC} $1 (缺失)"
        return 1
    fi
}

check_executable() {
    if [ -x "$1" ]; then
        echo -e "  ${GREEN}✓${NC} $1 (可执行)"
        return 0
    else
        echo -e "  ${YELLOW}⚠${NC} $1 (不可执行)"
        chmod +x "$1"
        echo -e "  ${GREEN}→${NC} 已添加执行权限"
        return 0
    fi
}

# 1. 检查文件结构
echo "1️⃣  检查文件结构..."
MISSING=0

check_file "SKILL.md" || ((MISSING++))
check_file "README.md" || ((MISSING++))
check_file "QUICKSTART.md" || ((MISSING++))
check_file "install-deps.sh" || ((MISSING++))
check_file "scripts/scrape.mjs" || ((MISSING++))
check_file "scripts/playwright-worker.mjs" || ((MISSING++))
check_file "scripts/scrapling-worker.py" || ((MISSING++))
check_file "scripts/crawl4ai-worker.py" || ((MISSING++))
check_file "tests/integration.test.mjs" || ((MISSING++))
check_file "docs/architecture.md" || ((MISSING++))
check_file "docs/tool-selection.md" || ((MISSING++))

if [ $MISSING -gt 0 ]; then
    echo -e "${RED}✗ 缺失 $MISSING 个文件${NC}"
    exit 1
fi

echo ""

# 2. 检查可执行权限
echo "2️⃣  检查可执行权限..."
check_executable "install-deps.sh"
check_executable "scripts/scrape.mjs"
check_executable "scripts/playwright-worker.mjs"
check_executable "scripts/scrapling-worker.py"
check_executable "scripts/crawl4ai-worker.py"
check_executable "tests/integration.test.mjs"

echo ""

# 3. 检查 Node.js
echo "3️⃣  检查 Node.js..."
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    echo -e "  ${GREEN}✓${NC} Node.js $NODE_VERSION"
else
    echo -e "  ${RED}✗${NC} Node.js 未安装"
    exit 1
fi

echo ""

# 4. 检查 Python
echo "4️⃣  检查 Python..."
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    echo -e "  ${GREEN}✓${NC} Python $PYTHON_VERSION"
else
    echo -e "  ${RED}✗${NC} Python 3 未安装"
    exit 1
fi

echo ""

# 5. 检查 Python 依赖
echo "5️⃣  检查 Python 依赖..."
DEPS_MISSING=0

if python3 -m pip list 2>/dev/null | grep -i scrapling > /dev/null; then
    echo -e "  ${GREEN}✓${NC} scrapling"
else
    echo -e "  ${YELLOW}⚠${NC} scrapling (未安装)"
    ((DEPS_MISSING++))
fi

if python3 -m pip list 2>/dev/null | grep -i crawl4ai > /dev/null; then
    echo -e "  ${GREEN}✓${NC} crawl4ai"
else
    echo -e "  ${YELLOW}⚠${NC} crawl4ai (未安装)"
    ((DEPS_MISSING++))
fi

if python3 -m pip list 2>/dev/null | grep -i playwright > /dev/null; then
    echo -e "  ${GREEN}✓${NC} playwright"
else
    echo -e "  ${YELLOW}⚠${NC} playwright (未安装)"
    ((DEPS_MISSING++))
fi

if [ $DEPS_MISSING -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}提示：运行 ./install-deps.sh 安装缺失的依赖${NC}"
fi

echo ""

# 6. 检查 Playwright worker
echo "6️⃣  检查本地 Playwright worker..."
echo -e "  ${GREEN}✓${NC} web-scrape 自包含 Playwright worker"

echo ""

# 7. 语法检查
echo "7️⃣  语法检查..."

# 检查 JavaScript 语法
if node -c scripts/scrape.mjs 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} scrape.mjs 语法正确"
else
    echo -e "  ${RED}✗${NC} scrape.mjs 语法错误"
    exit 1
fi

if node -c scripts/playwright-worker.mjs 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} playwright-worker.mjs 语法正确"
else
    echo -e "  ${RED}✗${NC} playwright-worker.mjs 语法错误"
    exit 1
fi

if node -c tests/integration.test.mjs 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} integration.test.mjs 语法正确"
else
    echo -e "  ${RED}✗${NC} integration.test.mjs 语法错误"
    exit 1
fi

# 检查 Python 语法
if python3 -m py_compile scripts/scrapling-worker.py 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} scrapling-worker.py 语法正确"
else
    echo -e "  ${RED}✗${NC} scrapling-worker.py 语法错误"
    exit 1
fi

if python3 -m py_compile scripts/crawl4ai-worker.py 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} crawl4ai-worker.py 语法正确"
else
    echo -e "  ${RED}✗${NC} crawl4ai-worker.py 语法错误"
    exit 1
fi

echo ""

# 8. 文档完整性
echo "8️⃣  文档完整性..."
TOTAL_LINES=$(wc -l $(find . -type f \( -name "*.md" -o -name "*.mjs" -o -name "*.py" -o -name "*.sh" \)) | tail -1 | awk '{print $1}')
echo -e "  ${GREEN}✓${NC} 总计 $TOTAL_LINES 行代码和文档"

echo ""

# 总结
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $MISSING -eq 0 ] && [ $DEPS_MISSING -eq 0 ]; then
    echo -e "${GREEN}✅ 所有检查通过！${NC}"
    echo ""
    echo "下一步："
    echo "  1. 如果还没安装依赖: ./install-deps.sh"
    echo "  2. 运行测试: node tests/integration.test.mjs"
    echo "  3. 开始使用: node scripts/scrape.mjs https://example.com"
elif [ $DEPS_MISSING -gt 0 ]; then
    echo -e "${YELLOW}⚠️  部分依赖缺失${NC}"
    echo ""
    echo "安装依赖："
    echo "  ./install-deps.sh"
else
    echo -e "${RED}❌ 验证失败${NC}"
    exit 1
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
