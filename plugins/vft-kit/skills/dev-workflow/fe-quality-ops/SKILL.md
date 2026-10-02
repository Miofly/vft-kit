---
name: fe-quality-ops
description: "前端质量检查与修复：处理 lint、格式、TypeScript 类型错误，验证页面渲染、控制台、Canvas/WebGL、交互、截图、Lighthouse、缓存、SEO 与 hydration；复用项目脚本和包管理器，浏览器优先 ego-lite。"
---

# 前端质量

按任务读取对应路线，不把静态修复与页面审计强制串成一套。

| 任务 | 路线 | 执行入口 |
|---|---|---|
| lint、格式、类型报错，或代码改动后的静态收尾 | [静态修复与类型检查](references/lint.md) | `scripts/lint-fix.sh` |
| 白屏、控制台、组件挂载、Canvas/WebGL、交互、截图、性能、缓存、SEO、hydration | [页面验证与审计](references/browser.md) | `scripts/check-deps.sh`，再按文档选检查脚本 |

- 纯静态问题只走静态路线；页面请求只走页面路线。改动同时涉及两者时先修静态问题，再验证相关页面。
- 仅查看、审查或禁止修改时，不运行会写文件的 lint 修复脚本；使用项目已有的只读检查命令。
- lint 修复会修改目标项目，TypeScript 校验不修改文件。保留无关改动，缺失工具按原脚本规则跳过。
- 页面路线保留原浏览器、Lighthouse、API 和人工登录边界；脚本及其相对依赖全部位于 `scripts/`。
- 不默认运行生产 build，不默认发布、部署，也不拿静态通过代替页面交互证据。
- 产物遵守工作区规范；已有 `FE_TEST_OUTPUT_DIR` 和默认缓存路径继续兼容，禁止把输出写入项目根。
