#!/usr/bin/env node
// 缓存 / 压缩探针 —— 给 resource-report.py 用（它原来调 curl，但 curl 被本机 hook 拦，
// 失败又被 except 吞掉，于是每个资源都被误报成「无 Cache-Control / 未压缩」）。
//
// 用法：URL 列表从 stdin 传入（JSON 数组），结果 JSON 从 stdout 出。
//   echo '["https://a.com/x.js"]' | node probe-headers.mjs
//
// 输出：{ "<url>": { ok, status, cacheControl, encoding, contentLength, err } }
//   ok:false + err  → **探测失败**，调用方必须如实说"没测到"，不准当成"站点没配"。
//   ok:true         → 这才是真值。cacheControl/encoding 为 null 表示确实没有该头。
import { request } from './_http.mjs';

const CONC = 6;

async function probe(url) {
  // 带 Accept-Encoding 请求（_http 默认就带 br,gzip），只取头不收 body
  const r = await request(url, { body: false, timeout: 15000 });
  if (r.err) return { ok: false, err: r.err };
  return {
    ok: true,
    status: r.status,
    cacheControl: r.headers['cache-control'] ?? null,
    encoding: r.headers['content-encoding'] ?? null,
    contentLength: r.headers['content-length'] ?? null,
  };
}

const stdin = await new Promise((res) => {
  let b = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (d) => (b += d));
  process.stdin.on('end', () => res(b));
});

let urls;
try {
  urls = JSON.parse(stdin);
  if (!Array.isArray(urls)) throw new Error('不是数组');
} catch (e) {
  console.error(`stdin 需要一个 URL 的 JSON 数组：${e.message}`);
  process.exit(1);
}

const out = {};
for (let i = 0; i < urls.length; i += CONC) {
  const batch = urls.slice(i, i + CONC);
  const rs = await Promise.all(batch.map(probe));
  batch.forEach((u, k) => (out[u] = rs[k]));
}
console.log(JSON.stringify(out));
