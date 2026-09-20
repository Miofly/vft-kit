# 进阶插件与工具详解（来自 h5-ring-pro）

本文档补充 h5-ring-pro 中更完整的生产级配置，是 plugins.md 的进阶篇。

---

## 目录

1. [unplugin-vue-components — Vant 按需自动导入](#1-unplugin-vue-components--vant-按需自动导入)
2. [@vitejs/plugin-vue2-jsx — JSX 支持](#2-vitejsplugin-vue2-jsx--jsx-支持)
3. [vite-plugin-checker — 开发时类型 + Lint 检查](#3-vite-plugin-checker--开发时类型--lint-检查)
4. [vite-plugin-html-template-mpa — 多页面 HTML 模板](#4-vite-plugin-html-template-mpa--多页面-html-模板)
5. [vite-plugin-vconsole-mpa — 开发调试工具](#5-vite-plugin-vconsole-mpa--开发调试工具)
6. [vite-plugin-externals — 外部依赖声明](#6-vite-plugin-externals--外部依赖声明)
7. [vite-plugin-magic-preloader — 资源预加载](#7-vite-plugin-magic-preloader--资源预加载)
8. [vite-plugin-devtools-json — DevTools 集成](#8-vite-plugin-devtools-json--devtools-集成)
9. [fileImportReplace — 自定义文件覆盖插件](#9-fileimportreplace--自定义文件覆盖插件)
10. [nightMode — 暗模式自动生成插件](#10-nightmode--暗模式自动生成插件)
11. [postcssRTL — RTL 国际化 PostCSS 插件](#11-postcssrtl--rtl-国际化-postcss-插件)
12. [mediaPxTransform — 媒体断点响应式插件](#12-mediapxtransform--媒体断点响应式插件)
13. [ViteEnv — 环境变量规范化](#13-viteenv--环境变量规范化)
14. [mergeConfig — 可扩展配置工厂模式](#14-mergeconfig--可扩展配置工厂模式)

---

## 1. unplugin-vue-components — Vant 按需自动导入

**作用**: 检测模板中使用的组件名，自动导入对应的组件及其样式，无需手动 `import`。

**Vant 2.x 的正确配置方式** (kebabCase 转换):
```typescript
import Components from 'unplugin-vue-components/vite';
import { kebabCase } from 'lodash-es';

Components({
  resolvers: [
    (name: string) => {
      if (name.startsWith('Van')) {
        const partialName = kebabCase(name.slice(3));  // VanButton → button
        return {
          from: `vant/lib/${partialName}`,
          sideEffects: `vant/lib/${partialName}/style`,
        };
      }
    },
  ],
  dts: resolve(root, './types/components.d.ts'),
})
```

**注意**: Vant 2.x 不能直接用 `VantResolver`，需要自定义 resolver。`VantResolver` 适用于 Vant 3+/4+。

**dts 生成**: 首次运行后自动生成 `types/components.d.ts`，需加入 tsconfig `include`。

---

## 2. @vitejs/plugin-vue2-jsx — JSX 支持

**作用**: 在 Vue 2.7 中使用 JSX/TSX 语法。

**配置方式** (必须嵌套在 VueMacros 内):
```typescript
import vue2Jsx from '@vitejs/plugin-vue2-jsx';

VueMacros({
  // ...
  plugins: {
    vue: vue2(),
    vueJsx: vue2Jsx(),   // ← 与 vue2() 并列
  },
})
```

**使用场景**: render 函数、函数式组件、动态组件封装等场景。

---

## 3. vite-plugin-checker — 开发时类型 + Lint 检查

**作用**: 在开发服务器运行时，在浏览器 overlay 和终端中实时显示 TypeScript 错误和 Stylelint 错误，不需要等构建时才发现。

```typescript
import checker from 'vite-plugin-checker';

checker({
  typescript: true,    // TS 类型检查
  vueTsc: true,        // Vue SFC 中的类型检查
  stylelint: {
    lintCommand: `stylelint ${resolve(projRoot, '**/*.{scss,less,vue}')}`,
  },
  overlay: false,      // 关闭浏览器弹窗（只在终端显示）
})
```

**与 vite-plugin-eslint 的区别**:
- `vite-plugin-checker` — 开发时实时检查，TypeScript 感知
- `vite-plugin-eslint` — 每次文件变化时运行 ESLint

建议同时使用，checker 专注类型，eslint 插件专注代码规范：
```typescript
// 仅开发环境加载 ESLint 插件（构建时由 CI 跑）
if (!isBuild) {
  vitePlugins.push(
    eslintPlugin({
      fix: false,
      include: ['**/*.{js,jsx,ts,tsx,vue}'],
      exclude: ['**/node_modules/**', '**/dist/**'],
      failOnError: false,
    })
  );
}
```

---

## 4. vite-plugin-html-template-mpa — 多页面 HTML 模板

**作用**: 比 `vite-plugin-html` 更强大的多页面 HTML 注入，支持 Handlebars (`.hbs`) 模板。

```typescript
import htmlTemplate from 'vite-plugin-html-template-mpa';

htmlTemplate({
  minify: isBuild,
  template: getExistenceHtml(page),    // 动态选择 HTML 模板文件
  buildCfg: {
    moveHtmlTop: false,                 // 不把 HTML 移到顶层
  },
  inject: {
    data: {
      ssrConfig: getPublicFileContent('ssr.hbs'),   // 读取公共 hbs 片段
      commonScript: isDev
        ? `<script src="/globalConfig.js"></script>`
        : getPublicFileContent('index.hbs'),
    },
  },
})
```

**模板文件查找逻辑**: 优先使用当前项目 `public/` 下的 HTML，不存在时回退到公共 business 包的 HTML。这支持多主题项目里各主题定制 HTML 的需求。

---

## 5. vite-plugin-vconsole-mpa — 开发调试工具

**作用**: 根据环境变量自动注入 VConsole，不需要手动在 HTML 中写 script 标签。

```typescript
import viteVConsole from 'vite-plugin-vconsole-mpa';

// 只在 VITE_OPEN_VCONSOLE=true 时启用
VITE_OPEN_VCONSOLE && vitePlugins.push(
  viteVConsole({
    enabled: VITE_OPEN_VCONSOLE,
    config: {
      maxLogNumber: 1000,
      theme: 'light',
    },
  })
);
```

**与手动注入的区别**: 插件方式更干净，不污染 HTML 模板，通过 `.env` 文件控制。

---

## 6. vite-plugin-externals — 外部依赖声明

**作用**: 将某些依赖从 bundle 中排除，改为运行时从全局变量读取（对应 HTML 里的 `<script>` CDN 引用）。

```typescript
import { viteExternalsPlugin } from 'vite-plugin-externals';

viteExternalsPlugin({
  '@h5-order/sdk': 'ordersdk',  // import x from '@h5-order/sdk' → window.ordersdk
})
```

**适用场景**: Native SDK、大型第三方库通过 App WebView 注入到 `window` 的情况。

---

## 7. vite-plugin-magic-preloader — 资源预加载

**作用**: 自动分析构建产物，为关键资源生成 `<link rel="preload">` 标签，提升首屏加载速度。

```typescript
import magicPreloader from 'vite-plugin-magic-preloader';

magicPreloader()   // 零配置使用
```

---

## 8. vite-plugin-devtools-json — DevTools 集成

**作用**: 生成 `.well-known/appspecific/com.chrome.devtools.json`，让 Chrome DevTools 自动识别项目信息。

```typescript
import devtoolsJson from 'vite-plugin-devtools-json';

devtoolsJson()
```

---

## 9. fileImportReplace — 自定义文件覆盖插件

**这是整个包中最核心的自定义插件**，解决多主题/皮肤系统中文件按优先级查找的问题。

**问题背景**: 项目分为 business（公共基础包）和各主题包。主题包中不存在的文件应自动 fallback 到 business 包。同时支持皮肤（skin）覆盖主题文件。

**优先级**: `皮肤文件 > 主题文件 > business 文件`

**配置方式**:
```typescript
fileImportReplace({
  pattern: /~?@.*\.(less|css|scss|sass|svg|png|jpg|gif|jpeg|vue|ts)/,
  fallbackPath: [
    // 皮肤文件（useWhenPatternNotFound: false = 强制覆盖，不管主题文件存不存在）
    skin ? {
      path: `./src/skin/${skin}`,
      useWhenPatternNotFound: false,
    } : undefined,
    // business 兜底（useWhenPatternNotFound: true = 仅文件不存在时才用）
    {
      path: resolve(businessRoot, 'src'),
    },
  ].filter(Boolean),
})
```

**附带能力**: 插件的 `transform` 钩子还处理了以下内容：
1. CSS 中 `url(@/images/xxx.png)` 的路径替换（按皮肤/主题/business 优先级）
2. 如果存在暗模式变量文件，自动调用 `nightMode` 处理所有 `.less` 文件

---

## 10. nightMode — 暗模式自动生成插件

**作用**: 不需要手写 `@media (prefers-color-scheme: dark)` 或 `.night-mode` 覆盖样式。只需维护一份 `src/css/night-mode/variables.less`，插件自动将 Less 变量中涉及暗模式颜色的地方生成 `.night-mode` 覆盖样式。

**工作原理**:
1. 读取 `variables.less`（正常模式）和 `night-mode/variables.less`（暗模式）的所有变量
2. 对每个 `.less` 文件，先用 less.render 编译（将变量替换为 `"@变量名"` 字符串以防报错）
3. 用 PostCSS 遍历所有声明，找到含变量的属性
4. 对比正常模式和暗模式变量值，生成差异部分的 `.night-mode .selector { prop: dark-value }` 覆盖规则
5. 附加到编译后的 CSS 末尾

**暗模式激活方式**: 在根节点（`#app` 的父级）添加 `.night-mode` class。

**注意**: 当 `variables.less` 文件变更时，插件会自动重启 dev server 更新变量缓存。

---

## 11. postcssRTL — RTL 国际化 PostCSS 插件

**作用**: 自动将 LTR（从左到右）的 CSS 转换为 RTL（从右到左）的覆盖样式，用于阿拉伯语等 RTL 语言适配。

**处理的属性类型**:
- 属性名互换：`margin-left` ↔ `margin-right`，`left` ↔ `right` 等
- 属性值互换：`text-align: left` → `text-align: right`
- 四值简写翻转：`margin: 10px 20px 10px 30px` → `margin: 10px 30px 10px 20px`
- transform 翻转：`translateX(10px)` → `translateX(-10px)`
- shadow 翻转：`box-shadow: 2px 0 4px` → `box-shadow: -2px 0 4px`
- `background-position`、`transform-origin` 翻转

**配置**:
```typescript
import { postcssRTL } from './plugins/postcss-rtl';

// 在 postcss plugins 中（按需启用）
VITE_OPEN_POSTCSS_RTL ? postcssRTL({
  rtlClass: 'rtl',           // RTL 激活的 class 名
  exclude: [],               // 排除某些选择器
  debug: false,
  injectGlobalStyles: true,  // 注入 .rtl { direction: rtl }
  injectInFiles: ['base.less'],  // 只在这些文件注入全局样式
}) : undefined
```

**RTL 激活方式**: 在根节点添加 `.rtl` class，所有生成的覆盖规则自动生效。

---

## 12. mediaPxTransform — 媒体断点响应式插件

**作用**: 替代 px-to-vw 的另一种响应式方案。对每个断点生成 `@media (min-width: Xpx)` 规则，将 px 值按断点比例缩放，适合需要精确像素控制而不想用 vw 的场景。

```typescript
import { mediaPxTransform } from './plugins/mediaPxTransform';

// 环境变量控制是否开启
VITE_OPEN_POSTCSS_MEDIA ? mediaPxTransform(
  [500, 620, 748, 900, 1100],  // 断点列表（px）
  360,                          // 基准宽度
) : undefined
```

**原理**: 设计稿基于 360px，在 500px 屏幕时，所有 px 值乘以 `360/500 = 0.72`，以此类推，生成对应 media query 规则。

---

## 13. ViteEnv — 环境变量规范化

`wrapperEnv` 函数将 `.env` 文件中的字符串自动转换为正确的类型：

```typescript
// .env
VITE_PORT=8890            → number: 8890
VITE_DROP_CONSOLE=true    → boolean: true
VITE_OPEN_VCONSOLE=false  → boolean: false
```

**完整环境变量清单** (ViteEnv 接口):
| 变量 | 类型 | 说明 |
|---|---|---|
| `VITE_DROP_CONSOLE` | boolean | 构建时移除 console.log |
| `VITE_AUTO_OPEN` | boolean | 启动后自动打开浏览器 |
| `VITE_PORT` | number | 开发服务器端口 |
| `VITE_OPEN_VCONSOLE` | boolean | 是否注入 VConsole |
| `VITE_OPEN_POSTCSS_VW` | boolean | 是否启用 px → vw 转换 |
| `VITE_OPEN_POSTCSS_RTL` | boolean | 是否启用 RTL 转换 |
| `VITE_OPEN_POSTCSS_MEDIA` | boolean | 是否启用媒体断点响应式 |
| `VITE_VW_BASE_VALUE` | number | vw 转换的设计稿基准宽度 |
| `VITE_BUILD_FILE_MIGRATE` | boolean | 构建后是否迁移文件 |
| `VITE_SENTRY_ORG` | string | Sentry 组织名 |
| `VITE_SENTRY_PROJECT` | string | Sentry 项目名 |
| `VITE_SENTRY_DSN` | string | Sentry DSN |

---

## 14. mergeConfig — 可扩展配置工厂模式

h5-ring-pro 的 `createViteConfig` 函数展示了一种优雅的"配置工厂"模式，适合 monorepo 中多个主题包共享基础配置：

```typescript
export function createViteConfig(
  viteConfig: UserConfig | Promise<UserConfig> = {},
  customConfig?: CustomViteConfig,
): UserConfigExport {
  // ...
  const commonConfig = { /* 公共配置 */ };

  // 如果没有自定义配置，直接返回公共配置
  if (isEmptyObject(viteConfig)) {
    return commonConfig;
  }

  // 有自定义配置时，深度合并（plugins 数组会合并而非覆盖）
  return mergeConfig(commonConfig, viteConfig);
}
```

**各主题包使用方式**:
```typescript
// packages/theme-foo/vite.config.ts
import { createViteConfig } from '@ky/vite';

export default createViteConfig({
  // 仅覆盖差异部分
  css: {
    preprocessorOptions: {
      less: {
        additionalData: `@import "./src/css/foo-overrides.less";`,
      },
    },
  },
}, {
  // 自定义 HTML 相关（loading 图、背景色）
  themeSkinConfig: {
    default: { htmlBgColor: '#f5f5f5' },
    dark: { htmlBgColor: '#1a1a1a' },
  },
});
```

**`mergeConfig` 的合并规则**:
- `plugins` 数组：合并（不覆盖）
- `resolve.alias`：合并
- 基本值（string、boolean、number）：后者覆盖前者
- 嵌套对象：递归合并
