# smart-web-scrape 架构设计

## 系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        Claude Code / User                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   scrape.mjs (调度器)                            │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ 1. 参数解析与验证                                         │  │
│  │ 2. 场景识别引擎 (selectTool)                             │  │
│  │ 3. 依赖检查 (checkDependencies)                          │  │
│  │ 4. 工具执行 + Fallback (executeWithFallback)            │  │
│  │ 5. 元信息收集与输出                                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────┬───────────────────┬──────────────────┬────────────┘
              │                   │                  │
              ▼                   ▼                  ▼
┌─────────────────────┐ ┌──────────────────┐ ┌────────────────────┐
│ Scrapling Worker    │ │ Crawl4AI Worker  │ │ Playwright (vft-ai)│
│ (scrapling-worker.py)│ │(crawl4ai-worker.py)│ │  web-scrape        │
│                     │ │                  │ │                    │
│ • 自适应解析         │ │ • fit_markdown   │ │ • 完整渲染          │
│ • Stealth 模式       │ │ • BM25 过滤      │ │ • 资源下载          │
│ • Spider 深度爬取    │ │ • 深度爬取 BFS   │ │ • 网络监控          │
│ • Cloudflare 绕过    │ │ • 崩溃恢复       │ │ • 截图/PDF          │
└─────────────────────┘ └──────────────────┘ └────────────────────┘
              │                   │                  │
              └───────────────────┴──────────────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │   输出目录           │
                  │  • meta.json        │
                  │  • content.html/md  │
                  │  • resources/       │
                  │  • network.json     │
                  │  • screenshot.png   │
                  │  • deep-crawl/      │
                  └─────────────────────┘
```

## 核心组件

### 1. 调度器 (scrape.mjs)

**职责**：
- 参数解析与验证
- 场景识别（工具选择算法）
- 依赖检查与提示
- 工具执行编排
- Fallback 机制
- 元信息收集

**关键函数**：

```javascript
parseArgs()              // 解析命令行参数
selectTool(url, intent)  // 场景识别引擎
checkDependencies(tool)  // 检查 Python 依赖
executeWithFallback()    // 执行 + 失败重试
runScrapling()           // 调用 Scrapling Worker
runCrawl4AI()            // 调用 Crawl4AI Worker
runPlaywright()          // 调用 Playwright（vft-ai）
```

**技术栈**：
- Node.js ES Modules
- child_process.spawn（安全执行）
- 异步流程控制（Promise）

### 2. Scrapling Worker (scrapling-worker.py)

**职责**：
- 自适应网页解析
- Cloudflare Turnstile 绕过
- 隐蔽模式抓取
- Spider 深度爬取

**关键特性**：
```python
# 自适应模式
StealthyFetcher.adaptive = True
page = StealthyFetcher.fetch(url, headless=True, network_idle=True)

# 深度爬取
class SmartSpider(Spider):
    async def parse(self, response: Response):
        yield {'url': response.url, 'title': ...}
        for link in response.css('a::attr(href)').getall():
            yield response.follow(link, self.parse)
```

**技术栈**：
- Python 3.8+
- Scrapling 库
- 异步 Spider 框架

### 3. Crawl4AI Worker (crawl4ai-worker.py)

**职责**：
- LLM-ready Markdown 生成
- fit_markdown 启发式去噪
- BM25 内容过滤
- 深度爬取（BFS/DFS/BestFirst）

**关键特性**：
```python
async with AsyncWebCrawler() as crawler:
    result = await crawler.arun(
        url=url,
        word_count_threshold=10,  # 去噪阈值
        bypass_cache=True,
    )
    # result.markdown 已去噪、BM25 过滤
```

**技术栈**：
- Python 3.8+
- Crawl4AI 库
- Playwright (底层)
- 异步 asyncio

### 4. Playwright Adapter (vft-ai:web-scrape)

**职责**：
- 完整页面渲染
- 静态资源下载
- 网络请求监控
- 截图与 PDF

**集成方式**：
```javascript
// scrape.mjs 中调用
const vftAiSkillDir = join(__dirname, '../../../../../vft-ai/skills/web-scrape');
const scrapeScript = join(vftAiSkillDir, 'scripts/scrape.mjs');
spawn('node', [scrapeScript, url, ...args]);
```

**技术栈**：
- Playwright
- Chromium/Firefox/WebKit
- 资源拦截与下载

## 数据流

### 单页抓取流程

```
用户输入
  ↓
[参数解析]
  ↓
URL + 意图
  ↓
[场景识别]
  ↓
选择工具 (scrapling/crawl4ai/playwright)
  ↓
[依赖检查]
  ↓
生成配置 JSON
  ↓
[启动 Worker]
  ↓
Worker 执行抓取
  ↓
写入输出文件
  ↓
[收集元信息]
  ↓
返回结果 JSON
  ↓
用户查看输出
```

### 深度爬取流程

```
起始 URL
  ↓
[首页抓取]
  ↓
提取链接列表
  ↓
[策略选择]
  BFS: 队列头部取出 (先进先出)
  DFS: 队列尾部取出 (后进先出)
  ↓
逐个抓取（最多 maxPages）
  ↓
每页保存 page-NNN.html/md
  ↓
生成索引 index.json
  ↓
返回汇总结果
```

### Fallback 流程

```
执行工具 A
  ↓
成功? ────→ 返回结果
  ↓ 失败
记录错误
  ↓
执行工具 B (fallback)
  ↓
成功? ────→ 返回结果
  ↓ 失败
记录错误
  ↓
执行工具 C (最后备份)
  ↓
成功? ────→ 返回结果
  ↓ 失败
汇总所有错误 → 抛出异常
```

## 配置传递

### 调度器 → Worker

通过临时配置文件（JSON）：

```javascript
// scrape.mjs 写入配置
const configPath = join(outDir, 'scrapling-config.json');
writeFileSync(configPath, JSON.stringify({
  url, outDir, adaptive, stealth, ...
}));

// 启动 Worker
spawn(CONFIG.pythonCmd, [scriptPath, configPath]);
```

```python
# scrapling-worker.py 读取配置
with open(sys.argv[1], 'r') as f:
    config = json.load(f)

url = config['url']
adaptive = config.get('adaptive', False)
```

### Worker → 调度器

通过标准输出（stdout）：

```python
# Worker 打印进度（stderr）
print(f"✅ HTML 已保存", file=sys.stderr)

# Worker 返回结果（stdout，调度器不捕获）
# 调度器通过检查输出目录验证成功
sys.exit(0)  # 退出码 0 = 成功
```

## 依赖管理

### Python 依赖检测

```javascript
function checkDependencies(tool) {
  // 1. 检查 Python 可执行文件
  execSync(`${CONFIG.pythonCmd} --version`);

  // 2. 检查已安装包
  const output = execSync(`${CONFIG.pythonCmd} -m pip list --format=json`);
  const packages = JSON.parse(output).map(p => p.name.toLowerCase());

  // 3. 验证工具所需依赖
  if (tool === 'scrapling' && !packages.includes('scrapling')) {
    throw new Error('缺少 scrapling');
  }
}
```

### 依赖隔离（venv）

```bash
# install-deps.sh 创建 venv
python3 -m venv ~/.scrape-venv
source ~/.scrape-venv/bin/activate
pip install scrapling crawl4ai playwright
```

Worker 自动使用激活的 venv：
```javascript
// 如果 venv 已激活，python3 指向 venv 中的 Python
spawn(CONFIG.pythonCmd, [...]);  // 自动使用 venv
```

## 错误处理

### 分层错误处理

1. **参数层**：
   - 无效 URL → 立即退出，提示用法
   - 无效选项 → 立即退出，提示可用选项

2. **依赖层**：
   - Python 不可用 → 退出，提示安装 Python
   - 包缺失 → 退出，提示 pip install 命令

3. **执行层**：
   - 工具失败 → 记录错误，尝试 fallback
   - 超时 → 记录错误，尝试 fallback
   - 所有工具失败 → 汇总错误，退出

4. **输出层**：
   - 输出目录创建失败 → 退出
   - 文件写入失败 → 记录警告，继续

### 错误信息格式

```javascript
// 单个工具失败
{
  tool: 'scrapling',
  error: 'Scrapling 失败，退出码: 1'
}

// 所有工具失败
❌ 所有工具都失败了:
  - scrapling: Scrapling 失败，退出码: 1
  - playwright: vft-ai:web-scrape 不可用（未找到脚本）
  - crawl4ai: 缺少依赖: crawl4ai
```

## 性能优化

### 1. 场景识别优先级

高优先级检查放前面（快速失败）：
```javascript
async function selectTool(url, intent, options) {
  // 1. 强制指定（O(1)）
  if (options.tool) return options.tool;

  // 2. 意图关键词（O(1)，正则匹配）
  if (/markdown/.test(intent)) return 'crawl4ai';

  // 3. URL 模式（O(1)，正则匹配）
  if (/\/docs?\//.test(url)) return 'crawl4ai';

  // 4. Cloudflare 检测（O(n)，网络请求，最慢）
  if (await detectCloudflare(url)) return 'scrapling';

  return 'scrapling';
}
```

### 2. 并发控制

深度爬取时限制并发：
```python
# Crawl4AI Worker
to_crawl = [url]
visited = set()

while to_crawl and page_count < max_pages:
    current_url = to_crawl.pop(0)  # BFS
    result = await crawler.arun(current_url)
    # 单线程顺序执行，避免目标站点过载
```

### 3. 缓存机制

Crawl4AI 内置缓存：
```python
result = await crawler.arun(
    url=url,
    bypass_cache=False,  # 使用缓存（重复抓取时更快）
)
```

## 安全考虑

### 1. 命令注入防护

使用 `spawn()` + 参数数组，不用 `exec()` + 字符串拼接：

```javascript
// ❌ 危险（命令注入）
exec(`node ${scriptPath} ${url}`);

// ✅ 安全
spawn('node', [scriptPath, url]);
```

### 2. 路径遍历防护

输出目录限制在 `other/scrape` 下：
```javascript
const outDir = join(process.cwd(), options.out, `${domain}-${timestamp}`);
// options.out 被限制在 other/scrape，无法写入敏感目录
```

### 3. 配置文件权限

临时配置文件只在输出目录创建，不会泄露到系统目录。

### 4. Python 沙箱

Worker 脚本只读取配置、抓取网页、写入输出目录，不执行任意代码。

## 可扩展性

### 添加新工具

1. 创建 Worker 脚本（如 `newTool-worker.py`）
2. 在 `scrape.mjs` 中添加执行函数：
   ```javascript
   async function runNewTool(url, options, outDir) {
     const scriptPath = join(__dirname, 'newTool-worker.py');
     // ... 执行逻辑
   }
   ```
3. 在 `selectTool()` 中添加场景识别规则
4. 更新 fallback 链

### 添加输出格式

在 Worker 中添加格式转换：
```python
if config.get('format') == 'json':
    output = {'url': url, 'html': html, 'text': text}
    json_path = out_dir / 'content.json'
    with open(json_path, 'w') as f:
        json.dump(output, f)
```

### 集成第三方服务

代理配置示例：
```javascript
// scrape.mjs
const CONFIG = {
  proxyList: process.env.SCRAPE_PROXY_LIST.split(','),
};

// Worker 配置传递
writeFileSync(configPath, JSON.stringify({
  ...config,
  proxies: CONFIG.proxyList,
}));
```

## 测试策略

### 单元测试（TODO）

- `selectTool()` 逻辑测试
- `checkDependencies()` 模拟测试
- `parseArgs()` 边界测试

### 集成测试

已实现 `tests/integration.test.mjs`：
- 场景识别测试（文档站、Markdown 意图等）
- 工具选择验证
- 输出文件验证
- 依赖检测测试

### 端到端测试（TODO）

- 真实网站抓取
- 深度爬取完整性
- Fallback 机制验证

## 监控与日志

### 进度输出

```javascript
console.log('🕷️  smart-web-scrape\n');
console.log(`URL: ${url}`);
console.log('🎯 检测到 LLM/Markdown 意图 → Crawl4AI');
console.log('\n🚀 使用 Crawl4AI 抓取...\n');
console.log('✅ 抓取完成！');
```

### 元信息记录

```json
{
  "url": "https://example.com",
  "tool": "crawl4ai",
  "reason": "文档站 URL 模式",
  "timestamp": "2026-08-07T21:30:00Z",
  "duration_ms": 3245,
  "options": {
    "format": "markdown",
    "deep": false
  }
}
```

### 错误日志

Worker 错误输出到 stderr：
```python
print(f"❌ Crawl4AI 执行失败: {e}", file=sys.stderr)
```

调度器捕获并记录：
```javascript
errors.push({ tool: 'crawl4ai', error: error.message });
```

## 部署建议

### 开发环境

```bash
# venv 隔离
python3 -m venv ~/.scrape-venv
source ~/.scrape-venv/bin/activate
pip install scrapling crawl4ai playwright
playwright install chromium
```

### 生产环境（Docker，TODO）

```dockerfile
FROM python:3.11-slim
RUN apt-get update && apt-get install -y nodejs npm
RUN pip install scrapling crawl4ai playwright
RUN playwright install --with-deps chromium
COPY . /app
WORKDIR /app
ENTRYPOINT ["node", "scripts/scrape.mjs"]
```

### CI/CD 集成

GitHub Actions 示例：
```yaml
- name: Setup Python
  uses: actions/setup-python@v4
  with:
    python-version: '3.11'

- name: Install dependencies
  run: |
    pip install scrapling crawl4ai playwright
    playwright install chromium

- name: Run tests
  run: node tests/integration.test.mjs
```

## 未来计划

### v1.1（短期）

- [ ] 添加 `--proxy` 支持
- [ ] 实现诊断工具 `diagnose.mjs`
- [ ] 支持自定义场景规则配置文件
- [ ] 添加结果缓存（避免重复抓取）

### v1.2（中期）

- [ ] Docker 镜像发布
- [ ] MCP Server 封装
- [ ] Web UI Dashboard
- [ ] 支持更多输出格式（PDF、EPUB）

### v2.0（长期）

- [ ] 分布式爬虫支持
- [ ] 智能反检测增强（机器学习）
- [ ] 实时爬取监控面板
- [ ] 云端部署方案（Cloudflare Workers）

## 相关资源

- [SKILL.md](../SKILL.md) - 完整使用文档
- [QUICKSTART.md](../QUICKSTART.md) - 快速开始
- [tool-selection.md](tool-selection.md) - 工具选择决策树
- [Scrapling GitHub](https://github.com/D4Vinci/Scrapling)
- [Crawl4AI GitHub](https://github.com/unclecode/crawl4ai)
