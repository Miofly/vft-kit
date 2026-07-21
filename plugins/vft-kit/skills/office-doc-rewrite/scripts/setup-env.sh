#!/usr/bin/env bash
# 建一个专用 venv 并装 openpyxl/python-docx/pillow，幂等。
# 本机 pip 常被 uv/homebrew 接管(报 "No virtual environment found"),故用独立 venv 隔离。
# 成功后打印 OFFICE_PY=<python路径>,后续脚本用它跑。
set -euo pipefail

VENV="${OFFICE_REWRITE_VENV:-$HOME/.cache/vft-kit/office-rewrite/venv}"
PY="$VENV/bin/python3"

need_install() {
  [ -x "$PY" ] || return 0
  "$PY" -c "import openpyxl, docx, PIL" 2>/dev/null && return 1 || return 0
}

if need_install; then
  echo "[setup] 创建 venv: $VENV" >&2
  mkdir -p "$(dirname "$VENV")"
  # 优先 uv(快),回退标准 venv
  if command -v uv >/dev/null 2>&1; then
    uv venv "$VENV" >&2 2>&1 || python3 -m venv "$VENV"
    VIRTUAL_ENV="$VENV" uv pip install openpyxl python-docx pillow >&2 2>&1 \
      || "$PY" -m pip install openpyxl python-docx pillow >&2 2>&1
  else
    python3 -m venv "$VENV"
    "$PY" -m pip install --upgrade pip >&2 2>&1
    "$PY" -m pip install openpyxl python-docx pillow >&2 2>&1
  fi
  echo "[setup] 依赖安装完成" >&2
else
  echo "[setup] 依赖已就绪" >&2
fi

# 供调用方 eval "$(bash setup-env.sh)" 取用
echo "OFFICE_PY=$PY"
