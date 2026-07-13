---
name: vue-sfc-split
description: 把体量过大的 Vue 单文件组件（动辄 800~2000 行的 .vue）拆成「平铺入口 .vue + 同级同名专属目录（components / composables / *.ts / *-scoped.css）」，把输入面板、结果展示块、纯逻辑、scoped 样式各自外移，能复用的沉淀到项目公共目录，并保证路由身份、行为、lint 全部不变。用户说"这个 vue 文件太大了/超过一千行/拆一下/拆成组件/页面变成目录/把样式抽出去/这个页面重构一下/split 这个 .vue/组件化/瘦身/模块化"等场景时触发；即使只说"这文件太长了帮我拆"也用本 skill——因为在用了**文件路由（unplugin-vue-router）或组件自动导入（unplugin-vue-components）**的项目里，拆分有一套必须遵守的约束，手拆极易踩 index.vue 撞路由名、子组件被误扫成路由、丢 definePage meta、漏 import 导致运行时空白（而 lint 和 vue-tsc 静默通过）这些坑。
---

# vue-sfc-split — 巨型 .vue 拆分

把臃肿的单文件组件拆成「**平铺入口 + 同级专属目录**」，让入口只承担"装配"，把面板 / 结果块 / 逻辑 / 样式各归其位。

这套拆法有几条**和文件路由、组件自动导入强耦合**的硬约束，踩错就是路由撞名报错、子组件被当成路由、或运行时空白——本 skill 把约束、决策表、步骤、自检脚本固化下来。

## 先探测项目用了什么（决定哪些约束适用）

动手前先确认，这决定下面「硬约束」哪几条对你生效：

```bash
# 文件路由？（约束 1、2、3 生效）
grep -rn "unplugin-vue-router\|VueRouter(" vite.config.* 2>/dev/null

# 组件自动导入？（约束 4 生效）
grep -rn "unplugin-vue-components\|Components(" vite.config.* 2>/dev/null
```

- **两个都没有**（手写路由表 + 手动 import）→ 只需遵守「目标结构」和「决策表」，硬约束可跳过。
- **用了文件路由** → 约束 1/2/3 是硬性的，踩错直接报错或丢菜单。
- **用了自动导入** → 约束 4 是硬性的，踩错运行时空白且 lint 查不出。

## 拆分 ≠ 搬家，是分层 + 复用

不要把 1000 行原样切成 5 个文件了事。边拆边问三件事：

1. **这块逻辑/组件，项目里是不是已经有公共件？** → 直接换掉，删掉自己这份。
2. **这块会被 ≥2 个页面用吗？** → 沉淀到项目公共目录，而不是塞进本页面专属目录。
3. **这块只有本页面用？** → 放专属目录 `<页面名>/`。

**先查复用（拆前必做）**：动手前 grep 一遍项目现有的公共件目录（通常是 `src/components/`、`src/composables/`、`src/utils/`，或本业务域下的公共目录），别把已存在的东西又拆一份。常见的重复造轮子：文件大小格式化、下载触发、防抖节流、尺寸获取、通用布局/卡片/表单行组件。

拆完的理想态：**入口 .vue 只剩 `<script>` 里的状态装配 + `<template>` 里的组件编排**。

## 目标结构

以 `video-trim.vue` 为例，拆后：

```
pages/
├── video-trim.vue                  ← 入口，平铺保留原地，不改文件名/位置
└── video-trim/                     ← 同级同名专属目录
    ├── composables/                ← 仅本页面用的 hook
    │   └── use-trim-range.ts
    ├── trim-args.ts                ← 仅本页面用的纯函数/类型
    ├── video-trim-scoped.css       ← 从入口 <style scoped> 抽出的样式
    └── components/                 ← 仅本页面用的子组件（.vue 必须在这里）
        ├── trim-range-panel.vue
        └── results/                ← 复杂页面可再分
            └── trim-result.vue
```

## 硬约束

### 1. 入口必须平铺 `<页面名>.vue`，禁止 `<页面名>/index.vue`

> 仅当用了文件路由（unplugin-vue-router）

文件路由会把 `<页面名>/index.vue` 和同级 `<分类>/index.vue` 当成**嵌套路由**，自动生成的 name 带尾斜杠，触发"子路由不能与祖先路由同名"报错。

- ✅ `video-trim.vue`（入口，原地不动）+ `video-trim/components/...`（专属件）
- ❌ 把入口挪进去改成 `video-trim/index.vue`

### 2. 专属 `.vue` 必须放在 `components/` 段下

> 仅当用了文件路由

文件路由通常配 `extensions: ['.vue']` + `exclude: ['**/components/**']`。所以：

- `<页面名>/components/**.vue` → 被 exclude，**不会**变成路由 ✅
- `<页面名>/foo.vue`（不在 components 下）→ 会被**误扫成一条多余路由**，破坏路由树 ❌
- `.ts` / `.css` 放专属目录任意位置都安全（不在 extensions 里，不会被扫）

先确认你项目的 exclude 配的是什么：

```bash
grep -rn "exclude" vite.config.* | grep -i "components\|routes"
```

口诀：**专属子组件只能进 `components/`；纯逻辑/样式随意放专属目录根。**

### 3. 不能丢路由 / 菜单身份

入口里的 `defineOptions({ name: '...' })` 和 `definePage({ meta: {...} })` 是这个页面的路由名 + 菜单标题/图标/排序/权限来源。拆分**只搬运代码，这两块原样留在入口**，别一起搬走或改值，否则菜单项消失或路由名变。

### 4. 专属子组件不会被自动导入，必须显式 import

> 仅当用了组件自动导入（unplugin-vue-components）

自动导入通常只覆盖 `src/components/**` 等**约定目录**。`<页面名>/components/**` **不在扫描范围**，入口/父组件里用它必须显式 import：

```ts
// 入口 video-trim.vue
import TrimRangePanel from './video-trim/components/trim-range-panel.vue';
```

**这是最阴险的坑**：漏了 import，本地 lint / vue-tsc **静默通过**，只有浏览器运行时报 `[Vue warn]: Failed to resolve component` + 该块空白。

本 skill 的自检脚本会自动抓这一类（对比专属目录里每个组件的标签用法和 import），但它只覆盖**专属目录内**的组件——引用了别处私有组件的情况仍需跑一次页面确认。

## 拆什么、放哪：决策表

| 拆出来的东西 | 复用范围 | 落点 |
|---|---|---|
| 输入面板 / 结果展示块 / 配置区（.vue） | 仅本页面 | `<页面名>/components/`（复杂再分 `components/results/` 等） |
| 同上 | ≥2 个页面会用 | 项目公共组件目录（自动导入范围内） |
| 组合式逻辑（useXxx） | 仅本页面 | `<页面名>/composables/use-xxx.ts` |
| 同上 | ≥2 个页面会用 | 项目公共 `composables/` |
| 纯函数 / 类型 / 常量 | 仅本页面 | `<页面名>/xxx.ts` |
| 同上 | ≥2 个页面会用 | 项目公共 `utils.ts` / `types.ts` |
| `<style scoped>` 样式 | 仅本页面 | `<页面名>/<页面名>-scoped.css`，入口 `import` 引入 |
| 设计 token / 通用卡片 / 滚动条 | 全局 | 用项目已有的全局样式与 CSS 变量，别重写 |

## 样式拆分

入口里的 `<style scoped>` 抽成同级 `.css`，入口顶部 import：

```ts
// video-trim.vue <script setup> 顶部
import './video-trim/video-trim-scoped.css';
```

注意：抽出后是**普通 css（非 scoped）**，隔离靠原有的类名前缀。如果原样式重度依赖 `scoped` 的隔离、而类名又很通用（`.header` / `.panel` 这种），**别直接抽**——先给类名加页面前缀再抽，否则会污染全局。

各子组件自己的样式跟随子组件走 `<style scoped>`。

## 操作步骤

1. **探测项目配置**（见开头）+ **读全文** + **先查复用**：通读入口，列出可外移的块；grep 公共件，标出哪些其实该换成公共件。
2. **建专属目录**：`mkdir -p <页面名>/components`（按需再建 `composables/`）。
3. **先搬纯逻辑**（`.ts` / composable）：依赖少、最易搬，搬完入口改 import。
4. **再拆子组件**（`.vue` → `components/`）：一块一块搬，定义清楚 props/emit/slots 边界，入口里换成 `<子组件 v-bind/v-on/>` 并**显式 import**（约束 4）。一次搬一块、随手核对，不要一把梭。
5. **抽样式**：`<style scoped>` → `<页面名>/<页面名>-scoped.css`，入口 import。
6. **保留路由身份**：确认 `defineOptions` name、`definePage` meta 仍在入口、值未变（约束 3）。
7. **自检结构**：跑本 skill 的脚本（见下）。
8. **lint + 类型 + 跑页面**：跑项目自己的 lint / vue-tsc，再在浏览器打开页面确认无 `Failed to resolve component`、功能与拆前一致。

逐块搬、每搬一块就保证可编译，比"全拆完再统一修"安全得多——出问题时 diff 小、好定位。

## 验证

**结构自检脚本**：

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/vue-sfc-split/scripts/check-sfc-split.sh <平铺入口.vue 的路径>
```

传**平铺入口**的路径。脚本会先探测项目是否用了文件路由，只对适用的约束报错（手写路由表的项目不会被误报）。

检查项：

- 专属组件**模板用了但没 import**（❌，最重要）、没人用的孤儿组件（⚠️）
- 抽出的 css 里未加页面前缀的通用类名（⚠️，会污染全局）
- 入口行数是否收敛（⚠️）
- 仅文件路由项目：无 `index.vue`（❌）、专属 .vue 都在 `components/` 下（❌）、路由/菜单身份未丢（⚠️）

❌ 是硬性问题必须改，⚠️ 自行确认。

**跑页面**：脚本的漏 import 检查只覆盖专属目录内的组件，自动导入的盲区它看不全。拆完仍**建议在浏览器实际打开该页面**，确认每个外移块都正常渲染、控制台无 `Failed to resolve component`、交互与拆前一致。

## 行为零变更原则

拆分是**纯搬运 + 接线**，不顺手改逻辑、不"优化"算法、不调默认值。发现可改进点，先把拆分做完、验证通过，再单独提改进——把"重构结构"和"改行为"混在一起，出 bug 时无法判断是哪类改动引入的。

## 反例（禁止）

- ❌ 把入口挪进目录改名 `<页面名>/index.vue`（文件路由撞名报错）
- ❌ 专属 .vue 放在 `<页面名>/panel.vue`（components 外，被误扫成路由）
- ❌ 专属子组件不写 import 就在模板里用（运行时空白，lint 静默通过）
- ❌ 把只有本页面用的子组件平铺进公共组件目录（污染公共目录）
- ❌ 把项目已有的公共件又拆一份自己的
- ❌ 拆分时丢了 `defineOptions name` / `definePage meta`（菜单/路由消失）
- ❌ 边拆边改逻辑、调参数（行为变更混入结构变更）
- ❌ 把依赖 scoped 隔离的通用类名样式直接抽成全局 css（污染全局）

## 正例（推荐）

- ✅ `<页面名>.vue` 平铺入口 + `<页面名>/components/*.vue`（显式 import）+ `<页面名>/*.ts` + `<页面名>/<页面名>-scoped.css`
- ✅ ≥2 页面复用的件沉淀到项目公共目录
- ✅ 入口瘦身到只剩状态装配 + 组件编排
- ✅ 跑 `check-sfc-split.sh` 全绿 + 项目 lint 通过 + 浏览器实测无 resolve 警告
