---
name: seo-ops
description: "SEO 审计与优化：在 Claude Code 中用 claude-seo 插件做技术 SEO、E-E-A-T 内容、Schema、GEO/AEO、Agent 就绪度、sitemap、本地/电商/国际 SEO、Google API、drift 监控与 PDF/Excel 报告。"
---

# SEO 审计与优化（seo-ops）

基于 [AgriciDaniel/claude-seo](https://github.com/AgriciDaniel/claude-seo)（MIT）归纳。claude-seo 是 Claude Code 插件，26 子技能 + 19 子 agent + 30 命令。

## 安装

```
/plugin marketplace add AgriciDaniel/claude-seo
/plugin install claude-seo@agricidaniel-claude-seo
/seo setup          # 自装 Python venv + headless Chromium
/seo doctor         # 就绪检查
```

手动：`git clone --depth 1 https://github.com/AgriciDaniel/claude-seo.git && bash claude-seo/install.sh`（Win 用 install.ps1）。要求 Claude Code ≥1.0.33、Python 3.11–3.14。

## 命令分组

**审计与规划**：`/seo setup` `/seo doctor` `/seo audit <url>` `/seo page <url>` `/seo plan <type>`（saas/local/ecommerce/publisher/agency）

**技术 SEO**：`/seo technical <url>`（9 类） `/seo sitemap <url|generate>` `/seo images <url>` `/seo hreflang <url>` `/seo programmatic <url>` `/seo google [cmd]`（GSC/PageSpeed/CrUX/Indexing/GA4/PDF） `/seo drift baseline|compare|history <url>`

**内容与 E-E-A-T**：`/seo content <url>` `/seo content-brief <topic>` `/seo cluster <keyword>` `/seo sxo <url>` `/seo flow [stage]` `/seo competitor-pages <url>`

**Schema 与 AI 搜索**：`/seo schema <url>` `/seo geo <url>` `/seo agentic <url>`（Lighthouse Agentic Browsing X/N、AI agent 访问、llms.txt、Markdown、WebMCP）

**本地/链接/电商**：`/seo local <url>` `/seo maps [cmd]` `/seo backlinks <url>` `/seo ecommerce <url>`

**扩展**：`/seo image-gen [use-case]` `/seo seranking [cmd]` `/seo profound [cmd]` `/seo bing [cmd] <url>` `/seo unlighthouse <url>`

## Agent 角色（模型可改 `agents/`）

| agent | 角色 | 模型 |
|---|---|---|
| seo-technical | 技术 SEO 主导 | Sonnet |
| seo-content / seo-geo / seo-cluster / seo-sxo / seo-drift | 内容/E-E-A-T/AI 搜索/聚类/搜索体验/漂移 | Opus |
| seo-schema / seo-sitemap / seo-performance / seo-visual / seo-agentic / seo-local / seo-maps / seo-google / seo-backlinks / seo-ecommerce / seo-flow / seo-image-gen | 对应专项 | Sonnet |

全量审计 `/seo audit` 有 5 个 Opus agent，比单页检查更吃 Claude plan 额度。

## 审计流程建议

1. 先 `/seo audit <url>` 拿优先级行动清单
2. 按问题类型下钻：技术→`/seo technical`，内容→`/seo content`，结构化数据→`/seo schema`，AI 搜索→`/seo geo`+`/seo agentic`
3. Google API（免费）：`/seo google setup` 接 PSI/CrUX/GSC/GA4，拿到真实 CWV 与索引数据
4. 持续：`/seo drift baseline` 建基线，后续 compare

## 适用与限制

- 支持 JS 渲染站点（SPA/Next/React/Vue）：自动 headless browser 审计 visitor 视角
- 无 API key 时 CWV 为 lab 估算、索引为推断；页面需滚动/点击才加载的内容可能噪声
- 数据送 Anthropic（与 Claude Code 一致），报告落本地；第三方 SEO 服务仅在装扩展时接入
- Pro 版（AI Marketing Hub 成员）有早期内测特性，安装源不同

## 与 fe-quality-ops 的分工

- `fe-quality-ops`：代码改动后的静态收尾（lint/tsc）+ 页面渲染/控制台/Lighthouse/SEO/hydration 验证
- `seo-ops`：站点级 SEO 审计、内容/E-E-A-T、Schema、GEO/AEO、drift 监控、报告产出

两者互补：开发阶段用 fe-quality-ops 验证单页，上线前/定期用 seo-ops 全站审计。
