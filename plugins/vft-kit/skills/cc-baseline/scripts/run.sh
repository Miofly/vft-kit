#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RTK_SCRIPT="${RTK_SCRIPT:-$SCRIPT_DIR/install-rtk.sh}"
CAVEMAN_SCRIPT="${CAVEMAN_SCRIPT:-$SCRIPT_DIR/install-caveman-default.sh}"
CHECK_SCRIPT="${CHECK_SCRIPT:-$SCRIPT_DIR/check.sh}"

if ! bash "$RTK_SCRIPT"; then
  printf '  ○ RTK 自动安装异常；继续执行基线检查\n' >&2
fi

if ! bash "$CAVEMAN_SCRIPT"; then
  printf '  ○ Caveman 默认 full 安装异常；继续执行只读基线检查\n' >&2
fi

bash "$CHECK_SCRIPT" "$@"
