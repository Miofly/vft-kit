#!/usr/bin/env bash
# check-sfc-split.sh —— 校验巨型 .vue 拆分后的目录结构
#
# 用法：
#   check-sfc-split.sh <平铺入口 .vue 的路径>
# 例：
#   check-sfc-split.sh src/views/tools/video-trim.vue
#
# 校验项（❌ 任一不过 → exit 1；⚠️ 仅提示，不影响退出码）：
#   1. 专属子组件「模板里用了但没 import」—— 本脚本最重要的检查。
#      <页面名>/components/** 不在组件自动导入的扫描范围内，漏 import 时
#      ESLint 和 vue-tsc 都静默通过，只有浏览器运行时报
#      [Vue warn]: Failed to resolve component + 该块空白。
#   2. 抽出的 css 里有无「未加页面前缀的通用类名」（抽出后不再 scoped，会污染全局）
#   3. 入口行数是否已收敛
#
#   以下仅在检测到文件路由（unplugin-vue-router）时才校验——手写路由表的项目
#   不受这些约束，对它们报错是误报：
#   4. 不存在 <页面名>/index.vue（会和同级 <分类>/index.vue 撞路由名）
#   5. <页面名>/ 里的 .vue 都在某个 components/ 段下
#      （路由通常配 exclude '**/components/**'；components 外的 .vue 会被
#       误扫成一条多余路由，破坏路由树）
#   6. 入口里 definePage / defineOptions name 仍在（不丢路由 / 菜单身份）
#
# 环境变量：
#   MAX_ENTRY_LINES  入口行数软警告阈值（默认 600）

set -u

ENTRY="${1:-}"
MAX_LINES="${MAX_ENTRY_LINES:-600}"

if [[ -z "$ENTRY" ]]; then
  echo "用法: check-sfc-split.sh <平铺入口 .vue 的路径>" >&2
  exit 2
fi
if [[ ! -f "$ENTRY" ]]; then
  echo "❌ 找不到入口文件: $ENTRY" >&2
  exit 2
fi
case "$ENTRY" in
  */components/*)
    echo "❌ 传入的是 components 下的子组件，不是入口。请传平铺的 <页面名>.vue" >&2
    exit 2 ;;
  *index.vue)
    echo "❌ 传入的是 index.vue。入口应是平铺的 <页面名>.vue，不要用 <页面名>/index.vue" >&2
    exit 2 ;;
esac

DIR=$(cd "$(dirname "$ENTRY")" && pwd)
BASE=$(basename "$ENTRY" .vue)        # 如 video-trim
TOOLDIR="$DIR/$BASE"                  # 同级专属目录 video-trim/

fail=0
warn=0
ok()   { printf '✅ %s\n' "$1"; }
bad()  { printf '❌ %s\n' "$1"; fail=1; }
note() { printf '⚠️  %s\n' "$1"; warn=1; }
rel()  { printf '%s' "${1#"$DIR"/}"; }

# kebab-case → PascalCase（trim-range-panel → TrimRangePanel）
to_pascal() {
  printf '%s' "$1" | awk -F- '{ for (i = 1; i <= NF; i++) printf toupper(substr($i, 1, 1)) substr($i, 2) }'
}

echo "── 校验 .vue 拆分结构: $BASE ──"
echo "入口: $ENTRY"
[[ -d "$TOOLDIR" ]] && echo "专属目录: $TOOLDIR" || echo "专属目录: (未创建)"

# ── 探测：项目是否用了文件路由 ────────────────────────────────────
# 决定下面哪些约束适用。手写路由表 + 手动 import 的项目里，把 panel.vue 放在
# 专属目录根、不写 definePage 都是完全合法的，不能对它们报 ❌。
uses_file_router=0
probe="$DIR"
while [[ "$probe" != "/" ]]; do
  # a) vite 配置里直接写了插件
  for cfg in "$probe"/vite.config.ts "$probe"/vite.config.js "$probe"/vite.config.mts "$probe"/vite.config.mjs; do
    [[ -f "$cfg" ]] && grep -q "unplugin-vue-router\|VueRouter(" "$cfg" 2>/dev/null && uses_file_router=1
  done
  # b) package.json 里有依赖 —— 更可靠：很多项目把 vite 插件封装进了自己的 config 包，
  #    配置文件里根本 grep 不到插件名
  if [[ -f "$probe/package.json" ]]; then
    grep -q "unplugin-vue-router" "$probe/package.json" 2>/dev/null && uses_file_router=1
    break   # 到子包根就停，别一路爬到 monorepo 根
  fi
  probe=$(dirname "$probe")
done
# 入口自带 definePage 宏，也说明在用文件路由。
# 注意：defineOptions 不能当信号——它是 Vue 3.3 起的内置宏，任何项目都能用，与文件路由无关。
grep -q "definePage" "$ENTRY" 2>/dev/null && uses_file_router=1

if [[ "$uses_file_router" -eq 1 ]]; then
  echo "项目: 使用文件路由（unplugin-vue-router）→ 路由相关约束生效"
else
  echo "项目: 未检测到文件路由 → 跳过路由相关检查（index.vue / components 位置 / 路由身份）"
fi
echo

# ── 1. 漏 import 检查（所有项目都适用，最重要） ────────────────────
# 保守匹配：只校验专属目录里「真实存在」的组件文件，不去猜模板里其它标签该不该
# import——那需要一份组件自动导入的白名单，各项目配置千差万别，猜错会刷屏假警报。
if [[ -d "$TOOLDIR" ]]; then
  missing=0
  orphan=0
  checked=0

  while IFS= read -r comp; do
    [[ -z "$comp" ]] && continue
    cname=$(basename "$comp" .vue)          # trim-range-panel
    pascal=$(to_pascal "$cname")            # TrimRangePanel
    used_anywhere=0
    checked=$((checked + 1))

    # 谁可能用它：入口 + 专属目录里所有其它 .vue
    while IFS= read -r user; do
      [[ -z "$user" ]] && continue
      [[ "$user" == "$comp" ]] && continue   # 不跟自己比

      # 模板里出现 <TrimRangePanel …> 或 <trim-range-panel …> 了吗
      if grep -qE "<($pascal|$cname)([[:space:]>/]|$)" "$user" 2>/dev/null; then
        used_anywhere=1
        # 用了就必须有指向该文件的 import（静态 import / defineAsyncComponent 都算）
        if ! grep -q "${cname}\.vue" "$user" 2>/dev/null; then
          bad "$(rel "$user") 模板用了 <$pascal> 却没 import ${cname}.vue —— 运行时 Failed to resolve component（lint / vue-tsc 查不出）"
          missing=1
        fi
      fi
    done < <(printf '%s\n' "$ENTRY"; find "$TOOLDIR" -name '*.vue' -type f 2>/dev/null)

    if [[ $used_anywhere -eq 0 ]]; then
      note "专属组件 $(rel "$comp") 没有任何地方用到 —— 漏接线了，还是该删的残留？"
      orphan=1
    fi
  done < <(find "$TOOLDIR" -name '*.vue' -type f 2>/dev/null)

  if [[ $checked -eq 0 ]]; then
    note "专属目录里没有 .vue，还没拆出子组件？"
  elif [[ $missing -eq 0 && $orphan -eq 0 ]]; then
    ok "专属子组件 ${checked} 个，用到的都已显式 import，无孤儿组件"
  elif [[ $missing -eq 0 ]]; then
    ok "模板用到的专属子组件都已显式 import"
  fi
else
  note "未发现专属目录 ${BASE}/，若入口仍很大说明还没开始拆"
fi

# ── 2. 抽出的 css 是否含未加前缀的通用类名（会污染全局） ────────────
# <style scoped> 抽成独立 .css 后不再 scoped，隔离只剩类名前缀。
# 顶层类选择器若是 .header / .panel 这类通用名，会漏到全局。
if [[ -d "$TOOLDIR" ]]; then
  generic='^(header|footer|nav|main|aside|section|panel|card|title|subtitle|desc|content|wrapper|container|box|inner|item|list|row|col|btn|button|icon|input|label|form|table|tabs|tab|tip|tips|actions|toolbar|empty|active|disabled|hidden|error|success|warning|loading|left|right|top|bottom|center)$'
  leaked=0
  css_seen=0
  while IFS= read -r css; do
    [[ -z "$css" ]] && continue
    css_seen=1
    while IFS= read -r cls; do
      [[ -z "$cls" ]] && continue
      if printf '%s' "$cls" | grep -qE "$generic"; then
        note "$(rel "$css") 顶层类名 .${cls} 过于通用 —— 抽出后不再 scoped，会污染全局。加页面前缀（如 .${BASE}-${cls}）"
        leaked=1
      fi
    done < <(grep -oE '^\.[a-zA-Z][a-zA-Z0-9_-]*' "$css" 2>/dev/null | sed 's/^\.//' | sort -u)
  done < <(find "$TOOLDIR" -name '*.css' -type f 2>/dev/null)
  [[ $css_seen -eq 1 && $leaked -eq 0 ]] && ok "抽出的 css 无裸通用类名（无全局污染风险）"
fi

# ── 3. 入口行数软警告 ─────────────────────────────────────────────
lines=$(wc -l < "$ENTRY" | tr -d ' ')
if [[ "$lines" -gt "$MAX_LINES" ]]; then
  note "入口仍有 ${lines} 行，偏大——继续把可独立的面板/结果块/逻辑外移"
else
  ok "入口行数 ${lines}，已收敛到合理区间"
fi

# ── 4/5/6. 文件路由专属约束 ───────────────────────────────────────
if [[ "$uses_file_router" -eq 1 ]]; then
  echo

  # 4. 禁止 <页面名>/index.vue
  if [[ -f "$TOOLDIR/index.vue" ]]; then
    bad "存在 ${BASE}/index.vue —— 会和同级 <分类>/index.vue 撞路由名，删掉并把入口逻辑放回平铺 ${BASE}.vue"
  else
    ok "未使用 ${BASE}/index.vue（正确）"
  fi

  # 5. 专属 .vue 必须在 components/ 段下
  if [[ -d "$TOOLDIR" ]]; then
    stray=0
    while IFS= read -r vue; do
      [[ -z "$vue" ]] && continue
      case "$vue" in
        */components/*) : ;;                    # 合规：被路由 exclude
        *) bad "目录内 .vue 不在 components/ 下，会被误扫成路由: $(rel "$vue")"; stray=1 ;;
      esac
    done < <(find "$TOOLDIR" -name '*.vue' -type f 2>/dev/null)
    [[ $stray -eq 0 ]] && ok "专属目录内所有 .vue 都在 components/ 下（不会被路由扫描）"
  fi

  # 6. 路由 / 菜单身份未丢
  if grep -q "defineOptions" "$ENTRY" && grep -q "name:" "$ENTRY"; then
    ok "入口保留 defineOptions name（路由身份未丢）"
  else
    note "入口未见 defineOptions name —— 确认拆分时没把路由名删掉/改掉"
  fi
  grep -q "definePage" "$ENTRY" && ok "入口保留 definePage meta（菜单/标题身份未丢）" \
    || note "入口未见 definePage —— 确认菜单 meta 未丢"
fi

echo
if [[ $fail -ne 0 ]]; then
  echo "结果: ❌ 结构有硬性问题，按上面 ❌ 项修正"
  exit 1
fi
if [[ $warn -ne 0 ]]; then
  echo "结果: ✅ 结构合规（有 ⚠️ 提示，自行确认）"
  exit 0
fi
echo "结果: ✅ 结构完全合规"
exit 0
