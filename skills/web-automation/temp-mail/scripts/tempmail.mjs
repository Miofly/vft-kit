#!/usr/bin/env node
// tempmail.ing 临时邮箱 CLI，零依赖（Node 18+ 内置 fetch）。
// 接口来自 https://tempmail.ing/app.js（2026-10-12 实测）：
//   POST   https://api.tempmail.ing/api/generate        body {duration}  -> {success, email:{address, expiresAt, createdAt, durationMinutes}}
//   GET    https://api.tempmail.ing/api/emails/<addr>                   -> {success, emails:[{id, from_address, subject, text, content, received_at, is_read}]}
//   DELETE https://api.tempmail.ing/api/emails/<id>     body {emailAddress}
// 无鉴权；必须带 Origin/Referer，否则 Cloudflare 直接 429 HTML。
// 限流：generate 10 次/60 秒（X-RateLimit-*），连发间隔过短也会 429 并返回 retryAfterSeconds。
//
// 用法：
//   tempmail.mjs new [--duration 5|10|15|20|30|60]
//   tempmail.mjs inbox <address> [--json]
//   tempmail.mjs wait <address> [--timeout 180] [--interval 5] [--from 子串] [--subject 正则] [--since ISO]
//   tempmail.mjs delete <address> <emailId>
//   tempmail.mjs selftest            # 离线测试验证码/链接提取
// 输出 JSON 到 stdout，日志走 stderr；wait 超时退出码 2。

const API = process.env.TEMPMAIL_API || 'https://api.tempmail.ing';
const HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140 Safari/537.36',
  Origin: 'https://tempmail.ing',
  Referer: 'https://tempmail.ing/',
  Accept: 'application/json',
};
const DURATIONS = [5, 10, 15, 20, 30, 60];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.error('[tempmail]', ...a);

async function call(method, path, body, retries = 4) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(API + path, {
      method,
      headers: body ? { ...HEADERS, 'Content-Type': 'application/json' } : HEADERS,
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    let data;
    try { data = JSON.parse(text); } catch { data = null; }
    if (res.status === 429 && attempt < retries) {
      const wait = Number(data?.retryAfterSeconds) || Number(res.headers.get('retry-after')) || 10;
      log(`429 限流，${wait}s 后重试`);
      await sleep(Math.min(wait, 65) * 1000 + 300);
      continue;
    }
    if (!res.ok || !data?.success) {
      throw new Error(`${method} ${path} -> ${res.status} ${data?.error || text.slice(0, 120)}`);
    }
    return data;
  }
}

function stripHtml(html = '') {
  return html
    .replace(/<(script|style)[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<br\s*\/?>|<\/(p|div|tr|li|h\d)>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#39;|&apos;/g, "'").replace(/&quot;/g, '"')
    .replace(/[ \t]+/g, ' ')
    .trim();
}

// 验证码：优先取「验证码/code/OTP」关键词附近含数字的 4-8 位串，再退回正文里唯一的 6 位数字。
// 纯字母验证码不识别（会和普通单词混淆），这种情况看返回的 text 自己找。
export function extractCode(subject = '', body = '') {
  const text = `${subject}\n${body}`;
  const near = /(验证码|校验码|动态码|确认码|code|otp|pin|passcode|verification|一次性)[^0-9A-Za-z]{0,30}([A-Z0-9]{4,8}|\d{4,8})\b/i.exec(text);
  if (near && /\d/.test(near[2])) return near[2];
  const six = [...new Set(text.match(/(?<![\d#&])\d{6}(?!\d)/g) || [])];
  if (six.length === 1) return six[0];
  const any = text.match(/(?<![\d#&])\d{4,8}(?!\d)/);
  return any?.[0] || null;
}

// 链接：去重后把含 verify/confirm/activate/token/magic 等字样的排前面。
export function extractLinks(html = '', text = '') {
  const urls = new Set();
  for (const m of html.matchAll(/href=["']([^"']+)["']/gi)) urls.add(m[1].replace(/&amp;/g, '&'));
  for (const m of `${text}`.matchAll(/https?:\/\/[^\s"'<>)\]]+/g)) urls.add(m[0]);
  const list = [...urls].filter((u) => /^https?:/i.test(u));
  const score = (u) => (/verif|confirm|activat|validate|token|magic|login|signin|auth|reset|code/i.test(u) ? 0 : 1);
  return list.sort((a, b) => score(a) - score(b));
}

// 接口原样返回 RFC 2047 编码的主题（如 =?utf-8?B?55m75b2VIFBlcnBsZXhpdHk=?=），这里解成明文。
export function decodeMimeWords(s = '') {
  return s.replace(/\?=\s+=\?/g, '?==?').replace(/=\?([^?]+)\?([BbQq])\?([^?]*)\?=/g, (all, charset, enc, data) => {
    try {
      const bytes = /b/i.test(enc)
        ? Buffer.from(data, 'base64')
        : Buffer.from(data.replace(/_/g, ' ').replace(/=([0-9A-Fa-f]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16))), 'latin1');
      return new TextDecoder(charset.toLowerCase()).decode(bytes);
    } catch { return all; }
  });
}

function shape(mail) {
  const html = mail.content || '';
  const text = mail.text || stripHtml(html);
  const subject = decodeMimeWords(mail.subject || '');
  return {
    id: mail.id,
    from: mail.from_address,
    subject,
    receivedAt: mail.received_at,
    code: extractCode(subject, text),
    links: extractLinks(html, text).slice(0, 10),
    text: text.slice(0, 4000),
  };
}

function parseArgs(argv) {
  const pos = [];
  const opt = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const k = a.slice(2);
      const v = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
      opt[k] = v;
    } else pos.push(a);
  }
  return { pos, opt };
}

async function cmdNew(opt) {
  const duration = Number(opt.duration || 10);
  if (!DURATIONS.includes(duration)) throw new Error(`--duration 只能是 ${DURATIONS.join('/')}`);
  const { email } = await call('POST', '/api/generate', { duration });
  return email;
}

async function listInbox(address) {
  const { emails } = await call('GET', `/api/emails/${encodeURIComponent(address)}`);
  return (emails || []).map(shape);
}

async function cmdWait(address, opt) {
  const timeout = Number(opt.timeout || 180) * 1000;
  const interval = Math.max(3, Number(opt.interval || 5)) * 1000;
  const since = opt.since ? Date.parse(opt.since) : 0;
  const subjectRe = opt.subject ? new RegExp(opt.subject, 'i') : null;
  const fromSub = opt.from ? String(opt.from).toLowerCase() : null;
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const hit = (await listInbox(address)).find((m) =>
      (!since || Date.parse(m.receivedAt) >= since) &&
      (!fromSub || (m.from || '').toLowerCase().includes(fromSub)) &&
      (!subjectRe || subjectRe.test(m.subject)));
    if (hit) return hit;
    await sleep(interval);
  }
  return null;
}

function selftest() {
  const cases = [
    [['Your verification code', '<p>Your code is <b>482913</b>. It expires in 10 minutes.</p>'], '482913'],
    [['【某站】验证码', '您的验证码为：7731，5分钟内有效。'], '7731'],
    [['Sign in to Foo', 'Enter this code: A7K2QX to continue'], 'A7K2QX'],
    [['Welcome', 'Order 2026 shipped. Use 993311 to log in.'], '993311'],
    [['Hi', 'no code here'], null],
  ];
  let fail = 0;
  for (const [[s, b], want] of cases) {
    const got = extractCode(s, stripHtml(b));
    if (got !== want) { fail++; console.error(`FAIL extractCode(${JSON.stringify(s)}) = ${got}, want ${want}`); }
  }
  // 2026-10-12 实收 Perplexity 登录信：验证码只单独占一行，前面是“登录验证代码：”。
  const pplx = '此链接和代码仅在接下来的 5 分钟内有效。如果链接无效，您可以直接使用登录验证代码：\n \n\n\n737149\n\n 如有任何问题，请联系 support@perplexity.ai';
  if (extractCode('登录 Perplexity', pplx) !== '737149') { fail++; console.error('FAIL extractCode(perplexity)'); }
  if (decodeMimeWords('=?utf-8?B?55m75b2VIFBlcnBsZXhpdHk=?=') !== '登录 Perplexity') { fail++; console.error('FAIL decodeMimeWords B'); }
  if (decodeMimeWords('=?UTF-8?Q?Caf=C3=A9_code?=') !== 'Café code') { fail++; console.error('FAIL decodeMimeWords Q'); }
  const links = extractLinks('<a href="https://x.com/help">h</a><a href="https://x.com/verify?token=1&amp;a=2">v</a>', '');
  if (links[0] !== 'https://x.com/verify?token=1&a=2') { fail++; console.error('FAIL extractLinks order', links); }
  console.log(fail ? `selftest: ${fail} failed` : 'selftest: ok');
  process.exit(fail ? 1 : 0);
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const { pos, opt } = parseArgs(rest);
  const out = (v) => console.log(JSON.stringify(v, null, 2));
  switch (cmd) {
    case 'new': return out(await cmdNew(opt));
    case 'inbox': {
      if (!pos[0]) throw new Error('用法: inbox <address>');
      const list = await listInbox(pos[0]);
      return out(opt.json ? list : list.map(({ text, ...m }) => m));
    }
    case 'wait': {
      if (!pos[0]) throw new Error('用法: wait <address>');
      const hit = await cmdWait(pos[0], opt);
      if (!hit) { log('等待超时，没有符合条件的邮件'); process.exit(2); }
      return out(hit);
    }
    case 'delete': {
      if (!pos[0] || !pos[1]) throw new Error('用法: delete <address> <emailId>');
      return out(await call('DELETE', `/api/emails/${encodeURIComponent(pos[1])}`, { emailAddress: pos[0] }));
    }
    case 'selftest': return selftest();
    default:
      console.error('用法: tempmail.mjs new|inbox|wait|delete|selftest，详见文件头注释');
      process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => { log(e.message); process.exit(1); });
}
