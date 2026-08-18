#!/usr/bin/env bash
set -euo pipefail

if command -v rtk >/dev/null 2>&1; then
  printf '  ✓ RTK 已安装（%s）\n' "$(rtk --version 2>/dev/null)"
  exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
  printf '  ✗ RTK 缺失且 Homebrew 不可用，无法自动安装\n' >&2
  exit 1
fi

brew install rtk
command -v rtk >/dev/null 2>&1 || {
  printf '  ✗ Homebrew 执行完成，但仍未找到 RTK\n' >&2
  exit 1
}
