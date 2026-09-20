# Vue 2.7 + Vite 5 标准配置 Skill

## 📋 简介

这是一个用于 Vue 2.7 + Vite 5 项目的标准配置 Skill，提供完整的脚手架生成和配置咨询能力。

## 🎯 适用场景

### 1. 创建新项目
当你需要快速搭建一个 Vue 2.7 + Vite 5 项目时，直接说：
- "创建 Vue 2.7 项目"
- "初始化 Vue 2.7"
- "搭建 Vue 2.7"

AI 会自动执行脚手架流程，生成包含以下特性的完整项目：
- ✅ `<script setup>` 语法支持
- ✅ TypeScript 配置
- ✅ API 自动导入（ref、computed 等无需 import）
- ✅ 组件自动注册
- ✅ PostCSS px 转 vw
- ✅ Legacy 浏览器兼容
- ✅ ESLint + Prettier
- ✅ 完整的类型声明

### 2. 配置咨询
当你遇到以下问题时，可以直接询问：
- "Vue 2.7 如何配置 unplugin-vue-macros？"
- "unplugin-auto-import 的 dts 怎么配置？"
- "PostCSS px 转 vw 怎么设置？"
- "如何配置 legacy 兼容老设备？"
- "组件自动注册怎么做？"

### 3. 从 Vue 2.6 迁移
如果你有现有的 Vue 2.6 项目需要升级到 2.7，可以询问：
- "如何从 Vue 2.6 迁移到 2.7？"
- "Vue 2.7 迁移有哪些注意事项？"

## 📦 核心技术栈

| 技术 | 版本 | 说明 |
|------|------|------|
| Vue | 2.7.x | 内置 Composition API |
| Vite | 5.2.x | 构建工具 |
| TypeScript | 5.2.x | 类型支持 |
| unplugin-vue-macros | 2.9.x | 启用 `<script setup>` |
| unplugin-auto-import | 0.17.x | API 自动导入 |
| unplugin-vue-components | 0.26.x | 组件自动注册 |

## 🚀 快速开始

### 方式一：通过 AI 创建（推荐）

直接对 AI 说：
```
创建一个 Vue 2.7 项目，项目名叫 my-app
```

AI 会自动生成完整的项目结构。

### 方式二：手动参考配置

查看 `SKILL.md` 中的「项目脚手架」章节，按步骤手动创建。

## 📚 参考文档

本 Skill 包含以下参考文档：

- **`SKILL.md`** - Skill 定义和完整脚手架流程
- **`references/plugins.md`** - 核心插件详解（VueMacros、AutoImport 等）
- **`references/advanced-plugins.md`** - 进阶插件（Vant 按需导入、JSX、Checker 等）
- **`references/migration.md`** - Vue 2.6 → 2.7 迁移指南
- **`references/build-optimization.md`** - 构建优化策略

## 🔧 核心配置要点

### 1. VueMacros 必须嵌套 vue2 插件

```typescript
import VueMacros from 'unplugin-vue-macros/vite'
import vue2 from '@vitejs/plugin-vue2'

VueMacros({
  plugins: {
    vue: vue2(),  // ← 必须嵌套在这里
  },
})
```

### 2. 排除 vue-demi

```typescript
optimizeDeps: {
  exclude: ['vue-demi'],  // Vue 2.7 不需要
}
```

### 3. TypeScript 配置

```json
{
  "vueCompilerOptions": {
    "target": 2.7  // ← 关键配置
  }
}
```

## ⚠️ 常见问题

### Q: defineProps 报"未定义"错误？
A: 检查 `types/auto-imports.d.ts` 是否生成，并确保 tsconfig 的 `include` 包含了 `types/**/*.d.ts`。

### Q: vue-demi 警告？
A: 在 `vite.config.ts` 中添加 `optimizeDeps: { exclude: ['vue-demi'] }`。

### Q: 为什么不能用 @vue/composition-api？
A: Vue 2.7 已内置 Composition API，不需要也不应该安装 `@vue/composition-api`。

### Q: ESLint 报 setup() return 错误？
A: 使用 `<script setup>` 时不需要 return，更新 `eslint-plugin-vue` 到支持 Vue 2.7 的版本。

## 📝 命名规范

本 Skill 遵循 KY AI Team 的命名规范：
- 目录名：`vue27-vite-config`（kebab-case）
- 分支名：`{域账号}_{日期}_skill_{功能}`

## 🤝 贡献

如需改进此 Skill，请：
1. 创建分支：`{你的域账号}_YYYYMMDD_skill_vue27_update`
2. 修改后提交 PR
3. 等待前端负责人审查

## 📄 许可

内部使用，遵循团队规范。
