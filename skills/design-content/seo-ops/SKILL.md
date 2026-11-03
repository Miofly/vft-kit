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

## 工具站扩词与竞品对照

- 先看真实输入、输出、限制、处理位置与收费/登录规则，再扩正式名、口语别名、英文词、格式词和使用场景。免费不等于无限额、免登录、离线或不上传，不能按分类批量承诺。
- 对照公开页面的标题、主标题、用途、步骤、FAQ 与相关工具链接；不复制竞品正文、不冒用评分。可参考 iLoveIMG 的格式词分组、PDF24 的免费与限制说明、123apps 的剪歌曲/铃声等场景词，以及 BeJSON 的相关能力导航。竞品写出的格式与功能不能直接当作本站支持。
- 核心词放在自然、独立的标题；长尾词写进可阅读用途与问答，邻近需求通过真实相关工具内链承接。Google 不用 `meta keywords` 排名，反复堆同义词反而触及垃圾内容政策；不为每个别名制造重复 URL。
- 摘要优先本页真实导语、用途和限制；不为凑 150–160 字套“全格式/批量/本地/不上传”句池。结构化数据必须与可见正文一致；不要把 FAQ/HowTo 标记或关键词数量当成富结果、收录或排名保证，展示资格以当前官方文档为准。
- 全站任务先列真实公开路由并冻结覆盖分母，不能只优化热门页后称全站完成；区分工具页、资讯页、管理工作区、个人收藏、重定向别名与辅助组件。私人页保留准确介绍，但不混入公开 sitemap 或标成匿名免费软件。
- 验收原始 HTML 与水合后页面两端：标题、canonical、正文、可访问内链和指南展开均正确。SSR 直出不代表已有说明；全屏与 client-only 页要检查指南是否被布局条件漏掉，并对照生产与单路由预览的包装差异。全量模板渲染测试与浏览器抽验分别报告，不把前者当作全站浏览器实测。无 Search Console 数据时，不能声称已提升曝光、点击或排名。

参考：[Google SEO 入门指南](https://developers.google.com/search/docs/fundamentals/seo-starter-guide?hl=zh-cn)、[标题最佳实践](https://developers.google.com/search/docs/appearance/title-link)、[关键词堆砌政策](https://developers.google.com/search/docs/essentials/spam-policies#keyword-stuffing)。

## 与 fe-quality-ops 的分工

- `fe-quality-ops`：代码改动后的静态收尾（lint/tsc）+ 页面渲染/控制台/Lighthouse/SEO/hydration 验证
- `seo-ops`：站点级 SEO 审计、内容/E-E-A-T、Schema、GEO/AEO、drift 监控、报告产出

两者互补：开发阶段用 fe-quality-ops 验证单页，上线前/定期用 seo-ops 全站审计。
