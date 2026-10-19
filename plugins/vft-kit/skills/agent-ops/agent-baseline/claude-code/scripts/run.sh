#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RTK_SCRIPT="${RTK_SCRIPT:-$SCRIPT_DIR/install-rtk.sh}"
CAVEMAN_SCRIPT="${CAVEMAN_SCRIPT:-$SCRIPT_DIR/install-caveman-default.sh}"
CHECK_SCRIPT="${CHECK_SCRIPT:-$SCRIPT_DIR/check.sh}"
CG_FILTER_SCRIPT="${CG_FILTER_SCRIPT:-$SCRIPT_DIR/install-codegraph-prompt-filter.sh}"
MR_SCRIPT="${MR_SCRIPT:-$SCRIPT_DIR/install-model-router.sh}"
HN_SCRIPT="${HN_SCRIPT:-$SCRIPT_DIR/install-handoff-nudge.sh}"

if ! bash "$RTK_SCRIPT"; then
  printf '  ○ RTK 自动安装异常；继续执行基线检查\n' >&2
fi

if ! bash "$CAVEMAN_SCRIPT"; then
  printf '  ○ Caveman 默认 full 安装异常；继续执行只读基线检查\n' >&2
fi

if ! bash "$CG_FILTER_SCRIPT"; then
  printf '  ○ codegraph prompt-hook 过滤安装异常；继续执行基线检查\n' >&2
fi

# model-router 补丁版：首次安装为 advisory（影子）模式，配置不覆盖。
if ! bash "$MR_SCRIPT"; then
  printf '  ○ model-router 安装异常；继续执行基线检查\n' >&2
fi

# handoff-nudge：上下文过 40% 提醒写交接；默认影子运行（只写 ~/.cache/vft-kit/handoff-nudge.jsonl），
# 建标记文件 ~/.cache/vft-kit/handoff-nudge.LIVE 才真正注入提示。
if ! bash "$HN_SCRIPT" >/dev/null; then
  printf '  ○ handoff-nudge 安装异常；继续执行基线检查\n' >&2
fi

# 参数白名单：只认 check.sh 支持的 --health，其余忽略并提示，避免盲转发。
check_args=()
for a in "$@"; do
  case "$a" in
    --health) check_args+=("--health") ;;
    *) printf '  ○ 忽略未知参数（仅支持 --health）：%s\n' "$a" ;;
  esac
done

bash "$CHECK_SCRIPT" ${check_args[@]+"${check_args[@]}"}
