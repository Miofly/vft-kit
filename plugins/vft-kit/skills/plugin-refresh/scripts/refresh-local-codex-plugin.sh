#!/usr/bin/env bash
# refresh-local-codex-plugin.sh
# 刷新本地目录 Codex 插件的 cache（remove + add）。
set -euo pipefail

PLUGIN=""
MARKETPLACE=""
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
Usage: refresh-local-codex-plugin.sh -p <plugin> [-m <marketplace>] [-q]

  -p, --plugin       插件名（必填）
  -m, --marketplace  marketplace 名（默认与 plugin 同名）
  -q, --quiet        不打印末尾"重启会话"提示

会做的事：
  1) 校验 Codex marketplace 存在并指向本地目录
  2) codex plugin remove <plugin>@<marketplace>
  3) codex plugin add <plugin>@<marketplace>
  4) 校验 ~/.codex/plugins/cache 中 SKILL.md 数量 = 源目录中 SKILL.md 数量
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
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

echo "==> 目标: ${PLUGIN}@${MARKETPLACE}"

if ! command -v codex >/dev/null 2>&1; then
  echo "✗ 未找到 codex CLI" >&2
  exit 1
fi

mp_list_plain="$(codex plugin marketplace list 2>&1 || true)"
src_path="$(echo "$mp_list_plain" | awk -v name="$MARKETPLACE" '
  NR == 1 { next }
  $1 == name {
    $1=""
    sub(/^[[:space:]]+/, "")
    print
    exit
  }
')"

if [[ -z "$src_path" ]]; then
  echo "✗ 找不到 Codex marketplace: ${MARKETPLACE}" >&2
  echo "  当前已注册:" >&2
  echo "$mp_list_plain" | sed 's/^/    /' >&2
  exit 1
fi
if [[ ! -d "$src_path" ]]; then
  echo "✗ Codex marketplace 不是本地目录或目录不存在: ${src_path}" >&2
  exit 1
fi

echo "==> 源 marketplace: ${src_path}"

plugin_root=""
while IFS= read -r plugin_json; do
  name="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$plugin_json" | head -1)"
  if [[ "$name" == "$PLUGIN" ]]; then
    plugin_root="$(cd "$(dirname "$plugin_json")/.." && pwd)"
    break
  fi
done < <(find "$src_path" -maxdepth 6 \( -path '*/.codex-plugin/plugin.json' -o -path '*/.claude-plugin/plugin.json' \) 2>/dev/null)

[[ -z "$plugin_root" ]] && plugin_root="$src_path"
[[ "$plugin_root" != "$src_path" ]] && echo "==> 插件根: ${plugin_root}"

if [[ ! -d "$plugin_root/skills" ]]; then
  echo "✗ 插件根缺少 skills 目录: ${plugin_root}/skills" >&2
  exit 1
fi

cache_root="$CODEX_HOME/plugins/cache/${MARKETPLACE}/${PLUGIN}"
if [[ -L "$cache_root" ]] || { [[ -d "$cache_root" ]] && find "$cache_root" -mindepth 1 -maxdepth 1 -type l | grep -q .; }; then
  echo "✗ Codex cache 存在软链，拒绝刷新以避免写操作穿透源码: ${cache_root}" >&2
  echo "  请先手动删除该软链 cache，再重新安装插件。" >&2
  exit 1
fi

echo "==> remove ${PLUGIN}@${MARKETPLACE}"
codex plugin remove "${PLUGIN}@${MARKETPLACE}" 2>&1 | tail -5 || true

echo "==> add ${PLUGIN}@${MARKETPLACE}"
if ! codex plugin add "${PLUGIN}@${MARKETPLACE}" 2>&1 | tail -8; then
  echo "✗ add 失败" >&2
  exit 1
fi

cache_ver_dir="$(find "$cache_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1 || true)"
if [[ -z "$cache_ver_dir" ]]; then
  echo "✗ cache 目录为空: ${cache_root}（add 可能未真正落盘）" >&2
  exit 1
fi
cache_dir="$cache_ver_dir"

src_skill_count="$(find "${plugin_root}/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
cache_skill_count="$(find "${cache_dir}/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"

echo "==> SKILL.md 数量：源 ${src_skill_count} / cache ${cache_skill_count}"
if [[ "$src_skill_count" != "$cache_skill_count" ]]; then
  echo "✗ 数量不一致，Codex cache 没刷干净" >&2
  exit 1
fi

sample_skill="$(find "${plugin_root}/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | sort | head -1)"
if [[ -n "$sample_skill" ]]; then
  rel="${sample_skill#${plugin_root}/}"
  cache_sample="${cache_dir}/${rel}"
  if [[ -f "$cache_sample" ]]; then
    src_size="$(wc -c < "$sample_skill" | tr -d ' ')"
    cache_size="$(wc -c < "$cache_sample" | tr -d ' ')"
    if [[ "$src_size" != "$cache_size" ]]; then
      echo "✗ 抽样 SKILL.md 尺寸不一致：${rel} 源=${src_size}B cache=${cache_size}B" >&2
      exit 1
    fi
  else
    echo "✗ cache 缺少抽样文件: ${rel}" >&2
    exit 1
  fi
fi

echo "✅ ${PLUGIN}@${MARKETPLACE} Codex cache 已刷新（${cache_dir}）"

if [[ "$SKIP_RESTART_TIP" -eq 0 ]]; then
  echo
  echo "⚠ 重启 Codex 会话，新 SKILL.md 才会进入 LLM 的 system prompt。"
  echo "   仅刷 cache 不重启会话，本会话内 LLM 看到的还是旧 SKILL.md 正文。"
fi
