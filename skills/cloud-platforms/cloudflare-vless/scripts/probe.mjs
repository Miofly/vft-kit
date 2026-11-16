#!/usr/bin/env node
// Explicit HTTP-proxy probe. curl performs CONNECT + certificate validation; no shell interpolation.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
export function parseResponse(output) {
  const marker = '\n__CF_PROBE__';
  const i = output.lastIndexOf(marker);
  if (i < 0) throw new Error('curl 没有完整结果');
  const [status, seconds] = output.slice(i + marker.length).trim().split(' ');
  if (!/^\d{3}$/.test(status) || !Number.isFinite(Number(seconds))) throw new Error('curl 结果格式异常');
  return { status: Number(status), seconds: Number(seconds), body: output.slice(0, i) };
}
export function evaluate(url, response) {
  const u = new URL(url);
  let detail = {};
  let ok = response.status >= 200 && response.status < 400;
  if (u.hostname === 'www.google.com' && u.pathname === '/generate_204') ok = response.status === 204;
  if (u.hostname === 'www.cloudflare.com' && u.pathname === '/cdn-cgi/trace') {
    const fields = Object.fromEntries(response.body.split('\n').filter(l => l.includes('=')).map(l => {
      const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1)];
    }));
    ok = response.status === 200 && Boolean(fields.ip) && /^[A-Z]{2}$/.test(fields.loc || '') && /^[A-Z]{3}$/.test(fields.colo || '');
    // Public IP is intentionally not persisted in the report.
    detail = { country: fields.loc, colo: fields.colo };
  }
  if (u.hostname === 'ipinfo.io' && u.pathname === '/json') {
    try {
      const fields = JSON.parse(response.body);
      ok = response.status === 200 && typeof fields.ip === 'string' && /^[A-Z]{2}$/.test(fields.country || '');
      detail = { country: fields.country };
    } catch { ok = false; }
  }
  return { ok, detail };
}
export function proxyAddress(value) {
  const u = new URL(value);
  if (u.protocol !== 'http:' || !['127.0.0.1','localhost','[::1]'].includes(u.hostname)
    || !u.port || u.username || u.password || u.pathname !== '/' || u.search || u.hash) {
    throw new Error('只接受显式端口的本机 HTTP proxy，例如 http://127.0.0.1:7890');
  }
  return u.href;
}
function target(value) {
  const u = new URL(value);
  if (u.protocol !== 'https:' || u.username || u.password || u.search || u.hash) throw new Error('测试 URL 必须是无凭据、query 和 fragment 的 HTTPS URL');
  return u.href;
}
function main(args) {
  if (!args.length || args.includes('--help')) {
    console.log('node probe.mjs --proxy http://127.0.0.1:7890 --out ABS_NEW_JSON [--url https://目标网站/ ...]\n经指定本地 HTTP proxy 串行做三轮检查；不改节点/系统代理。需要 curl（Windows 自动使用 curl.exe）。');
    return;
  }
  let proxy, out;
  const urls = ['https://www.google.com/generate_204','https://www.cloudflare.com/cdn-cgi/trace','https://ipinfo.io/json'];
  for (let i = 0; i < args.length; i += 2) {
    if (!args[i + 1]) throw new Error('参数必须成对');
    if (args[i] === '--proxy' && !proxy) proxy = proxyAddress(args[i + 1]);
    else if (args[i] === '--out' && !out) out = args[i + 1];
    else if (args[i] === '--url') urls.push(target(args[i + 1]));
    else throw new Error('未知或重复参数');
  }
  if (!proxy || !out || !path.isAbsolute(out)) throw new Error('需要 --proxy 和绝对路径 --out');
  // Reserve before sending requests: no probe should silently overwrite evidence from another run.
  const fd = fs.openSync(out, 'wx', 0o600);
  const rows = [];
  try {
    for (let round = 1; round <= 3; round++) {
      for (const url of [...new Set(urls)]) {
        const result = spawnSync(process.platform === 'win32' ? 'curl.exe' : 'curl', [
          '--noproxy', '', '--proxy', proxy, '--connect-timeout', '8', '--max-time', '25',
          '--silent', '--show-error', '--max-filesize', '2097152',
          '--write-out', '\n__CF_PROBE__%{http_code} %{time_total}', url,
        ], { encoding: 'utf8', timeout: 30000, maxBuffer: 3 * 1024 * 1024 });
        let row = { round, url, timestamp: new Date().toISOString(), ok: false };
        if (result.status === 0 && !result.error) {
          try {
            const response = parseResponse(result.stdout);
            row = { ...row, ...evaluate(url, response), status: response.status, seconds: response.seconds };
          } catch (error) { row.error = error.message; }
        } else row.error = result.error?.code || `curl_exit_${result.status}`;
        rows.push(row);
        console.log(JSON.stringify(row));
      }
    }
  } finally {
    const report = { status: rows.length === [...new Set(urls)].length * 3 && rows.every(r => r.ok) ? 'PASS' : 'FAIL',
      scope: 'HTTP proxy checks only; browser, country requirements and routing not proven', rows };
    fs.writeFileSync(fd, JSON.stringify(report, null, 2) + '\n');
    fs.closeSync(fd);
  }
  if (rows.some(r => !r.ok)) process.exitCode = 1;
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try { main(process.argv.slice(2)); }
  catch (error) { console.error(`FAIL: ${error.code || error.message}`); process.exitCode = 1; }
}
