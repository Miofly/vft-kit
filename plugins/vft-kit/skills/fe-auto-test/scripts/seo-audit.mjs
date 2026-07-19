#!/usr/bin/env node
// SEO 深度体检 —— 抓【原始 SSR HTML】（不跑 JS，纯 node HTTP，就是爬虫视角），全站/抽样解析。
// 补 Lighthouse SEO 分查不到的深层问题：
//   · SSR 空壳：状态 200 但 #app 没内容 → 爬虫拿到白屏 → 掉收录（ssr-status-sweep 只抓 500，抓不到这个）
//   · 跨路由 title / description 重复 → 搜索引擎判重、稀释权重（route-audit 只查「有没有」，不查「重不重」）
//   · canonical 缺失 / 不自指（SPA 常见 bug：所有页 canonical 全指首页）→ 内容页不被索引
//   · 结构化数据（JSON-LD）、og 社交卡片、h1、noindex 误标
//
// 为什么单独抓原始 HTML：SEO 看的是【服务端返回的首帧】，不是 JS 渲染后的 DOM。SSR 若没生效，
// 浏览器里（route-audit 那种跑完 JS 的）看着好好的，爬虫却只拿到空壳。只有直接 GET 才暴露这个。
//
// 用法：node seo-audit.mjs <baseURL> [sampleCount=40] [--all] [--q='?debug=true'] [--concurrency=8]
//   默认抽样 40 条看趋势；--all 全量（唯一性判定更准，但慢）。
import { request, sitemapUrls } from './_http.mjs';

const args = process.argv.slice(2);
const base = (args.find((a) => a.startsWith('http')) || '').replace(/\/$/, '');
if (!base) { console.error('需要 baseURL'); process.exit(1); }
const N = parseInt(args.find((a) => /^\d+$/.test(a)) || '40', 10);
const ALL = args.includes('--all');
const q = (args.find((a) => a.startsWith('--q=')) || '--q=').slice(4);
const CONC = parseInt((args.find((a) => a.startsWith('--concurrency=')) || '').split('=')[1] || '8', 10);
const EMPTY_LEN = 200; // 去标签后可见文本 < 此长度视为 SSR 空壳

function sample(a, n) { if (a.length <= n) return a; const s = a.length / n, o = []; for (let i = 0; i < n; i++) o.push(a[Math.floor(i * s)]); return o; }
const attr = (h, re) => { const m = h.match(re); return m ? m[1].trim() : null; };
const strip = (h) => h.replace(/<script[\s\S]*?<\/script>/gi, '').replace(/<style[\s\S]*?<\/style>/gi, '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
const norm = (u) => (u || '').replace(/^https?:\/\//, '').replace(/[?#].*$/, '').replace(/\/$/, '').toLowerCase();
const short = (u) => u.replace(base, '').replace(q, '') || '/';

function parse(url, html) {
  return {
    path: short(url),
    title: attr(html, /<title[^>]*>([^<]*)<\/title>/i),
    desc: attr(html, /<meta[^>]+name=["']description["'][^>]+content=["']([^"']*)["']/i)
       || attr(html, /<meta[^>]+content=["']([^"']*)["'][^>]+name=["']description["']/i),
    canonical: attr(html, /<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']*)["']/i)
       || attr(html, /<link[^>]+href=["']([^"']*)["'][^>]+rel=["']canonical["']/i),
    ogTitle: /<meta[^>]+property=["']og:title["']/i.test(html),
    ogImage: /<meta[^>]+property=["']og:image["']/i.test(html),
    h1: (html.match(/<h1[\s>]/gi) || []).length,
    noindex: /<meta[^>]+name=["']robots["'][^>]+content=["'][^"']*noindex/i.test(html),
    textLen: strip(html).length,
    ...imgAndJsonld(html),
  };
}

// 图片 alt 覆盖率 + JSON-LD 合法性（原始 HTML 已在手，顺手解析，零额外请求）。
// JSON-LD 分三态：空标签（SSR 没注入内容、只客户端填充 → 爬虫拿到空的、SEO 无效）/ parse 失败（写错）/ 有效。
// 空标签是 SSR 站高频坑：肉眼在浏览器里看着有结构化数据，爬虫拿到的首帧却是空的。
function imgAndJsonld(html) {
  const imgs = html.match(/<img\b[^>]*>/gi) || [];
  const imgNoAlt = imgs.filter((t) => !/\balt\s*=/i.test(t)).length;
  const decode = (s) => s.replace(/&quot;/g, '"').replace(/&#(\d+);/g, (_, n) => String.fromCharCode(+n)).replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  let jsonldEmpty = 0, jsonldBad = 0; const types = new Set();
  for (const m of html.matchAll(/<script[^>]+application\/ld\+json[^>]*>([\s\S]*?)<\/script>/gi)) {
    const c = m[1].trim();
    if (!c) { jsonldEmpty++; continue; }
    try { const j = JSON.parse(decode(c)); (Array.isArray(j) ? j : [j]).forEach((x) => x && x['@type'] && types.add(x['@type'])); }
    catch { jsonldBad++; }
  }
  return { imgTotal: imgs.length, imgNoAlt, jsonld: types.size > 0, jsonldEmpty, jsonldBad, jsonldTypes: [...types] };
}

(async () => {
  let urls = await sitemapUrls(base);
  if (!urls.length) { console.log('拿不到 sitemap.xml，只测首页（本地 dev 常无 sitemap，覆盖多路由请打线上域名）'); urls = [base + '/']; }
  const picks = ALL ? urls : [base + '/', ...sample(urls.filter((u) => u.replace(/\/$/, '') !== base), N)];
  console.log(`SITEMAP ${base} = ${urls.length} urls；SEO 体检 ${picks.length} 条${ALL ? '（全量）' : `（抽样，--all 跑全量）`}\n`);

  const rows = [];
  let idx = 0, done = 0;
  const worker = async () => {
    while (idx < picks.length) {
      const u = picks[idx++];
      const r = await request(u + q, { timeout: 30000, headers: { 'User-Agent': 'Mozilla/5.0 (compatible; Googlebot/2.1)' } });
      done++;
      if (r.err || r.status !== 200) { rows.push({ path: short(u), err: r.err || `HTTP ${r.status}` }); }
      else rows.push(parse(u, r.body || ''));
      if (done % 25 === 0) console.error(`  …${done}/${picks.length}`);
    }
  };
  await Promise.all(Array.from({ length: Math.min(CONC, picks.length) }, worker));

  const ok = rows.filter((r) => !r.err);
  const dup = (key) => {
    const m = {};
    ok.forEach((r) => { const v = r[key]; if (v) (m[v] ||= []).push(r.path); });
    return Object.entries(m).filter(([, ps]) => ps.length > 1).sort((a, b) => b[1].length - a[1].length);
  };
  const list = (pred) => ok.filter(pred).map((r) => r.path);
  const show = (arr, n = 12) => arr.slice(0, n).join('  ') + (arr.length > n ? ` …+${arr.length - n}` : '');

  const shells = ok.filter((r) => r.textLen < EMPTY_LEN);
  const dupTitle = dup('title');
  const dupDesc = dup('desc');
  const nonSelfCanon = ok.filter((r) => r.canonical && norm(r.canonical) !== norm(base + r.path));

  console.log('=== SEO 体检汇总 ===');
  console.log(`探测 ${rows.length}，成功 ${ok.length}，失败 ${rows.length - ok.length}`);

  console.log(`\n🔴 SSR 空壳（爬虫拿到白屏，直接掉收录）: ${shells.length}`);
  if (shells.length) console.log('   ', show(shells.map((r) => `${r.path}(${r.textLen}字)`)));

  console.log(`\n🔴 重复 title（搜索引擎判重）: ${dupTitle.length} 组`);
  dupTitle.slice(0, 6).forEach(([t, ps]) => console.log(`    ×${ps.length} "${t.slice(0, 40)}" → ${show(ps, 6)}`));

  console.log(`\n🟡 重复 description: ${dupDesc.length} 组`);
  dupDesc.slice(0, 6).forEach(([d, ps]) => console.log(`    ×${ps.length} "${d.slice(0, 40)}" → ${show(ps, 6)}`));

  const noTitle = list((r) => !r.title), noDesc = list((r) => !r.desc), noCanon = list((r) => !r.canonical);
  const noH1 = list((r) => !r.h1), multiH1 = list((r) => r.h1 > 1), noJsonld = list((r) => !r.jsonld);
  const noOg = list((r) => !r.ogTitle || !r.ogImage), noindexed = list((r) => r.noindex);

  console.log(`\n缺 title: ${noTitle.length}${noTitle.length ? '  ' + show(noTitle) : ''}`);
  console.log(`缺 description: ${noDesc.length}${noDesc.length ? '  ' + show(noDesc) : ''}`);
  console.log(`缺 canonical: ${noCanon.length}${noCanon.length ? '  ' + show(noCanon) : ''}`);
  console.log(`canonical 不自指（指向别处，常见 SPA bug 全指首页）: ${nonSelfCanon.length}${nonSelfCanon.length ? '  ' + show(nonSelfCanon.map((r) => `${r.path}→${norm(r.canonical)}`)) : ''}`);
  console.log(`缺 h1: ${noH1.length}${noH1.length ? '  ' + show(noH1) : ''}   多 h1: ${multiH1.length}${multiH1.length ? '  ' + show(multiH1) : ''}`);
  console.log(`无有效 JSON-LD 结构化数据: ${noJsonld.length}/${ok.length}${noJsonld.length === ok.length ? ' （全站都没有有效数据，加 Article/WebSite/BreadcrumbList schema 可拿富摘要）' : ''}`);
  console.log(`og 社交卡片不全: ${noOg.length}${noOg.length ? '  ' + show(noOg) : ''}`);
  const imgNoAlt = ok.reduce((s, r) => s + (r.imgNoAlt || 0), 0), imgTotal = ok.reduce((s, r) => s + (r.imgTotal || 0), 0);
  const jsonldBad = ok.reduce((s, r) => s + (r.jsonldBad || 0), 0), jsonldEmpty = ok.reduce((s, r) => s + (r.jsonldEmpty || 0), 0);
  const allTypes = [...new Set(ok.flatMap((r) => r.jsonldTypes || []))];
  console.log(`图片缺 alt: ${imgNoAlt}/${imgTotal}${imgNoAlt ? '（SEO+无障碍双失分，给每张 <img> 补 alt）' : ''}`);
  console.log(`JSON-LD: 有效类型=[${allTypes.join(', ') || '无'}]  空标签 ${jsonldEmpty}  parse失败 ${jsonldBad}`);
  if (jsonldEmpty) console.log('   🔴 有 <script type=ld+json> 但内容为空 —— SSR 没注入、只客户端填充，爬虫拿到空的，结构化数据对 SEO 无效（应在 SSR 阶段就注入 JSON-LD）');
  if (noindexed.length) console.log(`\n⚠ 被 noindex 屏蔽的路由（确认是否误标）: ${noindexed.length}  ${show(noindexed)}`);

  if (!shells.length && !dupTitle.length && !noTitle.length && !noCanon.length && !nonSelfCanon.length)
    console.log('\n✅ SSR 首帧、title 唯一性、canonical 自指 — 核心 SEO 项无硬伤');
})();
