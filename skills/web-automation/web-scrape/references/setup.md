# 依赖与安装

## 前置依赖

### 必需
- **Node.js** ≥ 18（运行调度脚本）
- **Python** ≥ 3.8（Scrapling / Crawl4AI）
- **ego-lite / Playwright** 均为可选；有 ego-lite 就只用它做浏览器后端，没有 ego-lite 才需要 Playwright

### Python 依赖（自动检测并提示安装）
```bash
pip install scrapling crawl4ai playwright
playwright install chromium  # Crawl4AI 需要
```

脚本会自动检测依赖，缺失时给出安装命令。

## 依赖安装

脚本首次运行会检测依赖，缺失时输出：

```
[web-scrape] 缺少 Python 依赖，请运行：

  pip install scrapling crawl4ai playwright
  playwright install chromium

或使用 venv：

  python3 -m venv ~/.scrape-venv
  source ~/.scrape-venv/bin/activate
  pip install scrapling crawl4ai playwright
  playwright install chromium
```
