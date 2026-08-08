#!/usr/bin/env python3
"""
Scrapling Worker - 自适应网页抓取
支持自适应解析、隐蔽模式、深度爬取
"""

import json
import sys
import os
from pathlib import Path
from datetime import datetime

def main():
    if len(sys.argv) < 2:
        print("用法: scrapling-worker.py <config.json>", file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
    except Exception as e:
        print(f"❌ 读取配置失败: {e}", file=sys.stderr)
        sys.exit(1)

    # 导入 Scrapling
    try:
        from scrapling.fetchers import StealthyFetcher, Fetcher
        from scrapling.spiders import Spider, Response
    except ImportError as e:
        print(f"❌ 导入 Scrapling 失败: {e}", file=sys.stderr)
        print("\n请安装: pip install scrapling", file=sys.stderr)
        sys.exit(1)

    url = config['url']
    out_dir = Path(config['outDir'])
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"🕷️  Scrapling 抓取中...")
    print(f"URL: {url}")
    print(f"自适应: {config.get('adaptive', False)}")
    print(f"隐蔽模式: {config.get('stealth', True)}")
    print()

    try:
        # 选择 Fetcher
        if config.get('stealth', True):
            fetcher_class = StealthyFetcher
            StealthyFetcher.adaptive = config.get('adaptive', False)
        else:
            fetcher_class = Fetcher
            Fetcher.adaptive = config.get('adaptive', False)

        # 单页抓取
        if not config.get('deep', False):
            print("📄 单页抓取模式")

            page = fetcher_class.fetch(
                url,
                headless=config.get('headless', True),
                network_idle=True,
            )

            # 保存 HTML
            html_path = out_dir / 'content.html'
            with open(html_path, 'w', encoding='utf-8') as f:
                f.write(page.html)
            print(f"✅ HTML 已保存: {html_path}")

            # 自适应模式：保存选择器训练数据
            if config.get('adaptive', False):
                # Scrapling 会自动保存训练数据到内部缓存
                print("✅ 自适应训练数据已保存")

            # 如果需要 Markdown 格式
            if config.get('format') == 'markdown':
                # Scrapling 没有内置 Markdown 转换，用简单的文本提取
                text = page.text
                md_path = out_dir / 'content.md'
                with open(md_path, 'w', encoding='utf-8') as f:
                    f.write(f"# {page.title}\n\n")
                    f.write(f"URL: {url}\n\n")
                    f.write(text)
                print(f"✅ Markdown 已保存: {md_path}")

        # 深度爬取
        else:
            print(f"🌲 深度爬取模式 (最多 {config.get('maxPages', 10)} 页)")

            # 定义 Spider
            class SmartSpider(Spider):
                name = "smart-scrape"
                start_urls = [url]
                max_pages = config.get('maxPages', 10)
                page_count = 0

                async def parse(self, response: Response):
                    self.page_count += 1

                    # 保存当前页
                    page_file = out_dir / 'deep-crawl' / f'page-{self.page_count:03d}.html'
                    page_file.parent.mkdir(parents=True, exist_ok=True)

                    with open(page_file, 'w', encoding='utf-8') as f:
                        f.write(response.html)

                    print(f"  [{self.page_count}/{self.max_pages}] {response.url}")

                    yield {
                        'url': response.url,
                        'title': response.css('title::text').get(''),
                        'page': self.page_count,
                    }

                    # 继续爬取链接
                    if self.page_count < self.max_pages:
                        for link in response.css('a::attr(href)').getall()[:20]:
                            if link and link.startswith(('http://', 'https://')):
                                yield response.follow(link, self.parse)

            # 运行 Spider
            spider = SmartSpider()
            results = []

            # Scrapling Spider 的运行方式
            for item in spider.start():
                if isinstance(item, dict):
                    results.append(item)

            # 保存索引
            index_path = out_dir / 'deep-crawl' / 'index.json'
            with open(index_path, 'w', encoding='utf-8') as f:
                json.dump(results, f, indent=2, ensure_ascii=False)

            print(f"\n✅ 深度爬取完成，共 {len(results)} 页")
            print(f"索引: {index_path}")

    except Exception as e:
        print(f"\n❌ Scrapling 执行失败: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

    print("\n✅ Scrapling 抓取完成")
    sys.exit(0)

if __name__ == '__main__':
    main()
