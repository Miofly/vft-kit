---
name: web-scrape
description: 智能网页抓取与场景路由工具，按需求选择 Scrapling、Crawl4AI 或 ego-lite（ego-browser），没有 ego-lite 时用 Playwright 兜底。用户要求抓取网页、提取 Markdown、深度爬取、处理 Cloudflare、自适应解析、下载渲染资源、截图或分析 XHR/API 请求时使用。
---

# web-scrape

智能网页抓取工具，根据场景自动选择最佳抓取策略。先静默探测 `command -v ego-browser >/dev/null 2>&1`：有 ego-lite 时所有需要浏览器的抓取（登录态、截图、网络请求）都走 ego-lite，每次抓取开一个独立 task space、结束即关闭，自动选择和回退都不会选 Playwright；没有 ego-lite 的环境才用 Playwright 兜底，不另起 Chrome：

运行环境要求 Node.js 18+ 和 Python 3.8+；Scrapling、Crawl4AI、Playwright 均为可选运行时依赖。

- **Scrapling** - 自适应解析 + Cloudflare Turnstile 绕过
- **Crawl4AI** - LLM-ready Markdown + 批量深度爬取
- **ego-lite（ego-browser）** - 浏览器后端首选：已登录单页、人工接管、截图、DOM 提取、网络请求清单
- **Playwright** - 仅在没有 ego-lite 的环境兜底：完整渲染资源下载 + 网络请求监控

## 何时用

- 需要**智能选择抓取工具**（自动判断场景）
- 网站频繁改版，需要**自适应元素定位**
- 需要**绕过 Cloudflare Turnstile** 反爬
- 抓取内容要喂给 **LLM**（RAG / 总结 / 问答）
- 批量爬取文档站、博客（**深度爬取 + 崩溃恢复**）
- 需要完整的**渲染后资源 + 网络请求日志**

不适用：简单的静态页面用 `curl` 就够；需要登录态复杂交互的用专门的自动化脚本。

## 浏览器到 API 的强制演进

本 skill 只要以浏览器执行远端业务动作，就必须先读并遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)。登录、验证码、2FA、纯视觉验收可保留浏览器；认证后的可接口化动作仍须抓取、复现、独立回验，并在同一任务自更新本 skill 与脚本。

## 核心流程

1. 读 [policies.md](references/policies.md)；简单静态页直接 `curl`，不进本 skill。
2. 静默探测 `command -v ego-browser >/dev/null 2>&1`，决定浏览器后端。
3. 跑调度脚本：`node "$SKILL_DIR/scripts/scrape.mjs" <url> [--intent ...] [--tool ...] [--format ...] [--out <dir>]`。
4. 脚本按意图、URL、Cloudflare 检测选工具；失败按回退链换下一个工具。
5. 读输出目录的 `meta.json` 确认工具与判断依据，再交付 `content.md`/`content.html`/`network.json`/截图。
6. ego-lite 抓取结束即关闭该 task space。

## 硬规则

- 有 ego-lite 时所有浏览器抓取只走 ego-lite，自动选择和回退都不选 Playwright。
- 每次 ego-lite 抓取开独立 task space，结束即关闭；不另起 Chrome。
- 没有 ego-lite 才用 Playwright 兜底；静态资源下载只有 Playwright 支持。
- `--adaptive` 必须先正常抓取一次训练，再在改版后启用。
- 代理只经 `SCRAPE_PROXY_LIST` 环境变量或配置文件，按顺序回退。
- 自建 Crawl4AI Docker Server 必须 ≥ 0.9.0；本 skill 直接用 Python 库。
- 不记录 Cookie、Token 或密码；凭据只从环境变量或私有配置读取。
- 使用 Scrapling、Crawl4AI 时遵守上游 Apache-2.0 署名要求。

## 路由表

| 任务 | references | 执行脚本 |
|---|---|---|
| API 优先、抓包演进、安全边界 | [policies.md](references/policies.md) | — |
| 安装 Node/Python 依赖、venv | [setup.md](references/setup.md) | `install-deps.sh`、`verify.sh` |
| 场景识别、工具对比、选择算法、Fallback | [tool-routing.md](references/tool-routing.md)，详解 [docs/tool-selection.md](docs/tool-selection.md) | `scripts/scrape.mjs` |
| 选项、六个示例、输出目录与 `meta.json` | [usage.md](references/usage.md) | `scripts/scrape.mjs` |
| 在其他 skill 或 MCP 中调用 | [integration.md](references/integration.md) | `scripts/scrape.mjs` |
| 自适应报错、Crawl4AI 超时、找不到 Playwright | [troubleshooting.md](references/troubleshooting.md) | — |
| Crawl4AI 漏洞史、代理链、许可证、官方文档 | [security-license.md](references/security-license.md) | — |
| 架构设计、各 worker 说明 | [docs/architecture.md](docs/architecture.md) | `scripts/scrapling-worker.py`、`scripts/crawl4ai-worker.py`、`scripts/playwright-worker.mjs` |
