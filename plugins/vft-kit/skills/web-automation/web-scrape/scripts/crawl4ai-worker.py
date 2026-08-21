#!/usr/bin/env python3
"""
Crawl4AI Worker - LLM-ready Markdown 抓取
支持深度爬取、fit_markdown 去噪、BM25 过滤
"""

import json
import sys
import os
import asyncio
from pathlib import Path
from datetime import datetime

def main():
    if len(sys.argv) < 2:
        print("用法: crawl4ai-worker.py <config.json>", file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
    except Exception as e:
        print(f"❌ 读取配置失败: {e}", file=sys.stderr)
        sys.exit(1)

    # 运行异步主函数
    asyncio.run(async_main(config))

async def async_main(config):
    # 导入 Crawl4AI
    try:
        from crawl4ai import AsyncWebCrawler
        from crawl4ai.extraction_strategy import LLMExtractionStrategy
        from crawl4ai.chunking_strategy import RegexChunking
    except ImportError as e:
        print(f"❌ 导入 Crawl4AI 失败: {e}", file=sys.stderr)
        print("\n请安装: pip install crawl4ai playwright", file=sys.stderr)
        print("然后运行: playwright install chromium", file=sys.stderr)
        sys.exit(1)

    url = config['url']
    out_dir = Path(config['outDir'])
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"🕷️  Crawl4AI 抓取中...")
    print(f"URL: {url}")
    print(f"深度爬取: {config.get('deep', False)}")
    print(f"隐蔽模式: {config.get('stealth', True)}")
    print()

    try:
        # 配置爬虫
        crawler_config = {
            'headless': config.get('headless', True),
            'verbose': True,
        }

        async with AsyncWebCrawler(**crawler_config) as crawler:
            # 单页抓取
            if not config.get('deep', False):
                print("📄 单页抓取模式")

                result = await crawler.arun(
                    url=url,
                    word_count_threshold=10,  # 去噪阈值
                    bypass_cache=True,
                    wait_for='networkidle' if config.get('wait', 0) > 0 else None,
                )

                if not result.success:
                    print(f"❌ 抓取失败: {result.error_message}", file=sys.stderr)
                    sys.exit(1)

                # 保存 Markdown
                md_path = out_dir / 'content.md'
                with open(md_path, 'w', encoding='utf-8') as f:
                    # fit_markdown 是 Crawl4AI 的核心特性
                    f.write(f"# {result.title or 'Untitled'}\n\n")
                    f.write(f"URL: {url}\n\n")
                    f.write(result.markdown)  # 已经去噪、BM25 过滤
                print(f"✅ Markdown 已保存: {md_path} ({len(result.markdown)} 字节)")

                # 保存原始 HTML
                html_path = out_dir / 'content.html'
                with open(html_path, 'w', encoding='utf-8') as f:
                    f.write(result.html)
                print(f"✅ HTML 已保存: {html_path}")

                # 保存截图（如果启用）
                if config.get('screenshot', True) and result.screenshot:
                    screenshot_path = out_dir / 'screenshot.png'
                    with open(screenshot_path, 'wb') as f:
                        f.write(result.screenshot)
                    print(f"✅ 截图已保存: {screenshot_path}")

                # 保存链接列表
                if result.links:
                    links_path = out_dir / 'links.json'
                    with open(links_path, 'w', encoding='utf-8') as f:
                        json.dump({
                            'internal': result.links.get('internal', []),
                            'external': result.links.get('external', []),
                        }, f, indent=2, ensure_ascii=False)
                    print(f"✅ 链接列表已保存: {links_path}")

            # 深度爬取
            else:
                max_pages = config.get('maxPages', 10)
                strategy = config.get('strategy', 'bfs')
                print(f"🌲 深度爬取模式 (策略: {strategy}, 最多 {max_pages} 页)")

                deep_dir = out_dir / 'deep-crawl'
                deep_dir.mkdir(parents=True, exist_ok=True)

                crawled = []
                to_crawl = [url]
                visited = set()

                page_count = 0

                while to_crawl and page_count < max_pages:
                    current_url = to_crawl.pop(0 if strategy == 'bfs' else -1)

                    if current_url in visited:
                        continue

                    visited.add(current_url)
                    page_count += 1

                    print(f"  [{page_count}/{max_pages}] {current_url}")

                    try:
                        result = await crawler.arun(
                            url=current_url,
                            word_count_threshold=10,
                            bypass_cache=True,
                        )

                        if not result.success:
                            print(f"    ⚠️  失败: {result.error_message}")
                            continue

                        # 保存页面
                        page_file = deep_dir / f'page-{page_count:03d}.md'
                        with open(page_file, 'w', encoding='utf-8') as f:
                            f.write(f"# {result.title or 'Untitled'}\n\n")
                            f.write(f"URL: {current_url}\n\n")
                            f.write(result.markdown)

                        crawled.append({
                            'page': page_count,
                            'url': current_url,
                            'title': result.title,
                            'file': str(page_file.name),
                            'size': len(result.markdown),
                        })

                        # 提取新链接
                        if result.links and result.links.get('internal'):
                            # 只爬取同域名的内部链接
                            for link in result.links['internal'][:20]:
                                if link not in visited and link not in to_crawl:
                                    to_crawl.append(link)

                    except Exception as e:
                        print(f"    ⚠️  异常: {e}")
                        continue

                # 保存索引
                index_path = deep_dir / 'index.json'
                with open(index_path, 'w', encoding='utf-8') as f:
                    json.dump(crawled, f, indent=2, ensure_ascii=False)

                print(f"\n✅ 深度爬取完成，共 {len(crawled)} 页")
                print(f"索引: {index_path}")

    except Exception as e:
        print(f"\n❌ Crawl4AI 执行失败: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

    print("\n✅ Crawl4AI 抓取完成")
    sys.exit(0)

if __name__ == '__main__':
    main()
