#!/usr/bin/env node
// CDN / 缓存 / 压缩 / SSR 冷启动 实测（node http/https 直连，绕开被 context-mode hook 拦的 curl）
// 用法：
//   node http-headers.mjs <baseURL> [--cold] [--q=?debug=true]
// 例：node http-headers.mjs https://example.com --cold --q='?debug=true'
//     node http-headers.mjs http://127.0.0.1:5173            ← 本地项目也能测（协议自动分流）
// 输出：HTML 入口 / sitemap / robots / 抽样静态资源 的缓存压缩头；--cold 时额外测回源 TTFB
import { request } from './_http.mjs';

const args = process.argv.slice(2);
const base = (args.find(a => a.startsWith('http')) || '').replace(/\/$/, '');
if (!base) { console.error('需要 baseURL，例：node http-headers.mjs https://site.com'); process.exit(1); }
const cold = args.includes('--cold');
const q = (args.find(a => a.startsWith('--q=')) || '--q=').slice(4); // 如 ?debug=true

const WANT = ['content-type','content-encoding','cache-control','cdn-cache-control','age','x-vercel-cache','cf-cache-status','vary','server','strict-transport-security'];
// 协议分流 / family:4 / brotli 解压这三个坑都在 _http.mjs 里处理，这里只挑关心的头。
async function get(url, timing = false) {
  const r = await request(url, { timing });
  if (r.err) return { url, err: r.err };
  const h = {};
  for (const k of WANT) if (r.headers[k]) h[k] = r.headers[k];
  return { url, status: r.status, h, body: r.body, ttfb: r.ttfb };
}
const short = u => u.replace(base, '').slice(0, 60);
const line = r => console.log((r.status||'ERR'), short(r.url), '\n  ', JSON.stringify(r.h || r.err || {}));

(async () => {
  console.log('=== HTML 入口 ===');
  const home = await get(base + '/' + q);
  line(home);
  const html = home.body || '';
  // 提取静态资源引用（HTML 已解压）
  const refs = [...new Set((html.match(/(?:https?:\/\/[^"' )>]+|\/[^"' )>]+)\.(?:js|css|woff2?|png|webp|avif)/g) || []))];
  const abs = r => r.startsWith('http') ? r : base + r;

  console.log('\n=== sitemap / robots ===');
  line(await get(base + '/sitemap.xml'));
  line(await get(base + '/robots.txt'));

  console.log('\n=== 抽样静态资源缓存/压缩头（期望 max-age=31536000, immutable + br）===');
  for (const r of refs.filter(x => /\.(js|css|woff2)$/.test(x)).slice(0, 6)) line(await get(abs(r)));

  if (cold) {
    console.log('\n=== SSR 冷启动回源 TTFB（随机 query 强制绕过 CDN 边缘缓存）===');
    for (let i = 0; i < 3; i++) {
      const r = await get(base + '/' + (q || '?') + (q ? '&' : '') + 'cb=' + Math.random(), true);
      console.log(`cold#${i} ${r.status||'ERR'} ${r.ttfb}ms vercel=${r.h?.['x-vercel-cache']||'?'} cf=${r.h?.['cf-cache-status']||'?'} bytes=${(r.body||'').length}`);
    }
    console.log('判读：cf/vercel=MISS 且 TTFB>3s → SSR 回源慢，发版后/边缘缓存过期时首批用户会等这么久。');
  }
})();
