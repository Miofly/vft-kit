# 安全、代理、许可证与相关文档

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

## 许可证

- **Scrapling**: Apache-2.0（需在使用处署名）
- **Crawl4AI**: Apache-2.0（需在使用处署名）
- **Playwright**: Apache-2.0

本 skill 作为 vft-kit 的一部分遵循 vft-kit 的许可证。使用时需遵守上游工具的 attribution 要求。

## 相关文档

- [Scrapling 官方文档](https://scrapling.readthedocs.io)
- [Crawl4AI 官方文档](https://crawl4ai.com)
- [场景选择算法详解](../docs/tool-selection.md)
- MCP 集成指南：`docs/mcp-integration.md`（TODO，尚未编写）
