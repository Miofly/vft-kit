---
name: smart-web-scrape
description: 智能网页抓取与场景路由工具，按需求选择 Scrapling、Crawl4AI 或 Playwright。用户要求抓取网页、提取 Markdown、深度爬取、处理 Cloudflare、自适应解析、下载渲染资源、截图或分析 XHR/API 请求时使用。
compatibility: Requires Node.js 18+ and Python 3.8+; Scrapling, Crawl4AI, and Playwright are optional runtime dependencies.
---

# smart-web-scrape

智能网页抓取工具，根据场景自动选择最佳抓取策略：

- **Scrapling** - 自适应解析 + Cloudflare Turnstile 绕过
- **Crawl4AI** - LLM-ready Markdown + 批量深度爬取
- **Playwright** - 完整渲染资源 + 网络请求监控

## 何时用

- 需要**智能选择抓取工具**（自动判断场景）
- 网站频繁改版，需要**自适应元素定位**
- 需要**绕过 Cloudflare Turnstile** 反爬
- 抓取内容要喂给 **LLM**（RAG / 总结 / 问答）
- 批量爬取文档站、博客（**深度爬取 + 崩溃恢复**）
- 需要完整的**渲染后资源 + 网络请求日志**

不适用：简单的静态页面用 `curl` 就够；需要登录态复杂交互的用专门的自动化脚本。

## 前置依赖

### 必需
- **Node.js** ≥ 18（运行调度脚本）
- **Python** ≥ 3.8（Scrapling / Crawl4AI）
- **Playwright** 全局安装（fallback 到 vft-ai:web-scrape）

### Python 依赖（自动检测并提示安装）
```bash
pip install scrapling crawl4ai playwright
playwright install chromium  # Crawl4AI 需要
```

脚本会自动检测依赖，缺失时给出安装命令。

## 工作原理

### 场景识别引擎

调度脚本 `scripts/scrape.mjs` 根据用户意图和 URL 特征自动选择工具：

| 场景 | 工具选择 | 原因 |
|------|---------|------|
| 用户明确要"Markdown" | **Crawl4AI** | LLM-ready 输出 + fit_markdown 去噪 |
| 用户说"批量"/"深度"/"递归" | **Crawl4AI** | BFS/DFS 深度爬取 + 崩溃恢复 |
| URL 匹配 `/docs/`、`/blog/`、`/wiki/` | **Crawl4AI** | 文档站常需要批量爬 + 干净 Markdown |
| 检测到 Cloudflare 防护页 | **Scrapling** | 内置 Turnstile 绕过 |
| 用户说"自适应"/"网站经常改" | **Scrapling** | 自适应解析器抗改版 |
| 用户要"资源"/"截图"/"网络请求" | **Playwright** | 完整渲染 + 资源下载 + 网络监控 |
| 用户要"接口"/"XHR"/"API 调用" | **Playwright** | network.json 记录所有请求 |
| 无明确意图 | **Scrapling** → **Playwright** | 先试快速抓取，失败 fallback |

### 三种工具对比

| 特性 | Scrapling | Crawl4AI | Playwright |
|------|-----------|----------|------------|
| **速度** | ⚡⚡⚡ 快 | ⚡⚡ 中等 | ⚡ 慢（需渲染） |
| **反检测** | Cloudflare 专杀 | Stealth + 代理链 | 基础（可加 stealth） |
| **自适应** | ✅ 网站改版自动定位 | ❌ | ❌ |
| **深度爬取** | ✅ Spider 框架 | ✅ BFS/DFS + 崩溃恢复 | ❌ 单页 |
| **输出格式** | HTML / 结构化 | **Markdown for LLM** | HTML + 资源 |
| **资源下载** | ❌ | ❌ | ✅ CSS/JS/图片/字体 |
| **网络监控** | ❌ | ❌ | ✅ network.json |
| **截图/PDF** | ❌ | ✅ | ✅ |

## 用法

### 基础调用

```bash
# 在 vft-kit 项目根目录
SKILL_DIR="plugins/vft-kit/skills/smart-web-scrape"
node "$SKILL_DIR/scripts/scrape.mjs" <url> [options]
```

或通过 Claude Code skill：

```text
用 smart-web-scrape 抓取 https://example.com 并转成 Markdown
```

### 选项

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `--tool <name>` | 强制使用工具：`scrapling`/`crawl4ai`/`playwright` | 自动选择 |
| `--intent <text>` | 用户意图描述（用于场景识别） | - |
| `--out <dir>` | 输出目录 | `other/scrape` |
| `--format <type>` | 输出格式：`html`/`markdown`/`json` | `html` |
| `--deep` | 启用深度爬取（仅 Crawl4AI / Scrapling） | `false` |
| `--max-pages <n>` | 深度爬取最大页数 | `10` |
| `--strategy <s>` | 深度爬取策略：`bfs`/`dfs`/`best-first` | `bfs` |
| `--adaptive` | 启用自适应解析（仅 Scrapling） | `false` |
| `--stealth` | 启用隐蔽模式（Scrapling / Crawl4AI） | `true` |
| `--headless` | 无头模式 | `true` |
| `--wait <ms>` | 页面加载后等待时间 | `1500` |
| `--timeout <ms>` | 单页超时 | `60000` |
| `--no-resources` | 不下载静态资源（仅 Playwright） | `false` |
| `--no-screenshot` | 不生成截图 | `false` |

## 示例

### 例 1 - 自动选择工具

```bash
# 根据 URL 和意图自动选择
node "$SKILL_DIR/scripts/scrape.mjs" https://docs.python.org/3/library/asyncio.html \
  --intent "抓取文档转成 Markdown 喂给 LLM"
# → 自动选择 Crawl4AI（文档站 + Markdown 意图）
```

### 例 2 - Cloudflare 站点

```bash
# 检测到 Cloudflare 自动用 Scrapling
node "$SKILL_DIR/scripts/scrape.mjs" https://protected-site.com \
  --stealth
# → Scrapling Turnstile 绕过
```

### 例 3 - 批量深度爬取

```bash
# 爬整个文档站
node "$SKILL_DIR/scripts/scrape.mjs" https://scrapling.readthedocs.io \
  --deep --max-pages 50 --strategy bfs --format markdown
# → Crawl4AI BFS 爬取 + Markdown 输出
```

### 例 4 - 自适应抓取（网站频繁改版）

```bash
# 第一次抓取
node "$SKILL_DIR/scripts/scrape.mjs" https://example.com/products \
  --tool scrapling --adaptive
# → Scrapling 学习页面结构

# 网站改版后再抓，自动重新定位元素
node "$SKILL_DIR/scripts/scrape.mjs" https://example.com/products \
  --tool scrapling --adaptive
# → 元素位置改变但仍能找到
```

### 例 5 - 完整渲染 + 网络请求

```bash
# 需要完整资源和接口调用日志
node "$SKILL_DIR/scripts/scrape.mjs" https://app.example.com \
  --tool playwright --wait 3000
# → 输出：HTML + CSS/JS/图片 + network.json（所有 XHR/fetch）
```

### 例 6 - 只要干净 Markdown

```bash
# 给 LLM 准备训练数据
node "$SKILL_DIR/scripts/scrape.mjs" https://blog.example.com/post/123 \
  --format markdown
# → Crawl4AI fit_markdown 去噪 + BM25 过滤
```

## 输出结构

```
<输出根>/<域名>-<时间戳>/
├── meta.json              # 元信息（工具、耗时、场景判断依据）
├── content.html           # HTML（Scrapling / Playwright）
├── content.md             # Markdown（Crawl4AI）
├── resources/             # 静态资源（仅 Playwright）
│   ├── css/
│   ├── js/
│   ├── images/
│   └── fonts/
├── network.json           # 网络请求日志（仅 Playwright）
├── screenshot.png         # 整页截图
├── page.pdf               # PDF 快照（Crawl4AI / Playwright chromium）
└── deep-crawl/            # 深度爬取结果（仅 Crawl4AI / Scrapling）
    ├── page-001.md
    ├── page-002.md
    └── index.json         # 爬取树结构
```

### meta.json 示例

```json
{
  "url": "https://docs.python.org/3/library/asyncio.html",
  "tool": "crawl4ai",
  "reason": "文档站 URL 模式 + Markdown 输出意图",
  "timestamp": "2026-08-07T21:30:00Z",
  "duration_ms": 3245,
  "options": {
    "format": "markdown",
    "deep": false,
    "stealth": true
  }
}
```

## 依赖安装

脚本首次运行会检测依赖，缺失时输出：

```
[smart-web-scrape] 缺少 Python 依赖，请运行：

  pip install scrapling crawl4ai playwright
  playwright install chromium

或使用 venv：

  python3 -m venv ~/.scrape-venv
  source ~/.scrape-venv/bin/activate
  pip install scrapling crawl4ai playwright
  playwright install chromium
```

## 集成到项目

### 在 Claude Code 中调用

```typescript
// 在其他 skill 中调用
const { execSync } = require('child_process');
const skillDir = '/path/to/vft-kit/plugins/vft-kit/skills/smart-web-scrape';

const result = execSync(
  `node ${skillDir}/scripts/scrape.mjs ${url} --format markdown --out ${outDir}`,
  { encoding: 'utf8' }
);

// 解析输出获取文件路径
const output = JSON.parse(result);
console.log('Markdown 文件:', output.files.markdown);
```

### 作为 MCP 工具暴露

可以将调度逻辑包装成 MCP tool，让 AI Agent 直接调用。参考 `docs/mcp-integration.md`（TODO）。

## 故障排查

### Scrapling 报错 "adaptive mode requires previous training"

自适应模式需要先正常抓取一次（训练），再在网站改版后启用 `--adaptive`。

**解决方案**：
```bash
# 第一次：训练
node "$SKILL_DIR/scripts/scrape.mjs" <url> --tool scrapling

# 第二次：自适应
node "$SKILL_DIR/scripts/scrape.mjs" <url> --tool scrapling --adaptive
```

### Crawl4AI 超时或被检测

某些站点的反爬严格，需要：
1. 增加 `--wait` 时间
2. 启用 `--stealth`
3. 配置代理（见 `scripts/scrape.mjs` 中的 `PROXY_LIST` 配置）

### Playwright 找不到浏览器

```bash
playwright install chromium
```

或指定全局 Playwright 路径（见 vft-ai:web-scrape 的依赖解析逻辑）。

## 安全注意事项

### Crawl4AI Docker Server 漏洞历史

如果你打算自建 Crawl4AI 的 Docker API Server：

⚠️ **必须使用 ≥ 0.9.0 版本**

- 0.8.5 及以前：`/crawl` 端点存在 **eval() RCE**
- 0.8.6：litellm PyPI 供应链投毒，已换成 fork
- 0.8.7 修复：AST 沙箱逃逸 RCE、硬编码 JWT secret、SSRF、任意文件写、XSS
- 0.9.0：默认开启鉴权，无 token 只绑 loopback

**本 skill 直接用 Python 库，不涉及 Docker Server，无此风险。**

### 代理配置

脚本支持通过环境变量或配置文件设置代理链：

```bash
export SCRAPE_PROXY_LIST="http://127.0.0.1:7890,socks5://127.0.0.1:1080"
node "$SKILL_DIR/scripts/scrape.mjs" <url>
```

代理按顺序尝试，失败自动 fallback。

## 技术细节

### 工具选择算法

```javascript
function selectTool(url, intent, options) {
  // 1. 强制指定
  if (options.tool) return options.tool;
  
  // 2. 意图关键词
  if (/markdown|LLM|喂给|训练/i.test(intent)) return 'crawl4ai';
  if (/批量|深度|递归|whole site/i.test(intent)) return 'crawl4ai';
  if (/cloudflare|turnstile|反爬|被拦/i.test(intent)) return 'scrapling';
  if (/自适应|网站改版|元素找不到/i.test(intent)) return 'scrapling';
  if (/资源|截图|网络请求|接口|XHR/i.test(intent)) return 'playwright';
  
  // 3. URL 模式
  if (/\/(docs?|wiki|blog|article|post)\//i.test(url)) return 'crawl4ai';
  
  // 4. 检测 Cloudflare（发 HEAD 请求看响应头）
  if (hasCloudflareProtection(url)) return 'scrapling';
  
  // 5. 默认策略：快速抓取 -> fallback
  return 'scrapling';  // 快速，失败后 fallback 到 playwright
}
```

### Fallback 机制

```
Scrapling (快速) 
  ↓ 失败（403/503/超时）
Playwright (渲染)
  ↓ 仍失败
Crawl4AI (重度反检测)
```

每个工具失败后自动尝试下一个，最终返回成功的结果或所有错误日志。

## 许可证

- **Scrapling**: Apache-2.0（需在使用处署名）
- **Crawl4AI**: Apache-2.0（需在使用处署名）
- **Playwright**: Apache-2.0

本 skill 作为 vft-kit 的一部分遵循 vft-kit 的许可证。使用时需遵守上游工具的 attribution 要求。

## 相关文档

- [vft-ai:web-scrape](../../vft-ai/skills/web-scrape/SKILL.md) - 原始 Playwright 实现
- [Scrapling 官方文档](https://scrapling.readthedocs.io)
- [Crawl4AI 官方文档](https://crawl4ai.com)
- [场景选择算法详解](docs/tool-selection.md)（TODO）
- [MCP 集成指南](docs/mcp-integration.md)（TODO）
