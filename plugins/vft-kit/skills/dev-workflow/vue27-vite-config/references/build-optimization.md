# 构建优化指南

## 分包策略（manualChunks）

将 Vue 单独提取，避免每个入口都打包一份：

```typescript
rollupOptions: {
  output: {
    manualChunks: {
      vue: ['vue'],
      // 按需添加其他大库
      // vant: ['vant'],
    },
  },
},
```

## 性能开关

```typescript
build: {
  reportCompressedSize: false,   // 关闭 gzip 大小报告，加快构建速度
  cssCodeSplit: true,            // CSS 按需加载，减少首屏阻塞
  chunkSizeWarningLimit: 1024,   // 提高警告阈值（默认 500kb）
}
```

## 生产环境 console 清理

通过环境变量控制，避免生产代码泄露调试信息：

```typescript
// .env.production
VITE_DROP_CONSOLE=true

// vite.config.ts
const VITE_DROP_CONSOLE = env.VITE_DROP_CONSOLE === 'true'

esbuild: {
  pure: VITE_DROP_CONSOLE ? ['console.log', 'debugger'] : [],
}
```

## 产物分析

`rollup-plugin-visualizer` 构建后会自动打开分析页面。
重点关注：
- 单个 chunk 超过 500kb 的模块
- 同一库被多个 chunk 重复打包的情况
- 图片/字体等静态资源是否被意外内联

## copyPublicDir 关闭

```typescript
build: {
  copyPublicDir: false,
}
```

多入口项目中，`public/` 目录的文件不需要复制到每个入口的 dist，避免重复文件。

## optimizeDeps 说明

```typescript
optimizeDeps: {
  exclude: ['vue-demi'],
}
```

`vue-demi` 是为跨版本 Vue 库设计的适配层，在 Vue 2.7 项目中由 Vite 预构建可能产生版本冲突，排除后让其走正常模块解析。

## sourcemap 策略

sourcemap 会显著增大构建产物，建议按需开启：

```typescript
build: {
  sourcemap: isSentry,  // 只在需要 Sentry 错误追踪的入口开启
}
```

如需调试特定入口：
```bash
ent=inventory pnpm build --mode=test
```
