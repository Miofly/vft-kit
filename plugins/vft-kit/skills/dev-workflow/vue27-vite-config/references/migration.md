# 从 Vue 2.6 迁移到 Vue 2.7 完整指南

## 迁移概览

| 变更项 | 旧版 | 新版 |
|---|---|---|
| Vue 版本 | 2.6.x | 2.7.x |
| 组合式 API | `@vue/composition-api` | 内置，无需额外安装 |
| Vite Vue 插件 | `vite-plugin-vue2` | `unplugin-vue-macros` + `@vitejs/plugin-vue2` |
| `<script setup>` | 不支持 | 支持（via VueMacros） |
| CSS 预处理 | LESS | SCSS |
| API 自动导入 | 手动 import | `unplugin-auto-import` |

---

## 步骤一：更新依赖

**移除旧依赖**:
```bash
pnpm remove @vue/composition-api vite-plugin-vue2
```

**安装新依赖**:
```bash
pnpm add vue@2.7
pnpm add -D unplugin-vue-macros @vitejs/plugin-vue2 unplugin-auto-import
pnpm add -D sass  # 替换 less
```

---

## 步骤二：清理 @vue/composition-api 的引用

Vue 2.7 已内置 Composition API，移除所有来自 `@vue/composition-api` 的导入：

```typescript
// 旧
import { ref, computed } from '@vue/composition-api'

// 新（或配合 auto-import 直接不写 import）
import { ref, computed } from 'vue'
```

用全局搜索替换：
```bash
grep -r "@vue/composition-api" src/ --include="*.ts" --include="*.vue"
```

---

## 步骤三：更新 vite.config.ts

核心变更：

```typescript
// 旧
import { createVuePlugin } from 'vite-plugin-vue2'

plugins: [
  createVuePlugin(),
  // ...
]

// 新
import VueMacros from 'unplugin-vue-macros/vite'
import vue2 from '@vitejs/plugin-vue2'

plugins: [
  VueMacros({
    // ...宏配置
    plugins: { vue: vue2() },  // vue2 插件必须嵌套在 VueMacros 内
  }),
  // ...
]
```

**build 配置变更**:
```typescript
// 旧（已废弃）
build: {
  polyfillModulePreload: true,
}

// 新
build: {
  modulePreload: { polyfill: true },
}
```

**新增 optimizeDeps**:
```typescript
optimizeDeps: {
  exclude: ['vue-demi'],  // Vue 2.7 不需要 vue-demi
}
```

---

## 步骤四：更新 tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "Node",
    "strict": true,
    "jsx": "preserve",
    "lib": ["ESNext", "DOM"],
    "paths": {
      "@/*": ["./src/*"],
      "#/*": ["./types/*"]
    }
  },
  "include": [
    "src/**/*",
    "types/**/*.d.ts",
    "site.config.ts",
    "vite.config.ts"
  ],
  "vueCompilerOptions": {
    "target": 2.7
  }
}
```

**关键**: `vueCompilerOptions.target: 2.7` 告诉 vue-tsc 使用 Vue 2.7 的类型系统。

---

## 步骤五：样式从 LESS 迁移到 SCSS

1. 将 `.less` 文件重命名为 `.scss`
2. 语法差异：
   - 变量：`@primary: red` → `$primary: red`
   - 混入：`#mixin` → `@mixin name` / `@include name`
   - 导入：`@import` 语法基本相同，但推荐用 `@use` / `@forward`

3. vite.config.ts 中 PostCSS stylelint 的 less 规则改为 scss 规则

---

## 常见迁移陷阱

### 1. vue-demi 冲突
**现象**: 控制台出现 `vue-demi` 相关警告
**原因**: Vant 等旧库依赖 vue-demi，但 Vue 2.7 环境下 vue-demi 的行为不同
**解决**: `optimizeDeps: { exclude: ['vue-demi'] }`

### 2. defineProps 类型推断失效
**现象**: TypeScript 不能识别 `defineProps` 返回的类型
**原因**: auto-imports.d.ts 未生成或 tsconfig 未包含
**解决**: 运行一次 `pnpm dev`，检查 `types/auto-imports.d.ts` 是否生成

### 3. inject/provide 类型错误
**现象**: `inject('key')` 返回 `unknown`
**原因**: 没有使用 `InjectionKey` 泛型
**解决**:
```typescript
// 定义 key
const playerKey: InjectionKey<PlayerInstance> = Symbol('player')

// provide
provide(playerKey, player)

// inject（有类型推断）
const player = inject(playerKey)!
```

### 4. ESLint vue/component-api-setup-return 规则
**现象**: 使用 `<script setup>` 时 ESLint 报错
**原因**: 旧版 ESLint 规则要求 setup() return，但 `<script setup>` 不需要
**解决**: 更新 eslint-plugin-vue 到支持 Vue 2.7 的版本，或关闭该规则
