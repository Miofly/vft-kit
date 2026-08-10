# web-scrape - 项目总结

## 🎉 已完成

为 vft-kit 创建了智能网页抓取 skill，整合了三种最佳抓取工具并根据场景自动选择。

## 📁 文件结构

```
vft-kit/plugins/vft-kit/skills/web-scrape/
├── SKILL.md                        # 完整使用文档（主文档）
├── QUICKSTART.md                   # 快速开始指南
├── install-deps.sh                 # 依赖安装脚本
│
├── scripts/
│   ├── scrape.mjs                  # 核心调度器（场景识别 + 工具选择）
│   ├── scrapling-worker.py         # Scrapling 执行器
│   └── crawl4ai-worker.py          # Crawl4AI 执行器
│
├── tests/
│   └── integration.test.mjs        # 集成测试（场景识别验证）
│
└── docs/
    ├── architecture.md             # 架构设计文档
    └── tool-selection.md           # 工具选择决策树
```

## 🚀 核心特性

### 1. 智能场景识别

根据 **URL 模式** + **用户意图** + **实时检测** 自动选择最佳工具：

| 场景 | 自动选择 | 原因 |
|------|---------|------|
| URL 包含 `/docs/` | **Crawl4AI** | 文档站常需批量 + Markdown |
| 意图："转成 Markdown 喂 LLM" | **Crawl4AI** | fit_markdown 去噪最佳 |
| 意图："绕过 Cloudflare" | **Scrapling** | 内置 Turnstile 专杀 |
| 意图："网站经常改版" | **Scrapling** | 自适应解析器抗改版 |
| 意图："需要所有静态资源" | **Playwright** | 完整渲染 + 资源下载 |
| HEAD 检测到 `CF-Ray` 头 | **Scrapling** | 实时检测 Cloudflare |

### 2. 三种工具整合

| 工具 | 优势 | 适用场景 |
|------|------|---------|
| **Scrapling** | 最快 + Cloudflare 专杀 + 自适应解析 | 快速抓取、反爬、网站改版 |
| **Crawl4AI** | LLM-ready Markdown + 深度爬取 + 崩溃恢复 | 喂 LLM、批量文档、RAG |
| **Playwright** | 完整资源 + 网络监控 + 截图 | 资源下载、接口日志、调试 |

### 3. Fallback 机制

工具失败自动重试下一个：
```
Scrapling (快速)
  ↓ 失败
Playwright (渲染)
  ↓ 失败
Crawl4AI (重度反检测)
```

### 4. 内置 Playwright Worker

Playwright 实现随公版 skill 分发，不依赖私有仓库：
```javascript
// scrape.mjs 中调用
spawn('node', [join(__dirname, 'playwright-worker.mjs'), url, ...args]);
```

## 🔧 快速开始

### 1. 安装依赖

```bash
cd /Users/wfly/Documents/code/wfly/bolierplate/project/vft-kit/plugins/vft-kit/skills/web-scrape
./install-deps.sh
```

选择 **选项 2**（venv 虚拟环境，推荐）

### 2. 运行测试

```bash
# 激活 venv（如果用了 venv）
source ~/.scrape-venv/bin/activate

# 运行集成测试
node tests/integration.test.mjs
```

预期输出：
```
🧪 web-scrape 集成测试

检查 Python 依赖...
  Python: ✅
  Scrapling: ✅
  Crawl4AI: ✅
  Playwright: ✅

━━━ 文档站自动识别 ━━━
🎯 检测到文档站 URL 模式 → Crawl4AI
✅ 成功（工具: crawl4ai, 耗时: 3245ms）

━━━ 测试结果汇总 ━━━

✅ 文档站自动识别 (crawl4ai)
✅ Markdown 意图 (crawl4ai)
✅ 反爬意图 (scrapling)
✅ 资源抓取意图 (playwright)
✅ 强制指定工具 (scrapling)

总计: 5 | 通过: 5 | 失败: 0 | 跳过: 0 | 警告: 0

✅ 所有测试通过
```

### 3. 基础使用

```bash
# 自动选择工具
node scripts/scrape.mjs https://docs.python.org/3/library/asyncio.html

# 指定意图
node scripts/scrape.mjs https://example.com \
  --intent "转成 Markdown 喂给 LLM"

# 深度爬取
node scripts/scrape.mjs https://example.com/docs \
  --deep --max-pages 50 --strategy bfs

# 强制指定工具
node scripts/scrape.mjs https://example.com --tool scrapling
```

### 4. 在 Claude Code 中使用

直接对 Claude Code 说：

```
用 web-scrape 抓取 https://docs.python.org 并转成 Markdown
```

或：

```
深度爬取 https://example.com/docs 最多 50 页
```

## 📊 技术亮点

### 1. 安全的命令执行

使用 `spawn()` + 参数数组，防止命令注入：

```javascript
// ❌ 危险
exec(`python3 worker.py ${userInput}`);

// ✅ 安全
spawn('python3', ['worker.py', userInput]);
```

### 2. 配置传递设计

调度器 → Worker 通过临时 JSON 文件：
- 避免命令行参数过长
- 支持复杂配置结构
- 不暴露敏感信息

### 3. 依赖检测

自动检测 Python 包并给出安装命令：
```javascript
const packages = JSON.parse(execSync('python3 -m pip list --format=json'));
if (!packages.includes('scrapling')) {
  console.error('请安装: pip install scrapling');
}
```

### 4. 元信息追踪

每次抓取生成 `meta.json`：
```json
{
  "url": "https://example.com",
  "tool": "crawl4ai",
  "reason": "文档站 URL 模式",
  "timestamp": "2026-08-07T21:30:00Z",
  "duration_ms": 3245
}
```

## 🎯 使用场景

### 场景 1：技术文档抓取

**需求**：抓取整个 Python 文档站，转成 Markdown 喂给 LLM 做 RAG

**命令**：
```bash
node scripts/scrape.mjs https://docs.python.org/3/library/ \
  --deep --max-pages 100 --format markdown
```

**自动选择**：Crawl4AI（文档站 URL + Markdown 格式）

### 场景 2：受 Cloudflare 保护的站点

**需求**：绕过 Cloudflare Turnstile 抓取内容

**命令**：
```bash
node scripts/scrape.mjs https://protected-site.com \
  --intent "这个站被 Cloudflare 拦了" --stealth
```

**自动选择**：Scrapling（反爬意图 + 实时 CF 检测）

### 场景 3：网站频繁改版

**需求**：产品页面经常改版，普通选择器总失效

**命令**：
```bash
# 第一次：训练
node scripts/scrape.mjs https://example.com/products --tool scrapling

# 改版后：自适应
node scripts/scrape.mjs https://example.com/products --tool scrapling --adaptive
```

**工具**：Scrapling 自适应解析器

### 场景 4：调试 SPA 应用

**需求**：需要完整静态资源和所有 XHR/fetch 请求

**命令**：
```bash
node scripts/scrape.mjs https://app.example.com \
  --tool playwright --wait 3000
```

**工具**：Playwright（输出 network.json + resources/）

## 📚 文档导航

- **[SKILL.md](SKILL.md)** - 完整功能文档（优先阅读）
- **[QUICKSTART.md](QUICKSTART.md)** - 快速开始
- **[docs/tool-selection.md](docs/tool-selection.md)** - 工具选择决策树
- **[docs/architecture.md](docs/architecture.md)** - 架构设计

## 🔗 工具对比

| 特性 | Scrapling | Crawl4AI | Playwright |
|------|-----------|----------|------------|
| **速度** | ⚡⚡⚡ | ⚡⚡ | ⚡ |
| **反检测** | Cloudflare 专杀 | Stealth + 代理 | 基础 |
| **自适应** | ✅ 网站改版自动定位 | ❌ | ❌ |
| **深度爬取** | ✅ Spider | ✅ BFS/DFS | ❌ |
| **LLM 输出** | ⭐⭐ | ⭐⭐⭐⭐⭐ fit_markdown | ⭐⭐⭐ |
| **资源下载** | ❌ | ❌ | ✅ |
| **网络监控** | ❌ | ❌ | ✅ network.json |

## ⚠️ 注意事项

### 1. Crawl4AI 安全历史

**如果自建 Docker API Server，必须 ≥ 0.9.0**

- 0.8.5 及以前：`/crawl` 端点 RCE 漏洞
- 0.8.7：AST 沙箱逃逸、硬编码 JWT、SSRF
- 0.9.0：默认开鉴权、安全加固

**本 skill 直接用 Python 库，不涉及 Docker Server，无此风险。**

### 2. 许可证

- Scrapling: Apache-2.0（需署名）
- Crawl4AI: Apache-2.0（需署名）
- Playwright: Apache-2.0

使用时需遵守上游工具的 attribution 要求。

### 3. 依赖版本

建议版本：
- Python ≥ 3.8
- Node.js ≥ 18
- scrapling 最新版
- crawl4ai ≥ 0.9.0
- playwright 最新版

## 🚀 下一步

### 立即可用

1. 运行 `./install-deps.sh` 安装依赖
2. 运行 `node tests/integration.test.mjs` 验证
3. 开始使用 `node scripts/scrape.mjs <url>`

### 后续优化（可选）

1. **添加到 vft-kit README**：在主 README 中添加 skill 入口
2. **Claude Code 集成**：测试 Claude Code 中的 skill 调用
3. **MCP Server 封装**：将调度器封装成 MCP tool
4. **Docker 镜像**：打包完整运行时环境

### 扩展功能（未来）

1. **代理轮换**：自动检测失败并切换代理
2. **结果缓存**：避免重复抓取同一 URL
3. **Web UI**：可视化配置和监控
4. **分布式爬虫**：多机协同批量抓取

## 💡 设计亮点

1. **依赖方向清晰**：公版自包含抓取能力，私版只注入登录态
2. **智能决策**：多维度场景识别（URL + 意图 + 实时检测）
3. **优雅降级**：Fallback 链保证至少有一个工具成功
4. **依赖隔离**：支持 venv 避免污染系统环境
5. **安全优先**：spawn() 而非 exec()，配置文件而非命令行参数
6. **可追溯**：meta.json 记录每次抓取的工具选择依据

## 🎓 学习资源

- [Scrapling 官方文档](https://scrapling.readthedocs.io)
- [Crawl4AI GitHub](https://github.com/unclecode/crawl4ai)
- [Playwright 文档](https://playwright.dev)

---

**问题反馈**：如遇到问题，检查：
1. Python 依赖是否安装完整（`pip list | grep -E 'scrapling|crawl4ai|playwright'`）
2. Playwright 浏览器是否安装（`playwright install chromium`）
3. venv 是否激活（`which python3` 应指向 venv）
4. 查看 `meta.json` 中的 `reason` 字段了解工具选择依据

**成功标志**：`node tests/integration.test.mjs` 全部通过 ✅
