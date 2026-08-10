#!/bin/bash
# web-scrape 依赖安装脚本

set -e

echo "🔧 web-scrape 依赖安装"
echo ""

# 检查 Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 未安装"
    echo "请先安装 Python ≥ 3.8: https://www.python.org/downloads/"
    exit 1
fi

PYTHON_VERSION=$(python3 --version | awk '{print $2}')
echo "✅ Python $PYTHON_VERSION"

# 检查 Node.js
if ! command -v node &> /dev/null; then
    echo "❌ Node.js 未安装"
    echo "请先安装 Node.js ≥ 18: https://nodejs.org/"
    exit 1
fi

NODE_VERSION=$(node --version)
echo "✅ Node.js $NODE_VERSION"

# 询问安装方式
echo ""
echo "选择安装方式:"
echo "  1) 全局安装 (pip install)"
echo "  2) venv 虚拟环境 (推荐)"
echo ""
read -p "请选择 [1/2, 默认 2]: " INSTALL_MODE
INSTALL_MODE=${INSTALL_MODE:-2}

if [ "$INSTALL_MODE" = "1" ]; then
    echo ""
    echo "📦 全局安装 Python 依赖..."
    pip3 install scrapling crawl4ai playwright

elif [ "$INSTALL_MODE" = "2" ]; then
    VENV_PATH="$HOME/.scrape-venv"

    if [ -d "$VENV_PATH" ]; then
        echo ""
        echo "⚠️  venv 已存在: $VENV_PATH"
        read -p "是否重建? [y/N]: " REBUILD
        if [ "$REBUILD" = "y" ] || [ "$REBUILD" = "Y" ]; then
            rm -rf "$VENV_PATH"
        else
            echo "使用现有 venv"
        fi
    fi

    if [ ! -d "$VENV_PATH" ]; then
        echo ""
        echo "📦 创建 venv: $VENV_PATH"
        python3 -m venv "$VENV_PATH"
    fi

    echo ""
    echo "📦 安装 Python 依赖到 venv..."
    source "$VENV_PATH/bin/activate"
    pip install --upgrade pip
    pip install scrapling crawl4ai playwright

    echo ""
    echo "✅ venv 已创建: $VENV_PATH"
    echo ""
    echo "使用时需要激活 venv:"
    echo "  source $VENV_PATH/bin/activate"

else
    echo "❌ 无效选择"
    exit 1
fi

# 安装 Playwright 浏览器
echo ""
echo "📦 安装 Playwright 浏览器（Chromium）..."
playwright install chromium

echo ""
echo "✅ 所有依赖已安装"
echo ""
echo "测试安装:"
echo "  node $(dirname "$0")/tests/integration.test.mjs"
echo ""
echo "使用方法:"
echo "  node $(dirname "$0")/scripts/scrape.mjs https://example.com"
