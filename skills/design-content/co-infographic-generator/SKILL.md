---
name: co-infographic-generator
description: "把结构化文字、KPI、成果或对比内容做成中文信息图 PNG（HTML/CSS 排版）；架构图用 diagram-design，统计图用绘图工具。"
---

# 信息图生成器（HTML + puppeteer）

> **浏览器/API 边界**：遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)。本地渲染、视觉、兼容性或浏览器本身的验证可保留浏览器；认证后的远端业务读写必须探索实际接口、写后独立回读，并在确认后更新本 skill，后续默认 API。

把结构化内容（要点、KPI、流程、对比）用 HTML/CSS 排版，再由 puppeteer 截成风格统一、中文准确的 PNG 信息图。

## 何时用

- KPI 看板、并列卡片、A/B 对比、简单线性步骤、成就/里程碑卡片。
- 需要渐变、玻璃拟态、光晕、自定义配色或品牌排版。
- 架构/流程/时序/状态/ER/泳道/四象限/时间线/甘特/循环/金字塔/漏斗/韦恩/组织架构，或 draw.io/Mermaid 重绘：已装 diagram-design 时改用它。
- 柱/折/饼/散点等纯统计、需交互或大数据量：改用 multi-chart-draw。

## 核心流程

1. 按 [diagram-design-integration.md](references/diagram-design-integration.md) 路由；先跑 `scripts/check-diagram-design.sh`（退出码 0=已安装）。
2. 风格与版式有明显多解时，先用一两句话确认配色和版式。
3. 从 `assets/templates/` 选起手模板，或用 design-system 组件自由组合。
4. 写 HTML：整图包在 `id="shot"` 内，按配方改 `--accent`/`--accent2` 与光晕。
5. `node <skill>/scripts/render.mjs <input.html> <output.png> [--scale 3] [--no-install]` 渲染。
6. 按溢出告警调宽重渲，看图检查缺字、错字和风格，交付 PNG 并保留 `.html`。

## 硬规则

- 技术图表与业务分析图在 diagram-design 已安装时必须优先用它；未安装先提示安装，用户拒绝或紧急才降级。
- 整张图必须包在 `id="shot"` 容器里；图宽只由 `#shot { width }` 决定。
- `body` 字体保留 `"Microsoft YaHei","PingFang SC"`，防中文缺字。
- 换主题色时同步改 `#shot` 背景光晕颜色。
- 图标只用 `assets/icons.md` 的线性 SVG，不用 emoji。
- 同一文档多张图沿用同一配方与组件语言；版式可以不同。
- 浏览器复用本机 chromium 或系统 Chrome/Edge，不默认下载浏览器。

## 路由表

| 任务 | references | 执行脚本 |
|---|---|---|
| 选 diagram-design / 本 skill / multi-chart-draw，安装提示话术，降级 | [diagram-design-integration.md](references/diagram-design-integration.md) | `scripts/check-diagram-design.sh` |
| 风格对齐、选模板、写 HTML、渲染、自检、一致性、可选微调 | [workflow.md](references/workflow.md) | `scripts/render.mjs` |
| CSS token、配色配方、组件、暗色变体、排版坑 | [design-system.md](references/design-system.md) | — |
| 起手模板与线性图标 | `assets/templates/*.html`、`assets/icons.md` | — |
