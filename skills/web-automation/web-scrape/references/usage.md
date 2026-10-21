# 用法、选项、示例与输出结构

## 用法

### 基础调用

```bash
# 在 vft-kit 项目根目录
SKILL_DIR="skills/web-automation/web-scrape"
node "$SKILL_DIR/scripts/scrape.mjs" <url> [options]
```

或通过 Claude Code skill：

```text
用 web-scrape 抓取 https://example.com 并转成 Markdown
```

### 选项

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `--tool <name>` | 强制使用工具：`scrapling`/`crawl4ai`/`ego`/`playwright` | 自动选择 |
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
| `--no-resources` | 不下载静态资源（仅 Playwright 兜底） | `false` |
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
├── network.json           # 网络请求日志（ego-lite / Playwright）
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
