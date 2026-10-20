# 故障排查

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

### Playwright 找不到浏览器（仅无 ego-lite 的环境）

```bash
playwright install chromium
```

脚本会自动回退到全局 npm 安装路径解析 Playwright。
