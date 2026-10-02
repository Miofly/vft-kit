#!/usr/bin/env node
// 逐路由批量审计：从 sitemap.xml 抽样 → Playwright 逐个打开 → 收集渲染/console 错误/SEO meta。
// 用法：node route-audit.mjs <baseURL> [sampleCount=15] [--q=?debug=true]
// 例：node route-audit.mjs https://example.com 15 --q='?debug=true'
import { sitemapUrls } from './_http.mjs';
import { chromium } from './_pw.mjs';

const args = process.argv.slice(2);
const base = (args.find(a => a.startsWith('http')) || '').replace(/\/$/, '');
if (!base) { console.error('需要 baseURL'); process.exit(1); }
const N = parseInt(args.find(a => /^\d+$/.test(a)) || '15', 10);
const q = (args.find(a => a.startsWith('--q=')) || '--q=').slice(4);

function sample(a, n){ if (a.length <= n) return a; const s = a.length/n, o = []; for (let i=0;i<n;i++) o.push(a[Math.floor(i*s)]); return o; }

// 良性噪声：广告/统计/浏览器无害告警。真 bug 的标准是栈指向业务代码或伴随渲染缺失。
const IGNORE = [/play\(\) request was interrupted/i, /ResizeObserver loop/i, /pagead|googlesyndication|adsbygoogle|doubleclick|google-analytics|googletagmanager|google\.com\/ads/i];
const benign = m => IGNORE.some(re => re.test(m));

async function testRoute(ctx, url){
  const page = await ctx.newPage();
  const errors = [], pageErrors = [], failed = [];
  page.on('console', m => { if (m.type()==='error') errors.push(m.text()); });
  page.on('pageerror', e => pageErrors.push(String(e).slice(0,180)));
  page.on('requestfailed', r => { const u = r.url(); if (!benign(u)) failed.push(short(u) + ' [' + (r.failure()?.errorText||'') + ']'); });
  const t0 = Date.now();
  // 广告站 domcontentloaded 也可能被拖住 → 用 commit + catch 容错
  try { await page.goto(url, { waitUntil:'commit', timeout:30000 }); } catch(e){ pageErrors.push('GOTO:'+e.message.slice(0,80)); }
  try { await page.waitForLoadState('domcontentloaded', { timeout:12000 }); } catch(e){}
  const info = await page.evaluate(() => {
    const app = document.querySelector('#app');
    return { title: document.title,
      desc: document.querySelector('meta[name=description]')?.getAttribute('content') || null,
      canonical: !!document.querySelector('link[rel=canonical]'),
      og: !!document.querySelector('meta[property="og:title"]'),
      appChildren: app ? app.children.length : -1,
      bodyLen: (document.body?.innerText||'').trim().length };
  }).catch(() => ({}));
  const realErr = [...new Set(errors.filter(e => !benign(e)))];
  await page.close();
  return { url, ...info, loadMs: Date.now()-t0, realErr: realErr.slice(0,3), pageErrors: pageErrors.slice(0,3), failed: failed.slice(0,3) };
}
const short = u => u.replace(base,'').replace(q,'').replace('https://','');

(async () => {
  const urls = await sitemapUrls(base);
  console.log(`SITEMAP ${base} = ${urls.length} urls；抽样 ${N} 条`);
  if (!urls.length) console.log('（拿不到 sitemap.xml —— 本地 dev server 通常没有。只测首页；要覆盖多路由请改用线上域名，或手动传路由列表。）');
  const browser = await chromium.launch({ headless:true });
  const ctx = await browser.newContext({ viewport:{width:390,height:844}, userAgent:'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 Mobile' });
  const picks = [base + '/' + q, ...sample(urls.filter(u => u.replace(/\/$/,'') !== base), N).map(u => u + q)];
  const results = [];
  for (const u of picks) {
    const r = await testRoute(ctx, u);
    const flag = r.appChildren <= 0 ? '⚠️EMPTY' : r.realErr.length ? '🔶ERR'+r.realErr.length : r.pageErrors.length ? '🔴PE' : '✅';
    console.log(`${flag} ${r.loadMs}ms ch=${r.appChildren} body=${r.bodyLen} | ${short(r.url)}`);
    console.log(`    title="${(r.title||'').slice(0,45)}" desc=${r.desc?'Y':'✗'} canon=${r.canonical?'Y':'✗'} og=${r.og?'Y':'✗'}`);
    if (r.realErr.length) console.log('    ERR:', JSON.stringify(r.realErr));
    if (r.pageErrors.length) console.log('    PAGEERR:', JSON.stringify(r.pageErrors));
    results.push(r);
  }
  const dedup = {}; results.forEach(r => r.realErr.forEach(e => { const k = e.slice(0,60); dedup[k] = (dedup[k]||0)+1; }));
  console.log('\n=== 去重业务 console 错误（已排除广告/统计噪声）===');
  const keys = Object.entries(dedup).sort((a,b) => b[1]-a[1]);
  keys.length ? keys.forEach(([k,c]) => console.log(c+'x', k)) : console.log('（无，业务代码零报错）');
  const noDesc = results.filter(r => !r.desc);
  console.log('\n缺 description 的路由:', noDesc.length, noDesc.map(r => short(r.url)).slice(0,10));
  await browser.close();
})();
