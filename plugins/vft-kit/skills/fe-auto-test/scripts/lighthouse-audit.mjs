#!/usr/bin/env node
// 全维度 Lighthouse 体检 —— 直接调 lighthouse 库，不走 MCP，装完立即可用、无需重启会话。
//
// 一次跑完，等价于原来串行调的 7 个 MCP 工具：
//   核心指标(FCP/LCP/CLS/TBT/SI/TTI) + 性能综合分 + 未用 JS + 未用 CSS
//   + 无障碍/最佳实践/SEO 三维评分 + 无障碍 score:0 失败项明细 + 资源清单
//
// 用法:
//   node lighthouse-audit.mjs <url> [--device=mobile|desktop] [--q='?debug=true']
//                                   [--resources=<落盘路径>] [--json]
//
// 坑位（都已在脚本里处理，调用方不用操心）:
//   · 本地 URL 一律改写成 127.0.0.1（headless Chrome 对 localhost 偶有解析问题）
//   · 输出主动裁剪（只留 top N 条），不像 MCP 的 analyze_resources 那样撑爆 token
//   · NO_FCP 会明确提示 anti-debug 陷阱 + 给出 --q 后门绕过建议，而不是干巴巴报全 N/A
import { writeFileSync } from 'node:fs';
import { lighthouse, launch } from './_lh.mjs';

const argv = process.argv.slice(2);
const rawUrl = argv.find((a) => !a.startsWith('--'));
if (!rawUrl) {
  console.error("用法: node lighthouse-audit.mjs <url> [--device=mobile|desktop] [--q='?debug=true'] [--resources=<path>] [--json]");
  process.exit(1);
}
const flag = (n, d = '') => {
  const hit = argv.find((a) => a.startsWith(`--${n}=`));
  return hit ? hit.slice(n.length + 3).replace(/^['"]|['"]$/g, '') : d;
};
const DEVICE = flag('device', 'mobile');
const QUERY = flag('q');
const RES_OUT = flag('resources');
const AS_JSON = argv.includes('--json');

// localhost → 127.0.0.1（headless Chrome 解析坑）；再拼上 debug 后门参数
let url = rawUrl.replace(/^(https?:\/\/)localhost(?=[:/]|$)/, '$1127.0.0.1');
if (QUERY) url += QUERY.startsWith('?') || QUERY.startsWith('&')
  ? (url.includes('?') ? QUERY.replace(/^\?/, '&') : QUERY)
  : (url.includes('?') ? `&${QUERY}` : `?${QUERY}`);

const DESKTOP = {
  formFactor: 'desktop',
  screenEmulation: { mobile: false, width: 1350, height: 940, deviceScaleFactor: 1, disabled: false },
  throttling: { rttMs: 40, throughputKbps: 10240, cpuSlowdownMultiplier: 1 },
};
const MOBILE = {
  formFactor: 'mobile',
  screenEmulation: { mobile: true, width: 412, height: 823, deviceScaleFactor: 1.75, disabled: false },
};

const chrome = await launch({ chromeFlags: ['--headless=new', '--no-sandbox'] });
let lhr;
try {
  const run = await lighthouse(url, {
    port: chrome.port,
    output: 'json',
    logLevel: 'error',
    onlyCategories: ['performance', 'accessibility', 'best-practices', 'seo'],
    ...(DEVICE === 'desktop' ? DESKTOP : MOBILE),
  });
  lhr = run.lhr;
} finally {
  await chrome.kill();
}

// —— 全 N/A 陷阱：页面有 anti-debug 的 debugger 陷阱时，Lighthouse 的 Debugger 域被拦，指标全废 ——
if (lhr.runtimeError?.code) {
  const isNoFcp = lhr.runtimeError.code === 'NO_FCP';
  console.error(`✗ Lighthouse 跑不出指标：${lhr.runtimeError.code} — ${lhr.runtimeError.message}`);
  if (isNoFcp) {
    console.error(
      '\n多半是页面里的 anti-debug `debugger` 陷阱拦了 Lighthouse 的 Debugger 域。\n' +
      "  · 先对照测一发 https://example.com，它正常就说明是目标站的陷阱；\n" +
      "  · 找该站自己的 debug 后门参数（常见 ?debug=true），重跑时加 --q='?debug=true'；\n" +
      '  · 实在没后门，改用 Playwright 读 performance API 降级测量（见 SKILL.md 降级方案）——\n' +
      '    Playwright 不开 Debugger 域，陷阱对它是空操作。'
    );
  }
  process.exit(2);
}

const A = lhr.audits;
const num = (id) => A[id]?.numericValue ?? null;
const score = (c) => (lhr.categories[c]?.score == null ? null : Math.round(lhr.categories[c].score * 100));
const ms = (v) => (v == null ? 'N/A' : v >= 1000 ? `${(v / 1000).toFixed(2)}s` : `${Math.round(v)}ms`);
// 阈值取 Lighthouse 官方分档（好 / 需改进 / 差）
const lamp = (v, good, poor) => (v == null ? '⚪' : v <= good ? '🟢' : v <= poor ? '🟡' : '🔴');
const slamp = (s) => (s == null ? '⚪' : s >= 90 ? '🟢' : s >= 50 ? '🟡' : '🔴');
const kb = (b) => `${Math.round((b ?? 0) / 1024)}KB`;

// 机会项：wastedBytes 明细（unused-javascript / unused-css-rules 同构）
// minBytes 分开给：JS chunk 动辄几百 KB，20KB 门槛能滤掉噪声；但 CSS 全站常常总共才几十 KB，
// 拿 20KB 卡会把「未用 15KB / 占比 90%」这种典型胖 CSS 整个滤没——而未用 CSS 往往是首屏最大的一块脂肪。
const waste = (id, minBytes, top = 8) =>
  (A[id]?.details?.items ?? [])
    .filter((i) => (i.wastedBytes ?? 0) > minBytes)
    .sort((a, b) => (b.wastedBytes ?? 0) - (a.wastedBytes ?? 0))
    .slice(0, top)
    .map((i) => ({
      url: String(i.url ?? '').replace(/^https?:\/\//, '').slice(0, 90),
      wasted: i.wastedBytes ?? 0,
      total: i.totalBytes ?? 0,
      pct: i.totalBytes ? Math.round(((i.wastedBytes ?? 0) / i.totalBytes) * 100) : 0,
    }));

// 无障碍失败项：只取 score===0 的硬失败（绝大多数 auditRef 是 score:null 的 N/A，不是问题）
const a11yFails = (lhr.categories.accessibility?.auditRefs ?? [])
  .map((r) => A[r.id])
  .filter((a) => a && a.score === 0)
  .map((a) => ({ id: a.id, title: a.title, count: a.details?.items?.length ?? 0 }));

// 最佳实践 / SEO 的失败项同理
const catFails = (cat) =>
  (lhr.categories[cat]?.auditRefs ?? [])
    .map((r) => A[r.id])
    .filter((a) => a && a.score === 0 && a.scoreDisplayMode !== 'notApplicable')
    .map((a) => ({ id: a.id, title: a.title }));

const report = {
  url: lhr.finalDisplayedUrl ?? url,
  device: DEVICE,
  scores: {
    performance: score('performance'),
    accessibility: score('accessibility'),
    bestPractices: score('best-practices'),
    seo: score('seo'),
  },
  metrics: {
    fcp: num('first-contentful-paint'),
    lcp: num('largest-contentful-paint'),
    cls: num('cumulative-layout-shift'),
    tbt: num('total-blocking-time'),
    si: num('speed-index'),
    tti: num('interactive'),
  },
  unusedJs: waste('unused-javascript', 20 * 1024),
  unusedCss: waste('unused-css-rules', 5 * 1024),
  a11yFails,
  bestPracticeFails: catFails('best-practices'),
  seoFails: catFails('seo'),
};

// 资源清单单独落盘，交给 resource-report.py 做域名/大小拆解 + 缓存压缩实测。
// 刻意不打进 stdout —— 它有几百条，直接打会撑爆上下文（MCP 的 analyze_resources 就栽在这）。
//
// 落盘格式**必须和 MCP 的 analyze_resources 对齐**（filename + summary.resourceCounts），
// 否则 resource-report.py 在脚本路径下会缺字段：图片明细打成空行、「按 type 拆解」整块消失。
if (RES_OUT) {
  const items = (A['network-requests']?.details?.items ?? []).map((i) => {
    const sizeKB = Math.round(((i.transferSize ?? 0) / 1024) * 10) / 10;
    let filename = '';
    try { filename = new URL(i.url).pathname.split('/').pop() || '/'; } catch { filename = String(i.url ?? '').slice(0, 40); }
    return { url: i.url, filename, type: i.resourceType, mimeType: i.mimeType, sizeKB };
  });
  const counts = {};
  for (const i of items) {
    const t = i.type || 'other';
    counts[t] ??= { count: 0, sizeKB: 0 };
    counts[t].count += 1;
    counts[t].sizeKB = Math.round((counts[t].sizeKB + i.sizeKB) * 10) / 10;
  }
  const summary = {
    totalResources: items.length,
    totalSizeKB: Math.round(items.reduce((s, i) => s + i.sizeKB, 0) * 10) / 10,
    resourceCounts: counts,
  };
  writeFileSync(RES_OUT, JSON.stringify({ url: report.url, summary, resources: items }, null, 2));
}

if (AS_JSON) {
  console.log(JSON.stringify(report, null, 2));
  process.exit(0);
}

const S = report.scores;
const M = report.metrics;
const out = [];
out.push(`\nLighthouse 全维度体检 — ${report.url}（${DEVICE}）\n`);
out.push('| 维度 | 评分 |');
out.push('|---|---|');
out.push(`| 性能 | ${slamp(S.performance)} ${S.performance ?? 'N/A'} |`);
out.push(`| 无障碍 | ${slamp(S.accessibility)} ${S.accessibility ?? 'N/A'} |`);
out.push(`| 最佳实践 | ${slamp(S.bestPractices)} ${S.bestPractices ?? 'N/A'} |`);
out.push(`| SEO | ${slamp(S.seo)} ${S.seo ?? 'N/A'} |`);
out.push('\n| 指标 | 实测 | 阈值 |');
out.push('|---|---|---|');
out.push(`| FCP | ${lamp(M.fcp, 1800, 3000)} ${ms(M.fcp)} | <1.8s |`);
out.push(`| LCP | ${lamp(M.lcp, 2500, 4000)} ${ms(M.lcp)} | <2.5s |`);
out.push(`| TBT | ${lamp(M.tbt, 200, 600)} ${ms(M.tbt)} | <200ms |`);
out.push(`| CLS | ${lamp(M.cls, 0.1, 0.25)} ${M.cls?.toFixed(3) ?? 'N/A'} | <0.1 |`);
out.push(`| Speed Index | ${lamp(M.si, 3400, 5800)} ${ms(M.si)} | <3.4s |`);
out.push(`| TTI | ${lamp(M.tti, 3800, 7300)} ${ms(M.tti)} | <3.8s |`);

const listWaste = (title, arr) => {
  if (!arr.length) return;
  out.push(`\n${title}`);
  for (const i of arr) out.push(`  · ${i.url} — 未用 ${kb(i.wasted)} / 共 ${kb(i.total)}（${i.pct}%）`);
};
listWaste('未使用的 JS（首屏脂肪，体积优化第一抓手）:', report.unusedJs);
listWaste('未使用的 CSS:', report.unusedCss);

if (a11yFails.length) {
  out.push('\n无障碍硬失败项（score:0）:');
  for (const f of a11yFails) out.push(`  · ${f.id} — ${f.title}${f.count ? `（${f.count} 处）` : ''}`);
}
if (report.bestPracticeFails.length) {
  out.push('\n最佳实践失败项:');
  for (const f of report.bestPracticeFails) out.push(`  · ${f.id} — ${f.title}`);
}
if (report.seoFails.length) {
  out.push('\nSEO 失败项:');
  for (const f of report.seoFails) out.push(`  · ${f.id} — ${f.title}`);
}
if (RES_OUT) out.push(`\n资源清单已落盘: ${RES_OUT}\n  → 下一步: python3 resource-report.py ${RES_OUT}`);

console.log(out.join('\n'));
