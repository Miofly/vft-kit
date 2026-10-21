#!/usr/bin/env node
// 全站 SSR 状态清扫：拉 sitemap.xml 的【全部】URL，逐个 GET（不开浏览器，纯 node:https），
// 只看 HTTP 状态码 + SSR 500 的错误首行。用来抓「某些路由 SSR 直接 500」这类致命 bug——
// route-audit.mjs 是抽样（默认 20 条），会漏掉大多数坏路由；本脚本【全量】覆盖，专治「每个路由都要看」。
//
// 为什么单独一个脚本：SSR 500 是【服务端模块实例化/渲染就崩】，返回的是错误栈 HTML、没有 #app，
// 浏览器硬导航/爬虫拿到的是白屏。这类问题不需要渲染，一个 GET 就能判定，比 Playwright 快几十倍，
// 所以可以对几百条路由全量跑。典型根因：CJS 包（gifenc/wasm-webp 等）被【静态 import】进路由 chunk，
// Node ESM 实例化时 "does not provide an export named X" → 整条路由 500（<client-only> 挡不住，
// 因为崩在模块实例化、早于渲染）。修复=改成组件内 `await import()` 懒加载。
//
// 用法：node ssr-status-sweep.mjs <baseURL> [--q='?debug=true'] [--concurrency=8]
// 例：node ssr-status-sweep.mjs https://example.com --q='?debug=true'
import { request } from './_http.mjs';

const args = process.argv.slice(2);
const base = (args.find(a => a.startsWith('http')) || '').replace(/\/$/, '');
if (!base) { console.error('需要 baseURL'); process.exit(1); }
const q = (args.find(a => a.startsWith('--q=')) || '--q=').slice(4);
const CONC = parseInt((args.find(a => a.startsWith('--concurrency=')) || '').split('=')[1] || '8', 10);

// 协议按**每个 URL** 判（sitemap 里常是绝对 https URL，而 base 可能是 http://127.0.0.1，
// 按 base 全局推协议会连错）——_http.mjs 里按 url.protocol 分流。
async function get(url) {
  const r = await request(url, { timeout: 30000, headers: { 'User-Agent': 'Mozilla/5.0 (SSR-sweep)' } });
  if (r.err) return { status: r.err === 'timeout' ? -1 : 0, body: '' };
  return { status: r.status || 0, body: r.body || '' };
}

// 从 SSR 500 的错误栈里抽最有用的一行（模块导出缺失 / ReferenceError / 崩溃文件名）
function errHint(body) {
  const m =
    body.match(/does not provide an export named ['"][^'"]+['"]/) ||
    body.match(/\b(\w+Error): [^\n]{0,120}/) ||
    body.match(/Cannot find module [^\n]{0,80}/) ||
    body.match(/is not defined/);
  return m ? m[0] : '';
}
const short = u => u.replace(base, '').replace(q, '') || '/';

(async () => {
  const sm = await get(base + '/sitemap.xml');
  const urls = [...sm.body.matchAll(/<loc>([^<]+)<\/loc>/g)].map(x => x[1].replace(/&amp;/g, '&'));
  console.log(`SITEMAP ${base} = ${urls.length} urls；全量 SSR 状态清扫（并发 ${CONC}）\n`);
  const bad = [];
  let done = 0;
  let idx = 0;
  const worker = async () => {
    while (idx < urls.length) {
      const u = urls[idx++];
      const target = u + q;
      const { status, body } = await get(target);
      done++;
      if (status !== 200) {
        const hint = status >= 500 ? errHint(body) : '';
        bad.push({ path: short(u), status, hint });
        console.log(`🔴 ${status} ${short(u)}${hint ? '  « ' + hint : ''}`);
      }
      if (done % 50 === 0) console.error(`  …${done}/${urls.length}`);
    }
  };
  await Promise.all(Array.from({ length: Math.min(CONC, urls.length) }, worker));

  console.log(`\n=== 汇总 ===`);
  console.log(`总路由 ${urls.length}，非 200：${bad.length}`);
  if (bad.length) {
    // 按错误提示归类，便于「一类根因一次修完」
    const byHint = {};
    bad.forEach(b => { const k = b.hint || `HTTP ${b.status}`; (byHint[k] ||= []).push(b.path); });
    Object.entries(byHint).sort((a, b) => b[1].length - a[1].length).forEach(([k, ps]) => {
      console.log(`\n【${k}】× ${ps.length}`);
      ps.forEach(p => console.log('   ', p));
    });
  } else {
    console.log('✅ 全站 SSR 全部 200，无致命路由');
  }
})();
