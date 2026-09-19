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

- 能在事件或提交时转换的数据不要用 `watch` 实时转换。
- `watch` 全局状态（路由、store）时，确认组件是否被 keep-alive 缓存：失活实例的 watch 仍会触发。
- SSR 项目中，setup 顶层（含其同步调用的函数）不要直接访问 `window` / `document` / `localStorage` / `matchMedia`；放进 `onMounted` 或加 `typeof window !== 'undefined'` 守卫。

## 5. 样式

- 组件样式默认 `scoped`；改子组件内部样式用 `:deep()`，不要去掉 scoped。
- 颜色、间距优先用设计变量（CSS 变量 / 主题 token），不写死品牌色。

## 项目覆盖

项目根放 `.claude/vft-rules.json` 可以关闭本规则或调整单项检查级别：

```json
{
  "disable": ["vue-sfc"],
  "checks": { "v-for-needs-key": "off", "tsx-no-kebab-component": "error" }
}
```
