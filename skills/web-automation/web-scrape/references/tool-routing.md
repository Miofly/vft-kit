# 场景识别与工具选择

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
| 用户要"截图"/"已登录页面"/"人工接管"且 ego-lite 可用 | **ego-lite** | 复用登录态，不另起浏览器 |
| 用户要"资源"/"网络请求"/"XHR"/"接口" | **ego-lite**（无 ego-lite 时 **Playwright**） | ego-lite 写 network.json（Resource Timing 清单）；需要下载静态资源文件且无 ego-lite 时才用 Playwright |
| 无明确意图 | **Scrapling** → **ego-lite** → Crawl4AI | 先试快速抓取；有 ego-lite 时回退链跳过 Playwright，没有 ego-lite 时按 Scrapling → Playwright → Crawl4AI |

### 四种工具对比

| 特性 | Scrapling | Crawl4AI | ego-lite | Playwright |
|------|-----------|----------|----------|------------|
| **速度** | ⚡⚡⚡ 快 | ⚡⚡ 中等 | ⚡⚡ 快 | ⚡ 慢（需渲染） |
| **登录态** | ❌ | ❌ | ✅ 复用用户登录态 | ✅ 需 storageState |
| **深度爬取** | ✅ Spider 框架 | ✅ BFS/DFS + 崩溃恢复 | ❌ 单页 | ❌ 单页 |
| **输出格式** | HTML / 结构化 | **Markdown for LLM** | HTML + 截图 | HTML + 资源 |
| **资源下载/网络监控** | ❌ | ❌ | 网络请求清单（不下载资源） | ✅ |

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
  if (/资源|网络请求|接口|XHR/i.test(intent)) return hasEgo() ? 'ego' : 'playwright';
  if (/已登录|登录态|人工接管|截图/i.test(intent)) return 'ego';
  
  // 3. URL 模式
  if (/\/(docs?|wiki|blog|article|post)\//i.test(url)) return 'crawl4ai';
  
  // 4. 检测 Cloudflare（发 HEAD 请求看响应头）
  if (hasCloudflareProtection(url)) return 'scrapling';
  
  // 5. 默认策略：快速抓取 -> fallback
  return 'scrapling';  // 快速，失败后 fallback（有 ego-lite 时不走 playwright）
}
```

### Fallback 机制

```
Scrapling (快速)
  ↓ 失败（403/503/超时）
ego-lite (渲染，独立 task space)   ← 没有 ego-lite 时换成 Playwright
  ↓ 仍失败
Crawl4AI (重度反检测)
```

每个工具失败后自动尝试下一个，最终返回成功的结果或所有错误日志。
