# 插件详解

## 1. unplugin-vue-macros（核心，替代 vite-plugin-vue2）

**作用**: 在 Vue 2.7 上启用 `<script setup>` 及扩展宏语法。Vue 2.7 原生支持 Composition API，但 `<script setup>` 编译支持需要此插件。

**必须启用的宏**:
- `reactivityTransform: true` — 支持 `$ref`、`$computed` 等响应式语法糖（props 解构需要）
- `defineOptions: true` — 在 `<script setup>` 中使用 `defineOptions({ name: 'MyComp' })`
- `defineModels: true` — 简化 v-model 双向绑定

**必须禁用的宏**（Vue 2.7 已内置，开启会冲突）:
```typescript
defineProps: false,
defineEmit: false,
defineSlots: false,
shortEmits: false,
```

**挂载 vue2 插件的正确方式**:
```typescript
VueMacros({
  // ... 宏配置
  plugins: {
    vue: vue2(),   // ← 必须嵌套在这里，不能单独放在 plugins 数组
  },
})
```

---

## 2. unplugin-auto-import

**作用**: 自动导入 Vue API（ref、computed 等），让 `<script setup>` 中不用写 import 语句。

**关键配置 dts**:
```typescript
AutoImport({
  dts: path.resolve(__dirname, 'types/auto-imports.d.ts'),
})
```
首次运行会自动生成 `types/auto-imports.d.ts`，需加入 tsconfig 的 include，否则 TS 报错。

**tsconfig.json 需要包含**:
```json
{
  "include": ["types/**/*.d.ts", "src/**/*"]
}
```

**常见问题**: 如果 `defineProps`、`defineEmits` 报"未定义"，检查是否已生成 dts 文件。

---

## 3. @vitejs/plugin-legacy

**作用**: 为不支持 ES Module 的老设备（Android 4.4、iOS 9、Chrome 49）生成兼容包。

**配置要点**:
```typescript
legacy({
  targets: ['Android >= 4.4', 'Chrome >= 49', 'iOS >= 9'],
  additionalLegacyPolyfills: ['regenerator-runtime/runtime'],  // async/await 支持
  modernPolyfills: ['es/global-this'],   // 现代浏览器也需要的 polyfill
  // ignoreBrowserslistConfig: true,     // 旧版写法，新版不需要
})
```

**注意**: 新版（Vite 5 时代）已移除 `ignoreBrowserslistConfig`，直接用 `targets` 即可。

---

## 4. vite-plugin-html（createHtmlPlugin）

**作用**: 多入口 HTML 模板注入，支持 EJS 语法，实现 title、统计 ID 等按入口差异化注入。

**配置要点**:
```typescript
createHtmlPlugin({
  minify: true,
  entry: `/entrances/${ent}/index.ts`,   // 注意路径是相对于 root（src/）
  template: 'index.html',               // 相对于 root（src/index.html）
  inject: {
    data: {
      title: '页面标题',
      statId: '12345',
    },
  },
})
```

**HTML 中使用**: `<title><%= title %></title>`

---

## 5. vite-plugin-vue2-svg（createSvgPlugin）

**作用**: 将 SVG 文件作为 Vue 组件导入。

**使用方式**:
```typescript
import Icon from '@/components/ky-icon/icon.svg?component'
```

**注意**: 必须加 `?component` 查询参数，否则按普通文件处理。

---

## 6. rollup-plugin-visualizer

**作用**: 构建完成后自动打开浏览器显示 bundle 分析图，帮助定位体积过大的模块。

```typescript
visualizer({ open: true })
```

**建议**: 仅在需要分析时开启，CI 构建时可通过环境变量控制是否加载。

---

## 7. @sentry/vite-plugin（按需）

**作用**: 构建时自动上传 sourcemap 到 Sentry，方便生产环境错误追踪。

**重要**: `authToken` 不要硬编码在代码里，使用环境变量：
```typescript
sentryVitePlugin({
  authToken: process.env.SENTRY_AUTH_TOKEN,
  // ...
})
```

---

## 8. PostCSS 插件链

三个插件按顺序执行，顺序很重要：

1. **Autoprefixer** — 添加浏览器前缀
2. **postcss-plugin-tablet-adapter**（自定义）— 平板端 media query 适配
3. **postcss-px-to-viewport-8-plugin** — px 转 vw

**px 转 vw 配置**:
```typescript
pxToViewport({
  viewportWidth: 1080,    // 设计稿宽度（iPhone 设计稿通常 750，此项目用 1080）
  unitPrecision: 6,       // 小数点精度
  viewportUnit: 'vw',
  selectorBlackList: ['icon-song-border', 'poster-pic-border'],  // 不转换的选择器
  propList: ['*', '!filter'],  // !filter 表示 filter 属性不转换
})
```
