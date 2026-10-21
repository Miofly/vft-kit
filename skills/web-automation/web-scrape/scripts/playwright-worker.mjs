#!/usr/bin/env node
// Playwright 全量网页抓取脚本。
// 抓取：渲染后 HTML + 所有静态资源(CSS/JS/图片/字体/媒体) + 网络请求清单 + 整页截图/PDF。
// 全局安装的 playwright 也能用：解析失败时自动回退到 `npm root -g`。
//
// 用法:
//   node playwright-worker.mjs <url> [options]
// 选项:
//   --out <dir>        输出目录（默认 ./scraped/<域名>-<时间戳>）
//   --browser <name>   chromium|firefox|webkit(默认 chromium)
//   --wait <ms>        load 之后额外等待(默认 1500)
//   --timeout <ms>     单页导航超时(默认 60000)
//   --no-assets        不落盘静态资源,只存 HTML+清单
//   --no-screenshot    不截图
//   --no-pdf           不导出 PDF(仅 chromium 支持 PDF)
//   --headed           显示浏览器窗口(默认无头)
//   --ua <string>      自定义 User-Agent
//   --storage-state <file>  复用 Playwright storageState 登录态

import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const require = createRequire(import.meta.url);

function defaultOutBase() {
  return 'scraped';
}

function loadPlaywright() {
  try {
    return require('playwright');
  } catch {
    const groot = execSync('npm root -g').toString().trim();
    return require(path.join(groot, 'playwright'));
  }
}

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) {
        args[key] = true;
      } else {
        args[key] = next;
        i++;
      }
    } else {
      args._.push(a);
    }
  }
  return args;
}

function pad(n) {
  return String(n).padStart(2, '0');
}

function timestamp() {
  const d = new Date();
  return (
    `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}` +
    `-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`
  );
}

// 把一个资源 URL 映射成本地相对路径,尽量还原站点目录结构。
function urlToLocalPath(rawUrl) {
  let u;
  try {
    u = new URL(rawUrl);
  } catch {
    return null;
  }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;

  let p = decodeURIComponent(u.pathname);
  if (p.endsWith('/') || p === '') p += 'index.html';
  // 带 query 的资源(如 a.js?v=2)追加哈希后缀避免覆盖
  if (u.search) {
    const ext = path.extname(p);
    const base = ext ? p.slice(0, -ext.length) : p;
    let h = 0;
    for (const ch of u.search) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
    p = `${base}__q${h.toString(16)}${ext}`;
  }
  // 去掉前导斜杠,按 host 分目录
  const safeHost = u.host.replace(/[:*?"<>|]/g, '_');
  const rel = path.join(safeHost, p.replace(/^\/+/, ''));
  // 防目录穿越
  return rel.split(path.sep).filter((seg) => seg !== '..').join(path.sep);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const url = args._[0];
  if (!url) {
    console.error('用法: node playwright-worker.mjs <url> [options]');
    process.exit(1);
  }

  const { chromium, firefox, webkit } = loadPlaywright();
  const engines = { chromium, firefox, webkit };
  const browserName = args.browser || 'chromium';
  const engine = engines[browserName];
  if (!engine) {
    console.error(`未知浏览器: ${browserName}(可选 chromium|firefox|webkit)`);
    process.exit(1);
  }

  const host = (() => {
    try {
      return new URL(url).host.replace(/[:*?"<>|]/g, '_');
    } catch {
      return 'site';
    }
  })();
  const outDir = path.resolve(
    args.out || path.join(defaultOutBase(), `${host}-${timestamp()}`),
  );
  const assetsRoot = path.join(outDir, 'assets');
  const saveAssets = !args['no-assets'];

  await mkdir(outDir, { recursive: true });

  console.log(`▶ 抓取 ${url}`);
  console.log(`  浏览器: ${browserName}  输出: ${outDir}`);

  const browser = await engine.launch({ headless: !args.headed });
  const contextOptions = args.ua ? { userAgent: String(args.ua) } : {};
  if (args['storage-state']) {
    const storageState = path.resolve(String(args['storage-state']));
    if (!existsSync(storageState)) throw new Error(`storageState 不存在: ${storageState}`);
    contextOptions.storageState = storageState;
  }
  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();

  const network = []; // 所有请求的清单
  const savedAssets = new Set();

  // 监听响应,落盘静态资源 + 记录网络
  page.on('response', async (response) => {
    const req = response.request();
    const resUrl = response.url();
    const entry = {
      url: resUrl,
      method: req.method(),
      status: response.status(),
      resourceType: req.resourceType(),
      contentType: response.headers()['content-type'] || '',
    };
    network.push(entry);

    if (!saveAssets) return;
    if (req.method() !== 'GET') return;
    if (resUrl.startsWith('data:') || resUrl.startsWith('blob:')) return;
    const rel = urlToLocalPath(resUrl);
    if (!rel || savedAssets.has(rel)) return;
    savedAssets.add(rel);
    try {
      const body = await response.body();
      const dest = path.join(assetsRoot, rel);
      await mkdir(path.dirname(dest), { recursive: true });
      await writeFile(dest, body);
      entry.savedAs = path.relative(outDir, dest);
    } catch {
      // 部分响应(重定向/204/已被消费)拿不到 body,跳过
    }
  });

  const timeout = Number(args.timeout || 60000);
  try {
    await page.goto(url, { waitUntil: 'networkidle', timeout });
  } catch (e) {
    console.warn(`  ⚠ networkidle 等待超时,回退到 load: ${e.message}`);
    await page.goto(url, { waitUntil: 'load', timeout }).catch(() => {});
  }

  const extraWait = Number(args.wait ?? 1500);
  if (extraWait > 0) await page.waitForTimeout(extraWait);

  // 渲染后 HTML
  const html = await page.content();
  await writeFile(path.join(outDir, 'index.html'), html, 'utf8');
  console.log(`  ✓ 已存渲染后 HTML (index.html)`);

  // 整页截图
  if (!args['no-screenshot']) {
    try {
      await page.screenshot({ path: path.join(outDir, 'screenshot.png'), fullPage: true });
      console.log(`  ✓ 已存整页截图 (screenshot.png)`);
    } catch (e) {
      console.warn(`  ⚠ 截图失败: ${e.message}`);
    }
  }

  // PDF(仅 chromium 无头支持)
  if (!args['no-pdf'] && browserName === 'chromium' && !args.headed) {
    try {
      await page.pdf({ path: path.join(outDir, 'page.pdf'), printBackground: true });
      console.log(`  ✓ 已存 PDF (page.pdf)`);
    } catch (e) {
      console.warn(`  ⚠ PDF 导出失败: ${e.message}`);
    }
  }

  // 网络清单
  await writeFile(
    path.join(outDir, 'network.json'),
    JSON.stringify({ url, capturedAt: new Date().toISOString(), count: network.length, requests: network }, null, 2),
    'utf8'
  );
  console.log(`  ✓ 已存网络清单 (network.json, ${network.length} 条)`);

  if (saveAssets) {
    console.log(`  ✓ 已存静态资源 ${savedAssets.size} 个 (assets/)`);
  }

  await browser.close();
  console.log(`✅ 完成 → ${outDir}`);
}

main().catch((e) => {
  console.error('抓取失败:', e);
  process.exit(1);
});
