---
name: vue-sfc
description: Vue 3 单文件组件（.vue）通用编写规范
paths:
  - '**/*.vue'
checks:
  - no-with-defaults
  - no-v-if-with-v-for
  - v-for-needs-key
  - tsx-no-quoted-directive
  - tsx-no-kebab-component
---

# Vue SFC 规范（vft-kit 注入）

读写 `.vue` 文件时遵守以下规范。标注「自动检查」的条目会在保存后由 vft-kit 校验，违反 error 级会被退回修改。

## 1. `<script setup>`

- 统一 `<script setup lang="ts">`，需要写 JSX/TSX 时用 `lang="tsx"`。
- **Props 用解构声明默认值，不用 `withDefaults`**（Vue ≥ 3.5，自动检查 `no-with-defaults`）：

  ```ts
  // ✅
  const { size = 'default', disabled = false } = defineProps<{ size?: string; disabled?: boolean }>();
  // ❌
  const props = withDefaults(defineProps<{ size?: string }>(), { size: 'default' });
  ```

  解构出的 prop 在模板、`computed`、`watch(() => size)` 里保持响应式；传给 `watch` 时要包成 getter，不能直接传变量。
- `defineProps` / `defineEmits` / `defineModel` 放在 import 之后、其他逻辑之前。
- 脚本里对 `ref` / `computed` 做条件判断必须写 `.value`（`if (!isOpen.value)`）；对象恒为真，漏写不会报错但逻辑永远走同一分支。
- 模板 `ref="xxx"` 对应的变量用 `useTemplateRef('xxx')` 或同名 `ref()`，不要在 setup 同步阶段访问 DOM。

## 2. 模板

- **`v-if` 与 `v-for` 不能写在同一元素上**（自动检查 `no-v-if-with-v-for`）：外层包 `<template v-for>`，或先用 `computed` 过滤列表。
- **`v-for` 必须带 `:key`**，且用稳定业务 id，不用 index（自动检查 `v-for-needs-key`，warn 级）。
- 模板里不写复杂表达式（超过一个三元或含函数调用链），抽成 `computed`。
- 给指令传对象时（如 `v-loading="{ ... }"`），对象放进 `computed`，不要在模板里写字面量：指令 `updated` 钩子按引用比较，字面量每次渲染都是新对象。

## 3. TSX 渲染函数（`lang="tsx"` 的 script 内）

- **组件标签必须 PascalCase 并显式 import**（自动检查 `tsx-no-kebab-component`，warn 级）：`unplugin-vue-components` 只处理 SFC 模板，TSX 里写 `<el-button>` 会原样变成 `resolveComponent('el-button')`，未全局注册时运行时报 `Failed to resolve component`，渲染为空。
- **指令值不要再套引号**（自动检查 `tsx-no-quoted-directive`）：JSX 里 `v-auth="'a:b'"` 的值是带引号的字符串 `'a:b'`。写 `v-auth="a:b"` 或 `v-auth={'a:b'}`。
- 具名插槽用 children 对象：`<Comp>{{ reference: () => <Btn /> }}</Comp>`。

## 4. 响应式与副作用

- **能不用 `watch` 就不用**。`watch` 是命令式副作用，数据流隐式、易漏清理、易循环触发。先按下表找替代方案，都不适用再写 `watch`：

  | 场景 | 替代 `watch` 的写法 |
  |---|---|
  | 由其他状态派生的值 | `computed`（可写场景用 `computed({ get, set })`） |
  | 用户操作引发的变化（输入、切换、提交） | 在事件处理函数里直接处理，如 `@change` / `@update:modelValue` |
  | 父子双向绑定 | `defineModel()`，不要 `watch` prop 再 `emit` |
  | prop 变化后重置内部状态 | 父组件给子组件换 `:key` 重建实例 |
  | 参数变化后重新请求 | 在触发参数变化的函数里调用请求；或用请求库自带的依赖刷新（如 vue-request 的 `refreshDeps`） |
  | 初始化逻辑 | `onMounted` 或 setup 顶层直接执行，不要 `watch(..., { immediate: true })` 代替 |

- 确需 `watch` 的场景：同步外部系统（DOM API、第三方实例、`localStorage`、路由查询参数）、异步副作用无法挂到单一事件入口。此时：
  - 只监听需要的字段（getter `() => obj.id`），不要 `deep: true` 监听整个对象。
  - 异步回调用 `onCleanup`（或 `onWatcherCleanup`）处理竞态。
  - 回调里不要回写被监听的源，避免循环触发。
- `watch` 全局状态（路由、store）时，确认组件是否被 keep-alive 缓存：失活实例的 watch 仍会触发。
- SSR 项目中，setup 顶层（含其同步调用的函数）不要直接访问 `window` / `document` / `localStorage` / `matchMedia`；放进 `onMounted` 或加 `typeof window !== 'undefined'` 守卫。

## 5. 样式

- 组件样式默认 `scoped`；改子组件内部样式用 `:deep()`，不要去掉 scoped。
- 颜色、间距优先用设计变量（CSS 变量 / 主题 token），不写死品牌色。

## 6. 组件复用

- **相同样式的结构必须抽成一个组件复用**，不要复制模板和样式再改几个字。出现第二处相同结构时就抽，不要等到第三处。
- **差异能用参数表达的，不要写第二个组件**：
  - 文案、图标、颜色、尺寸、状态等差异用 props。
  - 局部内容不同用插槽（默认插槽 / 具名插槽），不要为一块内容再复制整个组件。
  - 行为差异用 emit 抛给父组件处理，不要在组件内按调用方写 `if` 分支。
  - 外观变体用 `type` / `size` / `variant` 这类枚举 prop 加 class 修饰，不拆成 `XxxPrimary.vue`、`XxxSmall.vue`。
- 新写组件前先搜项目里有没有同类组件（`components/`、组件库、同目录 `components/`）。已有组件差一点时，扩展它的 props 或插槽，不要另起一个相似组件。
- 放置位置：只在一个页面内复用的，放该页面目录下的 `components/`；跨页面复用的，放项目公共 `components/`。
- 只抽样式相同的部分。两处只是碰巧长得像、业务含义不同且会分别演变的，不要强行合并成一个充满开关参数的组件；判断标准是 props 里出现大量互斥开关时，说明抽错了。

## 7. 大文件 SFC 拆分

当一个页面组件同时包含多个面板、结果块、组合式逻辑和大段样式时，按职责和复用边界拆分；入口只保留状态装配与组件编排。拆分是结构调整，保持行为、默认值和路由身份不变。

- 先查项目公共组件、composables、utils 和类型，已有能力直接复用；只在本页面使用的内容放到同级专属目录 `<页面名>/`，跨页面复用的内容放到项目公共目录。
- 使用文件路由（如 `unplugin-vue-router`）时，入口保持平铺的 `<页面名>.vue`，禁止改成 `<页面名>/index.vue`；专属 `.vue` 只能放在 `<页面名>/components/` 下，避免被路由扫描成页面。
- 使用组件自动导入时，专属目录通常不在自动导入范围内，模板引用的专属组件必须显式 `import`。
- `defineOptions({ name })` 和 `definePage({ meta })` 保留在入口，不能因拆分改变路由名、菜单标题、图标、排序或权限。
- `<style scoped>` 抽成独立 CSS 后不再受 scoped 隔离，顶层类名加页面前缀；通用设计 token 使用项目已有的全局变量，不重复定义。
- 先完成纯搬运和接线，再单独处理行为优化；不要把结构拆分与业务逻辑改动混在同一批修改中。

## 项目覆盖

项目根放 `.claude/vft-rules.json` 可以关闭本规则或调整单项检查级别：

```json
{
  "disable": ["vue-sfc"],
  "checks": { "v-for-needs-key": "off", "tsx-no-kebab-component": "error" }
}
```
