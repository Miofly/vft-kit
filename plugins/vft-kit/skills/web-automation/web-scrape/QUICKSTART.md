# web-scrape 快速开始

## 安装依赖

```bash
cd /path/to/vft-kit/plugins/vft-kit/skills/web-automation/web-scrape
./install-deps.sh
```

选择安装方式：
- **选项 1**：全局安装（简单，但可能污染系统环境）
- **选项 2**：venv 虚拟环境（推荐，隔离依赖）

如果选择 venv，每次使用前需激活：
```bash
source ~/.scrape-venv/bin/activate
```

## 基础使用

### 1. 自动选择工具（推荐）

让 AI 根据场景自动选择最佳工具：

```bash
# 文档站 → 自动选 Crawl4AI
node scripts/scrape.mjs https://docs.python.org/3/library/asyncio.html

# 明确意图 → 指导工具选择
node scripts/scrape.mjs https://example.com/blog \
  --intent "抓取文章转成 Markdown 喂给 LLM"
```

### 2. 强制指定工具

```bash
# 用 Scrapling（快速 + 自适应）
node scripts/scrape.mjs https://example.com --tool scrapling

# 用 Crawl4AI（LLM-ready Markdown）
node scripts/scrape.mjs https://example.com --tool crawl4ai --format markdown

# 用 Playwright（完整资源 + 网络监控）
node scripts/scrape.mjs https://example.com --tool playwright
```

### 3. 深度爬取

```bash
# 爬整个文档站（BFS 策略）
node scripts/scrape.mjs https://scrapling.readthedocs.io \
  --deep --max-pages 50 --strategy bfs

# DFS 策略（深度优先）
node scripts/scrape.mjs https://example.com/docs \
  --deep --max-pages 30 --strategy dfs
```

### 4. 自适应抓取（网站频繁改版）

```bash
# 第一次：训练
node scripts/scrape.mjs https://example.com/products \
  --tool scrapling

# 网站改版后：自适应重新定位
node scripts/scrape.mjs https://example.com/products \
  --tool scrapling --adaptive
```

## 常见场景

### 场景 1：博客文章转 Markdown

```bash
node scripts/scrape.mjs https://blog.example.com/post/123 \
  --format markdown
# → Crawl4AI fit_markdown 去噪
```

### 场景 2：绕过 Cloudflare

```bash
node scripts/scrape.mjs https://protected-site.com \
  --tool scrapling --stealth
# → Scrapling Turnstile 绕过
```

### 场景 3：完整资源 + API 调用日志

```bash
node scripts/scrape.mjs https://app.example.com \
  --tool playwright --wait 3000
# → 输出 HTML + CSS/JS/图片 + network.json
```

### 场景 4：批量爬文档站

```bash
node scripts/scrape.mjs https://docs.example.com \
  --deep --max-pages 100 --format markdown
# → Crawl4AI BFS 爬取 + Markdown
```

## 输出文件

```
other/scrape/<域名>-<时间戳>/
├── meta.json              # 元信息（工具、耗时）
├── content.html           # HTML（Scrapling/Playwright）
├── content.md             # Markdown（Crawl4AI）
├── resources/             # 静态资源（仅 Playwright）
├── network.json           # 网络请求（仅 Playwright）
├── screenshot.png         # 截图
└── deep-crawl/            # 深度爬取结果
    ├── page-001.md
    ├── page-002.md
    └── index.json
```

## 运行测试

```bash
node tests/integration.test.mjs
```

测试会：
1. 检查 Python 依赖
2. 测试场景识别（文档站、Markdown 意图、反爬意图等）
3. 测试工具选择和 fallback
4. 验证输出文件

## 故障排查

### 问题 1：`playwright: command not found`

```bash
pip install playwright
playwright install chromium
```

### 问题 2：Scrapling 报错 "adaptive mode requires training"

自适应模式需要先正常抓取一次：

```bash
# 第一次：训练
node scripts/scrape.mjs <url> --tool scrapling

# 第二次：自适应
node scripts/scrape.mjs <url> --tool scrapling --adaptive
```

### 问题 3：Crawl4AI 超时

增加等待时间和超时：

```bash
node scripts/scrape.mjs <url> --wait 5000 --timeout 120000
```

### 问题 4：依赖冲突

使用 venv 隔离：

```bash
python3 -m venv ~/.scrape-venv
source ~/.scrape-venv/bin/activate
pip install scrapling crawl4ai playwright
playwright install chromium
```

## 在 Claude Code 中使用

直接对 Claude Code 说：

```text
用 web-scrape 抓取 https://docs.python.org 并转成 Markdown
```

或：

```text
深度爬取 https://example.com/docs 最多 50 页
```

Claude Code 会自动调用 skill 并选择最佳工具。

## 集成到其他项目

```javascript
import { execFile } from 'child_process';
import { promisify } from 'util';

const execFileAsync = promisify(execFile);

async function scrapeWebsite(url, intent) {
  const { stdout } = await execFileAsync('node', [
    '/path/to/vft-kit/plugins/vft-kit/skills/web-automation/web-scrape/scripts/scrape.mjs',
    url,
    '--intent', intent,
    '--out', './output',
  ]);

  // 解析最后一行 JSON
  const lines = stdout.trim().split('\n');
  const result = JSON.parse(lines[lines.length - 1]);

  console.log('工具:', result.tool);
  console.log('输出目录:', result.outDir);
  console.log('耗时:', result.duration, 'ms');

  return result;
}

// 使用
await scrapeWebsite('https://example.com', '转成 Markdown');
```

## 高级配置

### 代理设置

```bash
export SCRAPE_PROXY_LIST="http://127.0.0.1:7890,socks5://127.0.0.1:1080"
node scripts/scrape.mjs <url>
```

### Python 路径

```bash
export PYTHON_CMD=/usr/local/bin/python3
node scripts/scrape.mjs <url>
```

### 输出目录

```bash
export SCRAPE_OUT_DIR=/custom/output/dir
node scripts/scrape.mjs <url>
```

## 性能对比

| 工具 | 速度 | 反检测 | 输出质量（LLM） | 资源下载 |
|------|------|--------|----------------|----------|
| Scrapling | ⚡⚡⚡ | Cloudflare 专杀 | ⭐⭐ | ❌ |
| Crawl4AI | ⚡⚡ | Stealth + 代理 | ⭐⭐⭐⭐⭐ | ❌ |
| Playwright | ⚡ | 基础 | ⭐⭐⭐ | ✅ |

- **Scrapling**：最快，适合简单抓取和反 Cloudflare
- **Crawl4AI**：最适合喂 LLM（fit_markdown 去噪）
- **Playwright**：最全面（资源 + 网络监控）

## 许可证

- Scrapling: Apache-2.0
- Crawl4AI: Apache-2.0
- Playwright: Apache-2.0

使用时需遵守上游工具的 attribution 要求。

## 相关资源

- [Scrapling 文档](https://scrapling.readthedocs.io)
- [Crawl4AI 文档](https://crawl4ai.com)
- [Playwright 文档](https://playwright.dev)
