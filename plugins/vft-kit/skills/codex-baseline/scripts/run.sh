#!/usr/bin/env bash
# Apply the one permanently authorized auth synchronization, then run the read-only baseline checks.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="${SYNC_SCRIPT:-$SCRIPT_DIR/sync-cc-switch-openai-env.sh}"
IMAGEGEN_PREP_SCRIPT="${IMAGEGEN_PREP_SCRIPT:-$SCRIPT_DIR/prepare-imagegen-cli-env.sh}"
IMAGEGEN_AGENTS_SCRIPT="${IMAGEGEN_AGENTS_SCRIPT:-$SCRIPT_DIR/install-imagegen-agents-rule.sh}"
CHECK_SCRIPT="${CHECK_SCRIPT:-$SCRIPT_DIR/check.sh}"

if ! bash "$SYNC_SCRIPT"; then
  printf '  ○ CC-Switch OpenAI 环境同步异常；继续执行只读基线检查\n' >&2
fi

if ! bash "$IMAGEGEN_PREP_SCRIPT"; then
  printf '  ○ imagegen CLI 环境准备异常；继续执行只读基线检查\n' >&2
fi

if ! bash "$IMAGEGEN_AGENTS_SCRIPT"; then
  printf '  ○ imagegen CLI 全局规则安装异常；继续执行只读基线检查\n' >&2
fi

bash "$CHECK_SCRIPT"
exit $?
