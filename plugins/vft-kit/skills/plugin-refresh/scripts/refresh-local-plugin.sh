#!/usr/bin/env bash
# refresh-local-plugin.sh
# 刷新本地目录 Claude Code 插件的 cache（uninstall + install）。
# 用 -p <plugin-name> 指定要刷的插件（须已注册为 Directory 来源的本地 plugin）。
#
# 背景：Claude Code 启动会话时，给 LLM 注入的 SKILL.md 正文是从
#   ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/
# 读的，**不是**源目录。`plugin details` 命令显示的组件列表会实时读源目录，
# 但这只决定"哪些 skill 存在"，不决定"LLM 看到的 SKILL.md 正文"。
# 改了源目录里的 SKILL.md / scripts / 子文件后，必须重新 install 才能刷 cache。
#
# `claude plugin marketplace update` 不刷 cache。
# `claude plugin install` 看到已装会跳过。
# 唯一可靠路径：先 uninstall 再 install。

set -euo pipefail

PLUGIN=""
MARKETPLACE=""    # 不传时假设与 plugin 同名（本地目录插件通常如此）
SKIP_RESTART_TIP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--plugin)
      PLUGIN="$2"; shift 2 ;;
    -m|--marketplace)
      MARKETPLACE="$2"; shift 2 ;;
    -q|--quiet)
      SKIP_RESTART_TIP=1; shift ;;
    -h|--help)
      cat <<EOF
Usage: refresh-local-plugin.sh -p <plugin> [-m <marketplace>] [-q]

  -p, --plugin       插件名（必填）
  -m, --marketplace  marketplace 名（默认与 plugin 同名）
  -q, --quiet        不打印末尾"重启会话"提示

会做的事：
  1) 校验 plugin / marketplace 存在
  2) claude plugin uninstall <plugin>@<marketplace>
  3) claude plugin install <plugin>@<marketplace>
  4) 校验 cache 中 SKILL.md 数量 = 源目录中 SKILL.md 数量
EOF
      exit 0 ;;
    *)
      echo "未知参数: $1" >&2
      exit 2 ;;
  esac
done

if [[ -z "$PLUGIN" ]]; then
  echo "✗ 必须用 -p <plugin> 指定要刷新的插件（-h 看用法）" >&2
  exit 2
fi

[[ -z "$MARKETPLACE" ]] && MARKETPLACE="$PLUGIN"

echo "==> 目标: ${PLUGIN}@${MARKETPLACE}"

# ---- 1. 取 marketplace 源目录路径（仅本地目录插件支持本脚本）----
mp_list_json="$(claude plugin marketplace list 2>/dev/null || true)"
# 简单做法：用 plain 输出再 grep —— Claude CLI 暂不支持 --json
mp_list_plain="$(claude plugin marketplace list 2>&1 || true)"
src_dir="$(echo "$mp_list_plain" | awk -v name="$MARKETPLACE" '
  $1 == "❯" && $2 == name { found=1; next }
  found && $1 == "Source:" {
    sub(/^[[:space:]]*Source:[[:space:]]*/, "")
    print
    exit
  }
')"

if [[ -z "$src_dir" ]]; then
  echo "✗ 找不到 marketplace: ${MARKETPLACE}" >&2
  echo "  当前已注册:" >&2
  echo "$mp_list_plain" | sed 's/^/    /' >&2
  exit 1
fi

# 形如 "Directory (/abs/path)" 或 "GitHub (org/repo)"
if [[ "$src_dir" != Directory* ]]; then
  echo "✗ ${MARKETPLACE} 不是本地目录插件 (${src_dir})" >&2
  echo "  本脚本只刷 Directory 来源；远端插件请用 \`claude plugin install\` 走标准链路。" >&2
  exit 1
fi

# 抽 () 内的路径
src_path="$(echo "$src_dir" | sed -E 's/^Directory \((.*)\)$/\1/')"
echo "==> 源目录: ${src_path}"

# ---- 2. uninstall + install ----
echo "==> uninstall ${PLUGIN}@${MARKETPLACE}"
claude plugin uninstall "${PLUGIN}@${MARKETPLACE}" 2>&1 | tail -3 || true

echo "==> install ${PLUGIN}@${MARKETPLACE}"
if ! claude plugin install "${PLUGIN}@${MARKETPLACE}" 2>&1 | tail -3; then
  echo "✗ install 失败" >&2
  exit 1
fi

# ---- 3. 校验 cache 与源 SKILL.md 数量一致 ----
cache_root="$HOME/.claude/plugins/cache/${MARKETPLACE}/${PLUGIN}"
cache_ver_dir="$(ls -1 "$cache_root" 2>/dev/null | head -1 || true)"
if [[ -z "$cache_ver_dir" ]]; then
  echo "⚠ cache 目录为空: ${cache_root}（install 可能未真正落盘）" >&2
  exit 1
fi
cache_dir="${cache_root}/${cache_ver_dir}"

src_skill_count="$(find "${src_path}/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
cache_skill_count="$(find "${cache_dir}/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"

echo "==> SKILL.md 数量：源 ${src_skill_count} / cache ${cache_skill_count}"
if [[ "$src_skill_count" != "$cache_skill_count" ]]; then
  echo "✗ 数量不一致，cache 没刷干净" >&2
  exit 1
fi

# 抽样校验：取一个 skill 的 SKILL.md size 做对比，提早抓到"个数对但内容旧"的边角
sample_skill="$(find "${src_path}/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | head -1)"
if [[ -n "$sample_skill" ]]; then
  rel="${sample_skill#${src_path}/}"
  cache_sample="${cache_dir}/${rel}"
  if [[ -f "$cache_sample" ]]; then
    src_size=$(wc -c < "$sample_skill" | tr -d ' ')
    cache_size=$(wc -c < "$cache_sample" | tr -d ' ')
    if [[ "$src_size" != "$cache_size" ]]; then
      echo "⚠ 抽样 SKILL.md 尺寸不一致：${rel} 源=${src_size}B cache=${cache_size}B" >&2
      exit 1
    fi
  fi
fi

echo "✅ ${PLUGIN}@${MARKETPLACE} cache 已刷新（${cache_dir}）"

if [[ "$SKIP_RESTART_TIP" -eq 0 ]]; then
  echo
  echo "⚠ 重启 Claude Code 会话（关掉当前 cc 重开），新 SKILL.md 才会进 LLM 的 system prompt。"
  echo "   仅刷 cache 不重启会话，本会话内 LLM 看到的还是旧 SKILL.md 正文。"
fi
