# 工具选择决策树

web-scrape 的场景识别引擎根据以下决策树选择最佳工具：

```
开始
  │
  ├─ 用户强制指定 --tool？
  │   └─ 是 → 使用指定工具
  │
  ├─ 意图关键词分析
  │   │
  │   ├─ 包含 "markdown|LLM|喂给|训练|RAG|总结|问答"？
  │   │   └─ 是 → Crawl4AI（LLM-ready 输出）
  │   │
  │   ├─ 包含 "批量|深度|递归|整站|多页"？
  │   │   └─ 是 → Crawl4AI（深度爬取 + 崩溃恢复）
  │   │
  │   ├─ 包含 "cloudflare|turnstile|反爬|被拦|403"？
  │   │   └─ 是 → Scrapling（Turnstile 专杀）
  │   │
  │   ├─ 包含 "自适应|网站改版|元素找不到"？
  │   │   └─ 是 → Scrapling（自适应解析器）
  │   │
  │   └─ 包含 "资源|截图|网络请求|接口|XHR"？
  │       └─ 是 → Playwright（完整资源 + 网络监控）
  │
  ├─ URL 模式匹配
  │   │
  │   └─ 匹配 "/(docs?|wiki|blog|article|post)/"？
  │       └─ 是 → Crawl4AI（文档站常需批量 + Markdown）
  │
  ├─ Cloudflare 检测（发 HEAD 请求）
  │   │
  │   └─ 检测到 CF-Ray 头或 server: cloudflare？
  │       └─ 是 → Scrapling（内置 Turnstile 绕过）
  │
  └─ 默认策略
      └─ Scrapling（快速抓取，失败后 fallback）
```

## 决策优先级

1. **强制指定** (`--tool`) - 最高优先级
2. **意图关键词** - 用户明确表达的需求
3. **URL 模式** - 推断常见站点类型
4. **实时检测** - 动态探测防护措施
5. **默认策略** - 快速 → 全面的 fallback 链

## Fallback 链

当选中的工具失败时，按以下顺序尝试：

```
原始选择
  ↓ 失败（403/503/超时/依赖缺失）
Scrapling（快速）
  ↓ 失败
Playwright（渲染完整）
  ↓ 失败
Crawl4AI（重度反检测）
  ↓ 全部失败
返回错误
```

### Fallback 触发条件

- HTTP 403/503 状态码
- 请求超时
- Python 依赖缺失
- 工具执行异常
- 内容为空或明显错误

## 场景示例

### 场景 1：文档站批量爬取

```bash
URL: https://docs.python.org/3/library/
意图: "抓取所有文档"
```

**决策路径**：
1. 无强制指定 ✗
2. 意图关键词 "抓取所有" 匹配 "批量" ✓
3. **选择：Crawl4AI**

**原因**：批量爬取 + 文档站 URL 模式 → Crawl4AI 的深度爬取最适合

### 场景 2：Cloudflare 保护的站点

```bash
URL: https://protected-site.com
意图: "这个站被 Cloudflare 拦了"
```

**决策路径**：
1. 无强制指定 ✗
2. 意图关键词 "Cloudflare 拦" 匹配 "cloudflare|反爬" ✓
3. **选择：Scrapling**

**原因**：明确的反爬需求 → Scrapling 内置 Turnstile 绕过

### 场景 3：喂给 LLM 的内容

```bash
URL: https://blog.example.com/post/123
意图: "转成 Markdown 喂给 GPT"
```

**决策路径**：
1. 无强制指定 ✗
2. 意图关键词 "Markdown 喂给" 匹配 "markdown|LLM|喂给" ✓
3. **选择：Crawl4AI**

**原因**：LLM 输出需求 → Crawl4AI 的 fit_markdown 去噪最佳

### 场景 4：网站频繁改版

```bash
URL: https://example.com/products
意图: "这个网站经常改版，元素位置总变"
```

**决策路径**：
1. 无强制指定 ✗
2. 意图关键词 "经常改版|元素位置" 匹配 "自适应|网站改版" ✓
3. **选择：Scrapling**

**原因**：抗改版需求 → Scrapling 的自适应解析器

### 场景 5：需要完整资源

```bash
URL: https://app.example.com
意图: "需要所有静态资源和接口调用"
```

**决策路径**：
1. 无强制指定 ✗
2. 意图关键词 "静态资源|接口调用" 匹配 "资源|接口|XHR" ✓
3. **选择：Playwright**

**原因**：资源 + 网络监控需求 → Playwright 最全面

### 场景 6：无明确意图

```bash
URL: https://example.com
意图: ""（空）
```

**决策路径**：
1. 无强制指定 ✗
2. 无意图关键词匹配 ✗
3. URL 不匹配文档站模式 ✗
4. 发送 HEAD 请求检测 Cloudflare... 未检测到 ✗
5. **选择：Scrapling（默认）**

**原因**：快速抓取，失败后自动 fallback 到 Playwright → Crawl4AI

## 关键词扩展

### Crawl4AI 触发词

**LLM 相关**：
- markdown, LLM, 喂给, 训练, RAG, 总结, 问答, 摘要, 向量化

**批量爬取**：
- 批量, 深度, 递归, whole site, 整站, 多页, 全量, 所有页面

### Scrapling 触发词

**反爬绕过**：
- cloudflare, turnstile, 反爬, 被拦, 403, bot detect, 验证码

**自适应**：
- 自适应, 网站改版, 元素找不到, DOM 变化, 选择器失效

### Playwright 触发词

**资源监控**：
- 资源, 截图, 网络请求, 接口, XHR, fetch, API 调用, 静态资源

## 调试模式

查看工具选择过程：

```bash
# 调度脚本会输出决策路径
node scripts/scrape.mjs <url> --intent "<描述>" 2>&1 | grep "🎯"
```

输出示例：
```
🎯 检测到 LLM/Markdown 意图 → Crawl4AI
```

## 手动覆盖

如果自动选择不符合预期，用 `--tool` 强制指定：

```bash
# 强制用 Scrapling
node scripts/scrape.mjs <url> --tool scrapling

# 强制用 Crawl4AI
node scripts/scrape.mjs <url> --tool crawl4ai

# 强制用 Playwright
node scripts/scrape.mjs <url> --tool playwright
```

## 性能特征

| 工具 | 冷启动 | 单页抓取 | 10 页爬取 | 反检测成功率 | 输出体积 |
|------|--------|----------|-----------|--------------|----------|
| Scrapling | ~0.5s | ~1-2s | ~15-30s | ⭐⭐⭐⭐⭐ (CF) | 小 |
| Crawl4AI | ~1s | ~2-4s | ~40-80s | ⭐⭐⭐⭐ | 小（MD 去噪） |
| Playwright | ~2s | ~3-5s | ~60-100s | ⭐⭐⭐ | 大（完整资源） |

- **Scrapling**：最快，Cloudflare 成功率最高
- **Crawl4AI**：输出质量最高（LLM 友好）
- **Playwright**：最全面但最慢

## 最佳实践

1. **首次抓取**：不指定 `--tool`，让引擎自动选择
2. **失败后重试**：查看 meta.json 中的 `reason`，手动指定更合适的工具
3. **批量任务**：优先用 Crawl4AI（深度爬取 + 崩溃恢复）
4. **定期抓取**：第一次用 Scrapling 训练，后续开启 `--adaptive`
5. **调试时**：用 `--tool` 强制指定，排除决策干扰

## 常见误判处理

### 误判 1：文档站被识别为普通页面

**原因**：URL 不包含 `/docs/` 等关键词

**解决**：
```bash
node scripts/scrape.mjs <url> --intent "文档站，需要批量爬取"
# 或
node scripts/scrape.mjs <url> --tool crawl4ai --deep
```

### 误判 2：简单页面被选了 Crawl4AI（太慢）

**原因**：URL 包含 `/blog/` 但实际是单篇文章

**解决**：
```bash
node scripts/scrape.mjs <url> --tool scrapling
```

### 误判 3：需要资源但选了 Scrapling

**原因**：意图描述不清晰

**解决**：
```bash
node scripts/scrape.mjs <url> --intent "需要下载所有 CSS/JS/图片"
# 或
node scripts/scrape.mjs <url> --tool playwright
```

## 扩展决策规则

如需添加新的场景识别规则，修改 `scripts/scrape.mjs` 的 `selectTool()` 函数：

```javascript
async function selectTool(url, intent, options) {
  // ... 现有逻辑 ...

  // 添加新规则
  if (/你的关键词/.test(intentLower)) {
    console.log('🎯 检测到自定义场景 → 工具名');
    return '工具名';
  }

  // ... 其余逻辑 ...
}
```

## 诊断工具

查看某个 URL 会选择哪个工具（dry-run 模式，TODO）：

```bash
node scripts/diagnose.mjs <url> --intent "<描述>"
```

输出示例：
```
URL: https://docs.python.org/3/library/
意图: "抓取文档"

决策路径:
  1. 强制指定: ✗
  2. 意图关键词: ✗
  3. URL 模式: ✓ (匹配 /docs/)
  4. Cloudflare 检测: ✗

选择: Crawl4AI
原因: 文档站 URL 模式

建议:
  - 可加 --deep --max-pages 50 批量爬取
  - 输出格式建议: --format markdown
```
