---
name: vue27-vite-config
description: Vue 2.7 + Vite 5 标准项目配置与脚手架。当用户询问 Vue 2.7 的 Vite 配置、插件选型、unplugin-vue-macros、unplugin-auto-import、PostCSS px 转 vw、legacy 兼容、组件自动注册等问题时使用。也用于从 Vue 2.6 迁移到 Vue 2.7。当用户说"创建 Vue 2.7 项目"、"初始化 Vue 2.7"、"搭建 Vue 2.7"时，主动执行脚手架流程生成完整项目结构。
---

# Vue 2.7 + Vite 5 标准配置 Skill

## 两种使用模式

1. **脚手架创建** — 用户要创建新项目，执行下方「项目脚手架」流程生成完整项目
2. **集成 Vite 配置** — 为现有项目集成或更新 Vite 配置，回答插件或配置项问题

## 快速模式行为

在快速模式下（fast mode）：
- **不要询问项目目录名称**，直接使用默认名称 `vue27-project`
- 如果用户明确指定了项目名称，使用用户指定的名称
- 直接开始生成项目文件，无需等待用户确认

---

## 核心架构原则

Vue 2.7 内置 Composition API，不再需要 `@vue/composition-api`。关键插件组合：

- `unplugin-vue-macros` — 在 Vue 2.7 上启用 `<script setup>`，**必须**将 `@vitejs/plugin-vue2` 嵌套在其 `plugins.vue` 内
- `unplugin-auto-import` — Vue API 自动导入，免手写 import
- `unplugin-vue-components` — 组件自动注册，含 UI 库按需导入
- `optimizeDeps.exclude: ['vue-demi']` — Vue 2.7 不需要 vue-demi，排除避免警告

## 插件选型对照

| 功能 | Vue 2.6 旧版 | Vue 2.7 新版 |
|---|---|---|
| Vue 编译 | `vite-plugin-vue2` | `unplugin-vue-macros` + `@vitejs/plugin-vue2` |
| `<script setup>` | 不支持 | VueMacros 启用 |
| API 自动导入 | 无 | `unplugin-auto-import` |
| 组件自动注册 | 无 | `unplugin-vue-components` |
| HTML 模板 | `vite-plugin-html` | `vite-plugin-html-template-mpa` |
| 开发时类型检查 | 无 | `vite-plugin-checker` |
| `build.polyfillModulePreload` | 旧 API（已废弃） | `build.modulePreload.polyfill` |

## 经过验证的依赖版本

```json
{
  "devDependencies": {
    "vite": "5.2.6",
    "typescript": "5.2.2",
    "unplugin-vue-macros": "2.9.5",
    "@vitejs/plugin-vue2": "2.3.1",
    "@vitejs/plugin-vue2-jsx": "1.1.1",
    "unplugin-auto-import": "0.17.5",
    "unplugin-vue-components": "0.26.0",
    "@vitejs/plugin-legacy": "5.3.2",
    "vite-plugin-checker": "0.6.2",
    "vite-plugin-html-template-mpa": "1.0.28",
    "vite-plugin-vconsole-mpa": "0.0.8",
    "vite-plugin-eslint": "1.8.1",
    "vite-plugin-externals": "0.6.2",
    "vite-plugin-devtools-json": "0.0.3",
    "rollup-plugin-visualizer": "5.14.0",
    "autoprefixer": "10.4.19",
    "postcss-px-to-viewport-8-plugin": "1.2.5",
    "@types/node": "20.11.30",
    "vue-demi": "0.14.7",
    "@typescript-eslint/eslint-plugin": "6.7.2",
    "@typescript-eslint/parser": "6.7.2",
    "eslint": "8.43.0",
    "eslint-config-prettier": "8.8.0",
    "eslint-define-config": "1.21.0",
    "eslint-plugin-import": "2.27.5",
    "eslint-plugin-jsonc": "2.9.0",
    "eslint-plugin-n": "16.0.0",
    "eslint-plugin-prettier": "4.2.1",
    "eslint-plugin-regexp": "1.15.0",
    "eslint-plugin-simple-import-sort": "10.0.0",
    "eslint-plugin-only-warn": "1.1.0",
    "eslint-plugin-vue": "9.15.1",
    "jsonc-eslint-parser": "2.3.0",
    "vue-eslint-parser": "9.3.1",
    "@commitlint/cli": "17.6.6",
    "@commitlint/config-conventional": "17.6.6",
    "commitizen": "4.3.0",
    "lint-staged": "8.1.5",
    "postcss": "8.4.23",
    "postcss-html": "1.5.0",
    "postcss-less": "6.0.0",
    "postcss-scss": "4.0.6",
    "prettier": "2.8.8",
    "stylelint": "10.1.0",
    "stylelint-config-rational-order": "0.1.2",
    "stylelint-config-recommended": "2.2.0",
    "stylelint-order": "3.0.0",
    "stylelint-performance-animation": "1.2.2"
  },
  "dependencies": {
    "vue": "2.7.16"
  },
  "optionalDependencies_注释": "以下为可选，按需添加",
  "optionalDependencies": {
    "vue-router": "3.6.5",
    "pinia": "2.1.7",
    "vant": "2.13.2",
    "less": "4.2.0",
    "sass": "1.97.3"
  },
  "volta": {
    "node": "16.18.1",
    "pnpm": "8.3.1"
  }
}
```

---

## 标准 vite.config.ts

```typescript
import { defineConfig, loadEnv } from 'vite';
import path, { resolve } from 'path';
import legacy from '@vitejs/plugin-legacy';
import VueMacros from 'unplugin-vue-macros/vite';
import vue2 from '@vitejs/plugin-vue2';
import AutoImport from 'unplugin-auto-import/vite';
import Components from 'unplugin-vue-components/vite';
import { visualizer } from 'rollup-plugin-visualizer';
import htmlTemplate from 'vite-plugin-html-template-mpa';
import { createSvgPlugin } from 'vite-plugin-vue2-svg';
import { sentryVitePlugin } from '@sentry/vite-plugin';
import checker from 'vite-plugin-checker';
import Autoprefixer from 'autoprefixer';
// @ts-ignore
import pxToViewport from 'postcss-px-to-viewport-8-plugin';

// 将 .env 字符串变量转换为正确类型（'true'→true，'8890'→8890）
function wrapperEnv(env: Record<string, string>) {
  const result: Record<string, any> = {};
  for (const key of Object.keys(env)) {
    let val: any = env[key];
    if (val === 'true') val = true;
    else if (val === 'false') val = false;
    else if (!isNaN(Number(val)) && val !== '') val = Number(val);
    result[key] = val;
  }
  return result as {
    VITE_DROP_CONSOLE: boolean;
    VITE_PORT: number;
    VITE_AUTO_OPEN: boolean;
    VITE_OPEN_POSTCSS_VW: boolean;
    VITE_VW_BASE_VALUE: number;
    VITE_SENTRY_ORG: string;
    VITE_SENTRY_PROJECT: string;
    [key: string]: any;
  };
}

// @ts-ignore
export default defineConfig(({ command, mode = 'production' }) => {
  const isBuild = command === 'build';
  const env = loadEnv(mode, process.cwd());

  const {
    VITE_DROP_CONSOLE = false,
    VITE_PORT = 3000,
    VITE_AUTO_OPEN = true,
    VITE_OPEN_POSTCSS_VW = true,
    VITE_VW_BASE_VALUE = 375,
    VITE_SENTRY_ORG = '',
    VITE_SENTRY_PROJECT = '',
  } = wrapperEnv(env);

  const isSentry = !isBuild && !!VITE_SENTRY_ORG && !!VITE_SENTRY_PROJECT;

  return {
    envDir: path.resolve(__dirname),
    base: command === 'serve' ? '/' : `${env.VITE_PUBLIC_BASE_PATH || ''}/`,
    json: { namedExports: true, stringify: false },
    resolve: {
      alias: {
        '@': path.resolve(__dirname, './src'),
        '#/': path.resolve(__dirname, 'types'),
      },
    },

    plugins: [
      // ── Vue Macros（Vue 2.7 下支持 <script setup> 及响应式解构）──
      VueMacros({
        defineRender: true,
        reactivityTransform: true,
        defineOptions: true,
        defineModels: true,
        betterDefine: true,
        hoistStatic: true,
        // 以下与 Vue 2.7 内置冲突，必须关闭
        defineEmit: false,
        exportProps: false,
        defineProps: false,
        definePropsRefs: false,
        defineSlots: false,
        namedTemplate: false,
        setupBlock: false,
        setupComponent: false,
        setupSFC: false,
        shortEmits: false,
        plugins: {
          vue: vue2(), // vue2 插件必须嵌套在此，不能单独放 plugins 数组
        },
      }),

      // ── 组件自动注册（按需添加 UI 库 resolver）──
      Components({
        dts: path.resolve(__dirname, 'types/components.d.ts'),
        // Vant 2.x 按需导入示例：
        // resolvers: [(name) => {
        //   if (name.startsWith('Van')) {
        //     const part = name.slice(3).replace(/([A-Z])/g, '-$1').toLowerCase().slice(1);
        //     return { from: `vant/lib/${part}`, sideEffects: `vant/lib/${part}/style` };
        //   }
        // }],
      }),

      // ── Vue API 自动导入（免手写 import { ref } from 'vue'）──
      AutoImport({
        imports: [
          {
            vue: [
              'defineComponent', 'ref', 'computed', 'reactive',
              'watch', 'watchEffect', 'provide', 'inject',
              'onMounted', 'onBeforeMount', 'onUnmounted', 'onBeforeUnmount',
              'onUpdated', 'onBeforeUpdate', 'onActivated', 'onDeactivated',
              'nextTick', 'toRefs', 'unref', 'readonly',
              'getCurrentInstance', 'h', 'useAttrs', 'useSlots',
              'defineProps', 'defineEmits', 'defineOptions',
            ],
          },
          {
            from: 'vue',
            imports: ['Component', 'ComputedRef', 'InjectionKey', 'PropType', 'Ref', 'VNode'],
            type: true,
          },
          // 选 pinia 时添加：
          // 'pinia',
        ],
        dts: path.resolve(__dirname, 'types/auto-imports.d.ts'),
      }),

      // ── HTML 模板（MPA 多页面 / 模板变量注入）──
      // 注意：不传 template，默认使用根目录 index.html
      htmlTemplate({
        minify: isBuild,
        inject: {
          data: { title: 'App' },
        },
      }),

      // ── 开发时实时类型 + Stylelint 检查 ──
      checker({
        typescript: true,
        vueTsc: true,
        stylelint: {
          lintCommand: `stylelint ${resolve(process.cwd(), '**/*.{scss,less,vue}')}`,
        },
        overlay: false,
      }),

      // ── SVG 作为 Vue 组件导入（import Icon from './icon.svg?component'）──
      createSvgPlugin(),

      // ── Legacy 兼容（Android 4.4 / iOS 9 / Chrome 49）──
      legacy({
        targets: ['Android >= 4.4', 'Chrome >= 49', 'iOS >= 9'],
        additionalLegacyPolyfills: ['regenerator-runtime/runtime'],
        modernPolyfills: ['es/global-this'],
      }),

      // ── 构建产物体积分析 ──
      visualizer({ open: true }),

      // ── Sentry（由 .env 中 VITE_SENTRY_ORG / VITE_SENTRY_PROJECT 控制）──
      isSentry && sentryVitePlugin({
        org: VITE_SENTRY_ORG,
        project: VITE_SENTRY_PROJECT,
        authToken: process.env.SENTRY_AUTH_TOKEN,
        silent: true,
      }),
    ].filter(Boolean),

    esbuild: {
      pure: VITE_DROP_CONSOLE ? ['console.log', 'debugger'] : [],
    },

    build: {
      copyPublicDir: false,
      modulePreload: { polyfill: true },
      outDir: path.resolve(__dirname, 'dist'),
      emptyOutDir: true,
      sourcemap: isSentry,
      reportCompressedSize: false,
      cssCodeSplit: true,
      chunkSizeWarningLimit: 1024,
      rollupOptions: {
        output: {
          manualChunks: { vue: ['vue'] },
        },
      },
    },

    optimizeDeps: {
      exclude: ['vue-demi'],
    },

    css: {
      preprocessorOptions: {
        // ── SCSS（默认预处理器）──
        scss: {
          silenceDeprecations: ['legacy-js-api'],
          additionalData: `@use "@/styles/variables.scss" as *;`,
          // 说明：variables.scss 存放全局变量，所有 .scss 文件自动注入，无需手动 import
        },
        // ── LESS（如果选用 less 则替换上方 scss 配置）──
        less: {
          additionalData: `@import "@/styles/variables.less";`,
          // 说明：variables.less 中定义全局变量（颜色、字号等），所有 .less 文件自动注入
          // 示例变量文件内容：
          //   @main-color: #0058ff;
          //   @text-color: rgba(0, 0, 0, 0.6);
          //   @border-color: rgba(0, 0, 0, 0.1);
          javascriptEnabled: true,
        },
      },
      postcss: {
        plugins: [
          Autoprefixer({
            overrideBrowserslist: ['Android >= 4.4', 'iOS >= 9', 'Chrome >= 49'],
          }),
          // px → vw，由 VITE_OPEN_POSTCSS_VW 控制，设计稿宽度由 VITE_VW_BASE_VALUE 配置
          VITE_OPEN_POSTCSS_VW && pxToViewport({
            viewportWidth: VITE_VW_BASE_VALUE,
            unitPrecision: 6,
            viewportUnit: 'vw',
            propList: ['*'],
          }),
        ].filter(Boolean),
      },
    },

    server: {
      open: VITE_AUTO_OPEN,
      port: VITE_PORT,
      host: true,
      proxy: {
        '/api': {
          target: 'https://your-api-server.com',
          changeOrigin: true,
        },
      },
    },
  };
});
```

---

## 项目脚手架

当用户要创建新的 Vue 2.7 项目时，执行以下步骤：

### Step 1：确认项目信息

**首先询问是否使用快速模式：**

> 是否使用快速模式？（快速模式将默认启用 vue-router + pinia + scss，无需逐项确认）

- **快速模式（推荐）**：直接生成，默认包含 vue-router 3.6.5、pinia 2.1.7、scss 1.97.3，不含 vant
- **自定义模式**：逐项询问以下选项：
  - 是否需要 Vue Router（默认是）
  - 是否需要 Pinia（默认是）
  - CSS 预处理器：SCSS / LESS（默认 SCSS）
  - 是否需要 Vant（默认否）
  - 设计稿宽度（有 px→vw 需求时，默认 375）

**目录命名规则：**

- **快速模式**：不询问目录名，直接使用 `examples/vue27-project/`（或用户已明确指定的名称）
- **自定义模式**：询问用户项目名；未指定则默认 `examples/vite-demo/`
- 如果目标目录已存在，则依次尝试递增后缀 `-1`、`-2`……直到找到未占用的名称
- 创建前用 Glob 或 Bash 检查已有目录，确定最终目录名后告知用户

### Step 2：生成项目结构

```
<project-name>/
├── index.html                   # 根目录 HTML，vite-plugin-html-template-mpa 默认读取
├── src/
│   ├── assets/
│   ├── components/
│   ├── styles/
│   │   ├── variables.scss   # 全局变量（选 SCSS 时）
│   │   ├── variables.less   # 全局变量（选 LESS 时）
│   │   └── index.scss/less  # 全局样式入口
│   ├── views/
│   │   └── Home.vue
│   ├── router/              # 选 vue-router 时生成
│   │   └── index.ts
│   ├── stores/              # 选 pinia 时生成
│   │   └── index.ts
│   ├── App.vue
│   └── main.ts
├── types/                   # auto-imports.d.ts / components.d.ts 自动生成至此
├── .env
├── .env.development
├── .env.test
├── .npmrc
├── tsconfig.json
├── vite.config.ts
└── package.json
```

### Step 3：生成关键文件内容

**package.json** — 根据选项动态生成，volta 固定版本必须包含：

```json
{
  "name": "<project-name>",
  "version": "1.0.0",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "vue": "2.7.16",
    "vue-router": "3.6.5",     // 选 vue-router 时添加
    "pinia": "2.1.7",           // 选 pinia 时添加
    "vant": "2.13.2"            // 选 vant 时添加
  },
  "devDependencies": {
    "vite": "5.2.6",
    "typescript": "5.2.2",
    "unplugin-vue-macros": "2.9.5",
    "@vitejs/plugin-vue2": "2.3.1",
    "@vitejs/plugin-vue2-jsx": "1.1.1",
    "unplugin-auto-import": "0.17.5",
    "unplugin-vue-components": "0.26.0",
    "@vitejs/plugin-legacy": "5.3.2",
    "vite-plugin-checker": "0.6.2",
    "vite-plugin-html-template-mpa": "1.0.28",
    "rollup-plugin-visualizer": "5.14.0",
    "autoprefixer": "10.4.19",
    "postcss": "8.4.23",
    "postcss-px-to-viewport-8-plugin": "1.2.5",
    "postcss-less": "6.0.0",
    "postcss-scss": "4.0.6",
    "stylelint": "10.1.0",
    "@types/node": "20.11.30",
    "vue-demi": "0.14.7",
    "vue-tsc": "1.8.22",
    "sass": "1.97.3",           // 选 SCSS 时添加
    "less": "4.2.0"             // 选 LESS 时添加
  },
  "volta": {
    "node": "16.18.1",
    "pnpm": "8.3.1"
  }
}
```

**tsconfig.json**：
```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "Node",
    "jsx": "preserve",
    "strict": true,
    "esModuleInterop": true,
    "verbatimModuleSyntax": true,
    "forceConsistentCasingInFileNames": true,
    "useUnknownInCatchVariables": false,
    "inlineSources": false,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "allowJs": true,
    "removeComments": true,
    "sourceMap": false,
    "types": ["node", "unplugin-vue-macros/macros-global"],
    "paths": {
      "@/*": ["./src/*"],
      "#/*": ["./types/*"]
    }
  },
  "include": ["src/**/*", "types/**/*.d.ts", "env.ts", "vite.config.ts"],
  "vueCompilerOptions": { "target": 2.7 }
}
```

**env.ts**：
```typescript
// @ts-nocheck
// @ts-ignore

/* eslint-disable */
// @ts-ignore
/// <reference types="vite/client" />

declare module '*.vue' {
  import { DefineComponent } from 'vue';
  const Component: DefineComponent<{}, {}, any>;
  export default Component;
}

declare module 'virtual:*' {
  const result: any;
  export default result;
}
```

**index.html**（根目录）：
```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title><%= title %></title>
</head>
<body>
  <div id="app"></div>
  <script type="module" src="/src/main.ts"></script>
</body>
</html>
```

**src/main.ts**（根据选项动态生成）：
```typescript
import Vue from 'vue';
import App from './App.vue';
import router from './router';   // 选 vue-router 时
import { createPinia, PiniaVuePlugin } from 'pinia'; // 选 pinia 时

// 选 pinia 时
Vue.use(PiniaVuePlugin);
const pinia = createPinia();

new Vue({
  router,   // 选 vue-router 时
  pinia,    // 选 pinia 时
  render: h => h(App),
}).$mount('#app');
```

**src/stores/index.ts**（选 pinia 时生成）：
```typescript
import { defineStore } from 'pinia';
import { ref } from 'vue';

export const useAppStore = defineStore('app', () => {
  const count = ref(0);

  function increment() {
    count.value++;
  }

  return { count, increment };
});
```

**src/App.vue**（lang 根据预处理器选择）：
```vue
<script setup lang="ts">
</script>

<template>
  <router-view />
</template>

<style scoped lang="scss">  <!-- 选 LESS 时改为 lang="less" -->
</style>
```

**src/styles/variables.scss**（选 SCSS 时生成）：
```scss
// 主题色
$main-color: #0058ff;
$text-color: rgba(0, 0, 0, 0.6);
$border-color: rgba(0, 0, 0, 0.1);
$white: #fff;
$black: #000;
```

**src/styles/variables.less**（选 LESS 时生成）：
```less
// 主题色
@main-color: #0058ff;
@text-color: rgba(0, 0, 0, 0.6);
@border-color: rgba(0, 0, 0, 0.1);
@white: #fff;
@black: #000;
```

**src/router/index.ts**：
```typescript
import Vue from 'vue';
import VueRouter from 'vue-router';

Vue.use(VueRouter);

export default new VueRouter({
  mode: 'history',
  routes: [
    {
      path: '/',
      component: () => import('@/views/Home.vue'),
    },
  ],
});
```

**src/views/Home.vue**：
```vue
<script setup lang="ts">
import { useAppStore } from '@/stores';

const store = useAppStore();
const msg = ref('Hello Vue 2.7 + Vite 5');
</script>

<template>
  <div class="home">
    <p class="home__msg">{{ msg }}</p>
    <p class="home__count">count: {{ store.count }}</p>
    <button class="home__btn" @click="store.increment">+1</button>
  </div>
</template>

<style scoped lang="scss">  <!-- 选 LESS 时改为 lang="less" -->
.home {
  padding: 20px;

  &__msg {
    font-size: 18px;
    color: $main-color;
  }

  &__count {
    margin-top: 12px;
    color: $text-color;
  }

  &__btn {
    margin-top: 12px;
    padding: 8px 20px;
    background-color: $main-color;
    color: #fff;
    border: none;
    border-radius: 4px;
    cursor: pointer;
  }
}
</style>
```

**.env**：
```
VITE_PUBLIC_BASE_PATH=./
VITE_DROP_CONSOLE=true
VITE_VW_BASE_VALUE=375
```

**.env.development**：
```
VITE_PUBLIC_BASE_PATH=
```

**.env.test**：
```
VITE_PUBLIC_BASE_PATH=./
```

**vite.config.ts** — 使用上方「标准 vite.config.ts」模板

**.npmrc**：
```
#registry=https://registry.npmjs.org/
registry=https://registry.npmmirror.com/
```

**.editorconfig**：
```
root = true

[*]
charset = utf-8
end_of_line = lf
indent_style = space
indent_size = 2
insert_final_newline = true
trim_trailing_whitespace = true
max_line_length = 80

[*.md]
trim_trailing_whitespace = false

[Makefile]
indent_style = space
```

**.prettierrc.cjs**：
```
module.exports = {
  printWidth: 80,
  tabWidth: 2,
  useTabs: false,
  semi: true,
  singleQuote: true,
  quoteProps: 'preserve',
  jsxSingleQuote: false,
  trailingComma: 'all',
  bracketSpacing: true,
  arrowParens: 'avoid',
  requirePragma: false,
  insertPragma: false,
  proseWrap: 'preserve',
  htmlWhitespaceSensitivity: 'ignore',
  endOfLine: 'lf',
};
```

**.prettierignore**：
```
dist
node_modules
public
.local
pnpm-lock.yaml
env.ts
```

**.stylelintignore**：
```
dist
public
node_modules
```

**.stylelintrc.js**：
```
module.exports = {
  root: true,
  extends: ['stylelint-config-rational-order'],
  plugins: ['stylelint-performance-animation'],
  rules: {
    'no-descending-specificity': null,
    'property-no-vendor-prefix': null,
    'plugin/no-low-performance-animation': null,
  },
};
```

**.eslintignore**：
```
*.sh
node_modules
*.md
*.woff
*.ttf
.vscode
.idea
dist
public
docs
.husky
.local
```

**.eslintrc.cjs**：
```
module.exports = {
  env: {
    browser: true,
    node: true,
    es6: true,
  },
  parser: 'vue-eslint-parser',
  plugins: ['vue', '@typescript-eslint'],
  parserOptions: {
    parser: '@typescript-eslint/parser',
    ecmaVersion: 2020,
    sourceType: 'module',
    jsxPragma: 'React',
    ecmaFeatures: {
      jsx: true,
    },
  },
  extends: [
    'plugin:vue/vue3-recommended',
    'plugin:@typescript-eslint/recommended',
    'plugin:prettier/recommended',
  ],
};
```

### Step 4：安装依赖并启动

```bash
cd <project-name>
pnpm install
pnpm dev
```

---

## 参考文档

- `references/plugins.md` — 核心插件详解（VueMacros 开关原理、AutoImport dts 配置等）
- `references/advanced-plugins.md` — 进阶插件（nightMode、postcssRTL、fileImportReplace、mergeConfig 工厂模式等）
- `references/migration.md` — Vue 2.6 → 2.7 迁移步骤与常见陷阱
- `references/build-optimization.md` — 分包策略、sourcemap、console 清理
