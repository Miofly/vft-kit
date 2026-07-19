---
name: fe-lint-fix
description: 对任意前端项目（默认当前目录，也可指定任意带 package.json 的目录/子包）一键执行 ESLint / Stylelint / Prettier 自动修复 + TypeScript（vue-tsc 或 tsc）类型校验，并清晰区分「已自动修复」与「需人工处理」。自动探测包管理器（pnpm / yarn / bun / npm）与项目已有的 lint 脚本，未装的工具自动跳过。改完任何 .vue / .ts / .tsx / .js / 样式文件后都该跑一遍收尾。用户说"跑一下 lint"、"修复 lint 报错"、"格式化代码"、"eslint --fix"、"stylelint 修一下"、"prettier 格式化"、"vue-tsc/tsc 类型检查"、"type check"、"代码质量检查"、"提交前过一遍 lint"、"lint 一下这个项目"等场景时触发。即使只说"修一下格式/报错"也用本 skill，因为它封装了正确的执行顺序与包管理器/脚本探测，避免手敲 npx 命令踩 glob/cache/顺序误报的坑。
---

# fe-lint-fix — 前端代码质量一键修复 + 校验（通用）

封装「改完前端代码收尾」的标准动作：**Prettier → Stylelint → ESLint 自动修复，再跑 TypeScript 类型校验**。把一串容易记错 glob / cache / 执行顺序的命令固化成一条脚本，**不绑定任何具体仓库或包管理器**——放进任意前端项目都能跑。

## 为什么用脚本而不是手敲 npx

- **执行顺序有讲究**：必须先格式化（Prettier/Stylelint）再 ESLint。反过来的话，用了 `eslint-plugin-prettier` 的项目会在格式化前先把 `prettier/prettier` 规则当成一堆 ESLint 失败误报，等 Prettier 改完其实早就干净了。脚本把顺序固化对。
- **glob / cache 路径会记错**：stylelint 的 `**/*.{vue,less,postcss,css,scss}` + cache 目录、eslint 的 `--cache --max-warnings 0` 手敲容易漏。
- **每个项目不一样**：包管理器可能是 pnpm/yarn/bun/npm，可能有也可能没有 `lint:eslint` 这类脚本，可能用 vue-tsc 也可能用 tsc。脚本**全自动探测**，同一条命令对任何项目成立。
- **修复与校验分清**：4 步各标 ✅/❌/⏭，最后汇总「哪几步需人工」，TypeScript 这种只能人工改的错误不会被淹没。

## 默认用法（日常收尾，走这条）

```bash
bash "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/fe-lint-fix/scripts/lint-fix.sh"
```

不带参数 = 对**当前工作目录**依次跑 **Prettier --write → Stylelint --fix → ESLint --fix → TypeScript --noEmit**。

- 前三步会**就地自动修复**文件，能修的都修掉；项目没装某个工具的就自动跳过（⏭）。
- 第四步**只校验不改文件**，类型错误必须人工修。
- 全部通过退出码 0；任一步有「自动修复解决不了」的残留则退出码 1，并打印对应报错末尾日志，方便直接定位人工改。

## 指定其它目录 / 子包

第一个位置参数或 `-t` 就是目标，可相对当前目录或绝对路径：

```bash
lint-fix.sh packages/ui          # monorepo 里换个子包
lint-fix.sh -t apps/web          # 显式指定
lint-fix.sh /abs/path/to/pkg     # 绝对路径
```

目标目录必须有 `package.json`，否则报错退出（exit 2）。

## 只跑某一步 / 跳过某一步

```bash
lint-fix.sh --eslint        # 只 eslint --fix（--stylelint / --prettier / --ts 同理，互斥）
lint-fix.sh --no-ts         # 跳过类型检查（改的是纯样式/纯格式时常用）
lint-fix.sh --no-prettier --no-stylelint   # 只跑 eslint + ts，可叠加
```

`--xxx`（只跑）和 `--no-xxx`（跳过）按需选，不要同时给冲突的两类。

## 探测逻辑（出问题时看这里）

**包管理器**：lockfile 优先（`pnpm-lock.yaml` / `yarn.lock` / `bun.lock(b)` / `package-lock.json`），再看 `package.json` 的 `packageManager` 字段，最后按现成二进制兜底，都没有则降级 npm。若项目有 `volta` 字段且本机装了 Volta，会自动用 `volta run <pm>`，避免全局 pnpm/npm 版本不匹配。

**每一步**都是「有对应 npm 脚本就用脚本，没有就回退直调二进制，二进制也没装就跳过」：

| 步骤 | 优先脚本名 | 回退命令（探测到装了才跑） |
|---|---|---|
| Prettier | `lint:prettier` / `format:prettier` / `format` | `<pm> exec prettier --write .` |
| Stylelint | `lint:stylelint` / `lint:style` / `stylelint` | `<pm> exec stylelint "**/*.{vue,less,postcss,css,scss}" --fix --cache ... --allow-empty-input` |
| ESLint | `lint:eslint` / `lint:es` / `lint` | `<pm> exec eslint . --cache --max-warnings 0 --fix` |
| TypeScript | `type-check` / `lint:type` / `typecheck` / `tsc` / `lint:tsc` | 有 `vue-tsc` 依赖 → `vue-tsc --noEmit`；否则有 `typescript`+`tsconfig.json` → `tsc --noEmit` |

> 优先用项目脚本，是因为脚本里编码了项目特有的 glob / cache / 阈值；项目加了 `type-check` 等脚本后本 skill 自动优先用它，无需改脚本。

## 失败排查

| 现象 | 原因 / 处理 |
|---|---|
| `目标目录无 package.json` | TARGET 路径错了，确认相对当前目录或给绝对路径 |
| 某步显示 ⏭ 跳过 | 项目没装该工具 / 没有 tsconfig，属正常；要用就先在项目里装依赖 |
| ESLint ❌ 仍有残留 | `--fix` 修不了的 error/warning（如未用变量、逻辑问题），按打印日志人工改；未使用变量加 `_` 前缀 |
| Stylelint ❌ 仍有残留 | 极少见，多数能 --fix；看日志按属性顺序 / 选择器规则手改 |
| TypeScript ❌ | 类型错误**只能人工改**，本步从不改文件；按 `文件:行` 定位修类型 |
| `exec ... not found` | 目标目录没装该依赖，或需先在项目里装一次依赖 |

## 操作原则

- **改完代码自己跑、自己读报错、自己修**，跑完一句话报结果（全绿 / 哪几步要人工 + 已修了什么），不要追问"要不要我跑 lint"。
- 前三步是自动修复，放心跑；TypeScript 是校验，红了就去改类型，别忽略。
- 只动样式时用 `--no-ts` 省时间；要全量收尾就不带参数。
- 这是收尾纪律：把「每次改动代码后必须解决 Lint 报错」落地成一条命令。
