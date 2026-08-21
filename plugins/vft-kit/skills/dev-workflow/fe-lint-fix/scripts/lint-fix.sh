#!/usr/bin/env bash
# fe-lint-fix —— 任意前端项目的 ESLint / Stylelint / Prettier / TypeScript 一键修复 + 校验
#
# 通用设计（不绑定任何具体仓库）：
#   - 目标默认是「当前工作目录」，也可传路径（相对当前目录或绝对）。
#   - 自动探测包管理器（pnpm / yarn / bun / npm），据此选 run / exec 命令。
#   - 每步优先用项目自己的 npm 脚本（lint:eslint / lint:stylelint / lint:prettier / type-check 等），
#     因为脚本里编码了项目特有的 glob、cache 路径、--max-warnings 阈值；没有脚本才回退直调二进制。
#   - TypeScript 步：有 vue 依赖用 vue-tsc，否则用 tsc；只校验不改文件。
#
# 用法：
#   lint-fix.sh [TARGET]              # TARGET 默认当前目录，可相对当前目录或绝对路径
#   lint-fix.sh -t path/to/pkg        # 同上，显式指定
#   lint-fix.sh --eslint              # 只跑 eslint（--stylelint / --prettier / --ts 同理，互斥）
#   lint-fix.sh --no-ts               # 跳过类型检查（其余照跑；--no-eslint 等同理，可叠加）
#   lint-fix.sh -h
#
# 退出码：全部步骤通过 0；有任一步骤存在「无法自动修复」的问题 1；参数/目标错误 2。

set -uo pipefail

TARGET="."
RUN_ESLINT=1; RUN_STYLELINT=1; RUN_PRETTIER=1; RUN_TS=1
ONLY=""

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target) TARGET="$2"; shift 2;;
    --eslint)    ONLY="eslint"; shift;;
    --stylelint) ONLY="stylelint"; shift;;
    --prettier)  ONLY="prettier"; shift;;
    --ts|--tsc)  ONLY="ts"; shift;;
    --no-eslint)    RUN_ESLINT=0; shift;;
    --no-stylelint) RUN_STYLELINT=0; shift;;
    --no-prettier)  RUN_PRETTIER=0; shift;;
    --no-ts)        RUN_TS=0; shift;;
    -h|--help) usage;;
    -*) echo "未知参数: $1" >&2; exit 2;;
    *) TARGET="$1"; shift;;
  esac
done

# --only 模式：只保留被选中的那一步
if [[ -n "$ONLY" ]]; then
  RUN_ESLINT=0; RUN_STYLELINT=0; RUN_PRETTIER=0; RUN_TS=0
  case "$ONLY" in
    eslint) RUN_ESLINT=1;; stylelint) RUN_STYLELINT=1;;
    prettier) RUN_PRETTIER=1;; ts) RUN_TS=1;;
  esac
fi

# 解析 TARGET 为绝对路径（相对则按当前目录拼）
case "$TARGET" in
  /*) TARGET_ABS="$TARGET";;
  *)  TARGET_ABS="$PWD/$TARGET";;
esac
if [[ ! -f "$TARGET_ABS/package.json" ]]; then
  echo "❌ 目标目录无 package.json: $TARGET_ABS" >&2
  exit 2
fi
cd "$TARGET_ABS"

# 探测包管理器：lockfile 优先（最能反映项目真实用的），再看 packageManager 字段，最后按二进制可用性兜底。
# PM_RUN=运行 npm script 的命令；PM_EXEC=直接跑二进制的命令（npx 语义）。
detect_pm() {
  local pm=""
  if   [[ -f pnpm-lock.yaml ]]; then pm=pnpm
  elif [[ -f yarn.lock ]];      then pm=yarn
  elif [[ -f bun.lockb || -f bun.lock ]]; then pm=bun
  elif [[ -f package-lock.json ]]; then pm=npm
  fi
  if [[ -z "$pm" ]]; then
    pm="$(node -e "try{console.log((require('./package.json').packageManager||'').split('@')[0])}catch{}" 2>/dev/null)"
  fi
  # lockfile / 字段都没有：按现成二进制挑一个
  if [[ -z "$pm" ]]; then
    for c in pnpm yarn bun npm; do command -v "$c" >/dev/null 2>&1 && { pm="$c"; break; }; done
  fi
  # 选中的包管理器不存在，降级到 npm
  command -v "$pm" >/dev/null 2>&1 || pm=npm
  echo "$pm"
}
PM="$(detect_pm)"
# 项目若声明了 Volta 工具链，用 volta run 包住包管理器，避免全局 pnpm/npm 版本不符。
PM_PREFIX=""
if command -v volta >/dev/null 2>&1 && node -e "process.exit(require('./package.json').volta?0:1)" 2>/dev/null; then
  PM_PREFIX="volta run "
fi
case "$PM" in
  pnpm) PM_RUN="${PM_PREFIX}pnpm run"; PM_EXEC="${PM_PREFIX}pnpm exec";;
  yarn) PM_RUN="${PM_PREFIX}yarn run"; PM_EXEC="${PM_PREFIX}yarn exec --";;
  bun)  PM_RUN="${PM_PREFIX}bun run";  PM_EXEC="${PM_PREFIX}bunx";;
  *)    PM_RUN="${PM_PREFIX}npm run --"; PM_EXEC="${PM_PREFIX}npx --no-install";;
esac

echo "📂 目标项目：$TARGET_ABS"
echo "📦 包管理器：${PM_PREFIX}${PM}"
echo "──────────────────────────────────────────"

FAILED=()

# 该 package.json 是否定义了某个 npm script
has_script() {
  node -e "process.exit((require('./package.json').scripts||{})['$1']?0:1)" 2>/dev/null
}

# 该 package.json 的依赖里是否有某个包（dep / devDep）
has_dep() {
  node -e "let p=require('./package.json');process.exit((({...p.dependencies,...p.devDependencies})['$1'])?0:1)" 2>/dev/null
}

# 找一个存在的脚本名（按优先级），打印到 stdout；找不到返回非 0
first_script() {
  for s in "$@"; do has_script "$s" && { echo "$s"; return 0; }; done
  return 1
}

# 执行一步：捕获输出，通过则一行 OK，失败则打印末尾日志供人工定位
run_step() {
  local name="$1"; shift
  local log; log="$(mktemp)"
  printf '▶ %-12s ' "$name"
  if "$@" >"$log" 2>&1; then
    echo "✅ 通过"
  else
    local code=$?
    echo "❌ 有未自动修复的问题（exit ${code}）"
    echo "──── $name 输出（末尾 60 行）────"
    tail -n 60 "$log" | sed 's/^/  /'
    echo "────────────────────────────────"
    FAILED+=("$name")
  fi
  rm -f "$log"
}

# 执行顺序很关键：先 Prettier / Stylelint 把格式化类问题就地改掉，再跑 ESLint。
# 否则 ESLint 的 prettier/prettier 等「本该由 Prettier 修」的规则会在格式化之前先被
# 当成 ESLint 失败误报（用了 eslint-plugin-prettier 的项目里常见：ESLint 先跑会假报
# 一堆 prettier/prettier，等 Prettier 改完其实早已干净）。所以让格式化先行，
# ESLint 作为最后的 fix + 收口闸门。

# Prettier —— 纯格式化，--write 几乎总成功；放最前，统一格式基线
if [[ $RUN_PRETTIER == 1 ]]; then
  if s="$(first_script lint:prettier format:prettier format)"; then
    run_step "Prettier" $PM_RUN "$s"
  elif has_dep prettier; then
    run_step "Prettier" $PM_EXEC prettier --write .
  else
    printf '▶ %-12s ⏭  跳过（项目未装 prettier）\n' "Prettier"
  fi
fi

# Stylelint —— 样式属性顺序、字体引号等大多可 --fix
if [[ $RUN_STYLELINT == 1 ]]; then
  if s="$(first_script lint:stylelint lint:style stylelint)"; then
    run_step "Stylelint" $PM_RUN "$s"
  elif has_dep stylelint; then
    run_step "Stylelint" $PM_EXEC stylelint "**/*.{vue,less,postcss,css,scss}" --fix \
      --cache --cache-location node_modules/.cache/stylelint/ --allow-empty-input
  else
    printf '▶ %-12s ⏭  跳过（项目未装 stylelint）\n' "Stylelint"
  fi
fi

# ESLint —— 放在格式化之后，--fix 兜底；剩余 error/warning 才是真·需人工的问题
if [[ $RUN_ESLINT == 1 ]]; then
  if s="$(first_script lint:eslint lint:es lint)"; then
    run_step "ESLint" $PM_RUN "$s"
  elif has_dep eslint; then
    run_step "ESLint" $PM_EXEC eslint . --cache --max-warnings 0 --fix
  else
    printf '▶ %-12s ⏭  跳过（项目未装 eslint）\n' "ESLint"
  fi
fi

# TypeScript —— 只校验不修复，类型错误必须人工改。有 vue 依赖用 vue-tsc，否则用 tsc。
if [[ $RUN_TS == 1 ]]; then
  if s="$(first_script type-check lint:type typecheck tsc lint:tsc)"; then
    run_step "TypeScript" $PM_RUN "$s"
  elif has_dep vue-tsc; then
    run_step "TypeScript" $PM_EXEC vue-tsc --noEmit
  elif has_dep typescript && [[ -f tsconfig.json ]]; then
    run_step "TypeScript" $PM_EXEC tsc --noEmit
  else
    printf '▶ %-12s ⏭  跳过（无 vue-tsc/typescript 或无 tsconfig.json）\n' "TypeScript"
  fi
fi

echo "──────────────────────────────────────────"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "🎉 全部通过：无残留问题（未装的步骤已自动跳过）"
  exit 0
else
  echo "⚠️  需人工处理的步骤：${FAILED[*]}"
  echo "   （上面已打印各自的报错日志；自动修复已尽力，剩下的是 --fix 解决不了的）"
  exit 1
fi
