// 共享 HTTP 客户端 —— 所有需要发请求的脚本都走这里，别再各自手搓。
//
// 为什么不用 curl / fetch：
//   · curl / wget 会被本机 context-mode hook 拦（提示改走 ctx_execute）；
//   · 沙箱里的 fetch 连不上 Cloudflare（ETIMEDOUT）。
//   只有 node 的 http/https 直连是稳的，但它有三个坑，都在这里处理掉：
//
//   1. 协议分流：base 是 http://127.0.0.1:5173 时必须用 node:http，硬用 https 会直接连不上
//      （本地项目跑不了，就是这么来的）。
//   2. family:4 强制 IPv4：不指定的话 Cloudflare 的 IPv6 走不通、请求挂起到超时。
//   3. brotli/gzip 手动解压：node 的 http/https 不自动解压，不解压 body 是二进制，
//      正则抓不到资源名。
//
// 约定：**永不 throw**。失败返回 { err }，让调用方能区分「探测失败」和「探测到没有」——
// 这两者混同会把噪声升级成错误结论（旧 resource-report.py 就栽在这：curl 被拦 → 一律报
// 「无 Cache-Control / 未压缩」，把配好长缓存的站说成没配）。
import https from 'node:https';
import http from 'node:http';
import zlib from 'node:zlib';

/**
 * @param {string} url
 * @param {{method?:string, timeout?:number, headers?:object, body?:boolean, timing?:boolean}} opts
 *   body:false 时只取响应头，不收 body（探针场景更快）
 * @returns {Promise<{url,status,headers,body,ttfb,err}>} 失败时带 err，其余字段可能缺
 */
export function request(url, opts = {}) {
  const { method = 'GET', timeout = 25000, headers = {}, body = true, timing = false } = opts;
  return new Promise((res) => {
    let u;
    try { u = new URL(url); } catch (e) { return res({ url, err: `bad url: ${e.message}` }); }
    const isHttps = u.protocol === 'https:';
    const mod = isHttps ? https : http;
    const t0 = Date.now();
    const req = mod.request(
      {
        method,
        hostname: u.hostname,
        port: u.port || (isHttps ? 443 : 80),
        path: u.pathname + u.search,
        family: 4,
        timeout,
        headers: { 'Accept-Encoding': 'br,gzip', 'User-Agent': 'Mozilla/5.0', ...headers },
      },
      (r) => {
        const ttfb = timing ? Date.now() - t0 : null;
        if (!body) {
          r.resume(); // 丢弃 body，否则 socket 不释放
          return r.on('end', () => res({ url, status: r.statusCode, headers: r.headers, body: '', ttfb }));
        }
        const chunks = [];
        r.on('data', (d) => chunks.push(d));
        r.on('end', () => {
          let b = Buffer.concat(chunks);
          const enc = r.headers['content-encoding'];
          try {
            if (enc === 'br') b = zlib.brotliDecompressSync(b);
            else if (enc === 'gzip') b = zlib.gunzipSync(b);
            else if (enc === 'deflate') b = zlib.inflateSync(b);
          } catch { /* 解压失败就用原文，别让整个请求挂掉 */ }
          res({ url, status: r.statusCode, headers: r.headers, body: b.toString('utf8'), ttfb });
        });
      },
    );
    req.on('timeout', () => { req.destroy(); res({ url, err: 'timeout' }); });
    req.on('error', (e) => res({ url, err: e.message }));
    req.end();
  });
}

/** 只要指定的响应头（小写 key），失败返回 { err } */
export async function headersOf(url, want = [], timeout = 15000) {
  const r = await request(url, { body: false, timeout });
  if (r.err) return { err: r.err };
  const h = {};
  for (const k of want) if (r.headers[k] != null) h[k] = r.headers[k];
  return { status: r.status, h };
}

/** 拉 sitemap.xml 里的全部 <loc>；拿不到返回 [] */
export async function sitemapUrls(base) {
  const r = await request(`${base}/sitemap.xml`);
  if (r.err || !r.body) return [];
  return [...r.body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
}
