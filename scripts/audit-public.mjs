#!/usr/bin/env node
// Public-release audit for vft-kit: private identifiers, secrets/tokens, PII,
// dangerous files and unreadable/binary files. Any CRITICAL/HIGH finding,
// any unknown binary, or more known binaries than --max-binary => exit 1.
//
// Usage:
//   node scripts/audit-public.mjs                 # audit this repo (git-aware)
//   node scripts/audit-public.mjs --root <dir>    # audit another directory
//   options: --json  --strict (warnings fail too)  --all-files (ignore .gitignore)
//            --max-binary <n> (default 60)  --allowlist <file>
//            --selftest [dir]  (build fixtures with fake secrets and assert detection)
// Exit codes: 0 pass, 1 findings, 2 usage/internal error.
//
// Allowlisting:
//   - inline: a line containing `audit-public: allow` is skipped;
//     `audit-public: allow-next-line` skips the following line.
//   - file: <root>/.audit-public-allow (or --allowlist). One entry per line:
//       <path-glob>[:<line>] [<rule-glob>]      e.g. docs/*.md:12 pii.*
//       fp:<fingerprint>                        fingerprint printed with each finding
//     `#` starts a comment. Globs: `*` (no slash), `**` (any), `?`.
// Secret values are never printed; findings carry a short sha256 fingerprint.
//
// Partly adapted from affaan-m/ECC (MIT): agents/opensource-sanitizer.md,
// skills/opensource-pipeline, skills/security-scan.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const self = path.resolve(fileURLToPath(import.meta.url));
const defaultRoot = path.resolve(path.dirname(self), '..');
const skip = new Set(['.git', '.codegraph', '.remember', '.idea', 'node_modules', '.code-review-graph']);
const MAX_TEXT_BYTES = 20 * 1024 * 1024;

// ---- 1. private identifiers (unchanged from the original audit) ----
const privateUser = ['wf', 'ly'].join('');
const privateDomain = ['ifly', 'tek.com'].join('');
const forbidden = [
  new RegExp(`\\b${privateUser}(?:nn)?\\b`, 'i'),
  new RegExp([['vft', 'fnn'].join(''), ['fd', 'wei4'].join(''), ['vft', 'dream'].join('')].join('|'), 'i'),
  new RegExp(`${privateDomain}|${['xun', 'fei'].join('')}|${['kuy', 'in'].join('')}|${['groc', 'ery'].join('')}`, 'i'),
  new RegExp(`/Users/${privateUser}\\b`, 'i'),
  new RegExp(`java/${privateUser}-spring|${['mysql6', 'sqlpub.com'].join('\\.') }|${['spring', 'local'].join('_')}`, 'i'),
];

// ---- 2. secret / PII line rules ----
// sev: critical|high fail the audit; warn is informational unless --strict.
// group: index of the capture group holding the secret value (0 = whole match).
// minEntropy: Shannon bits/char the value must reach (filters placeholders).
const lineRules = [
  { id: 'secret.private-key', sev: 'critical', re: /-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?: BLOCK)?-----/ },
  { id: 'secret.openai-anthropic', sev: 'critical', re: /\bsk-(?:ant-[a-z0-9]+-|proj-|svcacct-|or-v1-)?[A-Za-z0-9_-]{20,}/g, minEntropy: 3.5, mixed: true },
  { id: 'secret.stripe', sev: 'critical', re: /\b[rs]k_live_[A-Za-z0-9]{20,}/g, minEntropy: 3.5 },
  { id: 'secret.github', sev: 'critical', re: /\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})/g, minEntropy: 3.5 },
  { id: 'secret.huggingface', sev: 'critical', re: /\bhf_[A-Za-z0-9]{30,}/g, minEntropy: 3.5 },
  { id: 'secret.aws-key', sev: 'critical', re: /\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/g, minEntropy: 3.0 },
  { id: 'secret.aws-secret', sev: 'critical', re: /aws_secret(?:_access_key)?\s*["']?\s*[=:]\s*["']?([A-Za-z0-9+/=]{40})\b/gi, group: 1, minEntropy: 4.0 },
  { id: 'secret.slack', sev: 'critical', re: /\bxox[abprs]-[A-Za-z0-9-]{10,}|https:\/\/hooks\.slack\.com\/services\/T[A-Z0-9]+\/B[A-Z0-9]+\/[A-Za-z0-9]+/g, minEntropy: 3.0 },
  { id: 'secret.google-api', sev: 'critical', re: /\bAIza[0-9A-Za-z_-]{35}\b/g, minEntropy: 3.5 },
  { id: 'secret.google-oauth', sev: 'critical', re: /\bGOCSPX-[A-Za-z0-9_-]{20,}/g, minEntropy: 3.5 },
  { id: 'secret.kaggle', sev: 'critical', re: /\bKGAT_[0-9a-fA-F]{32}\b/g, minEntropy: 3.0 },
  { id: 'secret.vercel', sev: 'critical', re: /\bvc[pk]_[A-Za-z0-9]{40,}/g, minEntropy: 3.5 },
  { id: 'secret.npm', sev: 'critical', re: /\bnpm_[A-Za-z0-9]{36}\b/g, minEntropy: 3.5 },
  { id: 'secret.npmrc-auth', sev: 'critical', re: /_authToken\s*=\s*([^\s$"'{]{16,})/g, group: 1, minEntropy: 3.0 },
  { id: 'secret.sendgrid', sev: 'critical', re: /\bSG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}\b/g },
  { id: 'secret.telegram', sev: 'critical', re: /\b\d{8,10}:AA[A-Za-z0-9_-]{33}\b/g },
  { id: 'secret.jwt', sev: 'critical', re: /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g },
  { id: 'secret.db-url', sev: 'critical', re: /\b(?:postgres(?:ql)?|mysql|mariadb|mongodb(?:\+srv)?|redis|rediss|amqps?):\/\/([^\s:/@'"]+):([^\s@/'"]{4,})@/gi, group: 2, minEntropy: 2.5 },
  { id: 'secret.bearer', sev: 'critical', re: /\bBearer\s+([A-Za-z0-9._~+/-]{24,}=*)/g, group: 1, minEntropy: 3.5, mixed: true },
  // quoted assignment: password: "....", api_key = '....'
  { id: 'secret.generic', sev: 'high', check: genericValueOk, re: /\b[A-Za-z0-9_.-]*(?:password|passwd|pwd|secret|token|api[_-]?key|apikey|access[_-]?key|private[_-]?key|client[_-]?secret|credential)s?[A-Za-z0-9_.-]*["']?\s*[:=]\s*["']([^"'\s]{12,})["']/gi, group: 1, minEntropy: 3.6, mixed: true },
  // env style: export FOO_TOKEN=value
  { id: 'secret.generic', sev: 'high', check: genericValueOk, re: /^\s*(?:export\s+)?[A-Z0-9_]*(?:PASSWORD|PASSWD|SECRET|TOKEN|API_KEY|APIKEY|ACCESS_KEY)[A-Z0-9_]*\s*=\s*([^\s'"$#`]{12,})\s*$/g, group: 1, minEntropy: 3.6, mixed: true },
  { id: 'pii.phone-cn', sev: 'high', ctx: phoneContextOk, re: /(?<![\d.\w-])(1[3-9]\d{9})(?![\d\w])/g, group: 1, check: phoneOk },
  { id: 'pii.id-cn', sev: 'high', re: /(?<![\d\w])([1-9]\d{5}(?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx])(?![\d\w])/g, group: 1, check: idCardOk },
  { id: 'pii.email-personal', sev: 'high', re: /\b([A-Za-z0-9._%+-]+)@(?:gmail|googlemail|qq|163|126|yeah|foxmail|sina|sohu|aliyun|hotmail|outlook|live|yahoo|icloud|me|protonmail|proton)\.(?:com|cn|net|me)\b/gi, group: 1, check: emailLocalOk },
  { id: 'pii.private-ip', sev: 'warn', re: /(?<![\d.])(?:192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})(?![\d.])/g },
  { id: 'path.home', sev: 'warn', re: /(?:\/Users|\/home)\/(?!(?:user|username|you|me|runner|ubuntu|xxx|aistudio|jovyan|kaggle|node|app|appuser|linuxbrew|name|USER|USERNAME)\/|<|\$)[A-Za-z][A-Za-z0-9_-]+\/|C:\\Users\\(?!user\\|<)[A-Za-z]/g },
];

const PLACEHOLDER = /(example|sample|placeholder|your[_-]?|xxxx|\*\*\*\*|dummy|fake|mock|test|changeme|redacted|replace|<|>|\$|\{\{|\.\.\.|abcdef|123456|todo)/i;

function entropy(s) {
  const freq = new Map();
  for (const ch of s) freq.set(ch, (freq.get(ch) || 0) + 1);
  let h = 0;
  for (const n of freq.values()) { const p = n / s.length; h -= p * Math.log2(p); }
  return h;
}
function looksPlaceholder(v) {
  if (PLACEHOLDER.test(v)) return true;
  if (/^(.)\1+$/.test(v.replace(/[-_]/g, ''))) return true;
  if (/^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$/.test(v)) return true; // dotted identifier
  if (/^[A-Za-z]+(?:[-_][A-Za-z]+)*$/.test(v)) return true; // plain word / kebab / UPPER_SNAKE name
  return false;
}
// extra filters for the generic assignment rule: references, URLs, paths, regexes
function genericValueOk(v) {
  if (/^(https?|wss?|file):\/\//i.test(v) || /^(\/|~\/|\.\.?\/|[A-Za-z]:\\)/.test(v)) return false;
  if (/[[\]\\]|\{\d|\(\?/.test(v)) return false;          // regex source
  if (/^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$/.test(v)) return false; // env var / keychain item name
  if (/^(process\.env|os\.environ|env\.|import\.meta)/.test(v)) return false;
  return true;
}
// 11-digit numbers right after `key:` / `key =` without quotes are sizes, ids or timestamps
function phoneContextOk(line, idx) {
  return !/[:=]\s*$/.test(line.slice(Math.max(0, idx - 4), idx));
}
function phoneOk(v) {
  if (/(\d)\1{5,}/.test(v) || /12345678|23456789|87654321/.test(v)) return false;
  return !['13800138000', '13900139000', '13800000000', '18888888888', '13000000000'].includes(v);
}
function idCardOk(v) {
  const w = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2];
  let sum = 0;
  for (let i = 0; i < 17; i++) sum += Number(v[i]) * w[i];
  return '10X98765432'[sum % 11] === v[17].toUpperCase();
}
function emailLocalOk(local) {
  return !/^(example|user|username|you|your.*|name|test|foo|bar|xxx+|someone|noreply|no-reply|me|demo|admin|abc)$/i.test(local);
}
const fingerprint = (v) => crypto.createHash('sha256').update(v).digest('hex').slice(0, 12);

// ---- 3. dangerous files (by path) ----
const fileRules = [
  { id: 'file.env', sev: 'critical', test: (b) => /^\.env(\..+)?$/.test(b) && !/^\.env\.(example|sample|template|dist)$/.test(b) },
  { id: 'file.key', sev: 'critical', test: (b) => /\.(pem|key|p12|pfx|jks|keystore|kdbx|ppk|asc|gpg)$/i.test(b) },
  { id: 'file.ssh-key', sev: 'critical', test: (b) => /^id_(rsa|dsa|ecdsa|ed25519)$/.test(b) },
  { id: 'file.credentials', sev: 'critical', test: (b) => /^(credentials(\.json)?|service[-_]account.*\.json|\.netrc|\.pgpass|\.htpasswd|\.npmrc|\.pypirc|\.git-credentials)$/i.test(b) },
  { id: 'file.secrets-dir', sev: 'critical', testPath: (p) => /(^|\/)(\.secrets|\.ssh|\.aws|\.gnupg)\//.test(p) },
  { id: 'file.claude-local-settings', sev: 'high', testPath: (p) => /(^|\/)\.claude\/settings\.local\.json$/.test(p) },
  { id: 'file.sourcemap', sev: 'warn', test: (b) => /\.map$/.test(b) },
];

// ---- 4. binary classification (by content, never by extension) ----
const KNOWN_MAGIC = [
  ['image/png', [0x89, 0x50, 0x4e, 0x47]], ['image/jpeg', [0xff, 0xd8, 0xff]], ['image/gif', [0x47, 0x49, 0x46, 0x38]],
  ['image/x-icon', [0x00, 0x00, 0x01, 0x00]], ['image/bmp', [0x42, 0x4d]],
  ['font/woff', [0x77, 0x4f, 0x46, 0x46]], ['font/woff2', [0x77, 0x4f, 0x46, 0x32]],
  ['font/ttf', [0x00, 0x01, 0x00, 0x00]], ['font/otf', [0x4f, 0x54, 0x54, 0x4f]],
  ['audio/mpeg', [0x49, 0x44, 0x33]], ['audio/ogg', [0x4f, 0x67, 0x67, 0x53]], ['audio/flac', [0x66, 0x4c, 0x61, 0x43]],
];
const UNKNOWN_MAGIC = [
  ['zip/ooxml/jar', [0x50, 0x4b]], ['pdf', [0x25, 0x50, 0x44, 0x46]], ['ole (doc/xls/msi)', [0xd0, 0xcf, 0x11, 0xe0]],
  ['gzip', [0x1f, 0x8b]], ['bzip2', [0x42, 0x5a, 0x68]], ['zstd', [0x28, 0xb5, 0x2f, 0xfd]], ['7z', [0x37, 0x7a, 0xbc, 0xaf]],
  ['sqlite', [0x53, 0x51, 0x4c, 0x69, 0x74, 0x65]], ['elf', [0x7f, 0x45, 0x4c, 0x46]], ['mach-o', [0xcf, 0xfa, 0xed, 0xfe]],
  ['pe/exe', [0x4d, 0x5a]], ['wasm', [0x00, 0x61, 0x73, 0x6d]],
];
const startsWith = (buf, sig, off = 0) => sig.every((b, i) => buf[off + i] === b);
function classifyBinary(buf) {
  for (const [label, sig] of UNKNOWN_MAGIC) if (startsWith(buf, sig)) return { known: false, label };
  for (const [label, sig] of KNOWN_MAGIC) if (startsWith(buf, sig)) return { known: true, label };
  if (startsWith(buf, [0x52, 0x49, 0x46, 0x46])) { // RIFF: webp/wav/avi
    const t = buf.subarray(8, 12).toString('latin1');
    if (t === 'WEBP') return { known: true, label: 'image/webp' };
    if (t === 'WAVE') return { known: true, label: 'audio/wav' };
  }
  if (buf.subarray(4, 8).toString('latin1') === 'ftyp') return { known: true, label: 'video-or-image/mp4-heic-avif' };
  return null;
}
function isPlainText(buf) {
  for (const b of buf) if (b < 0x20 && b !== 0x09 && b !== 0x0a && b !== 0x0d) return false; // NUL / control bytes
  return !buf.includes(0x7f);
}

// ---- file listing ----
function walk(dir, root, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (skip.has(entry.name)) continue;
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(file, root, files);
    else files.push(path.relative(root, file));
  }
  return files;
}
function listFiles(root, allFiles) {
  if (!allFiles) {
    const top = spawnSync('git', ['-C', root, 'rev-parse', '--show-toplevel'], { encoding: 'utf8' });
    if (top.status === 0 && fs.realpathSync(top.stdout.trim()) === fs.realpathSync(root)) {
      const ls = spawnSync('git', ['-C', root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], { encoding: 'utf8', maxBuffer: 64 << 20 });
      if (ls.status === 0) {
        const files = [...new Set(ls.stdout.split('\0').filter(Boolean))]
          .filter((f) => !f.split('/').some((seg) => skip.has(seg)))
          .filter((f) => { try { return fs.lstatSync(path.join(root, f)).isFile(); } catch { return false; } });
        return { mode: 'git', files };
      }
    }
  }
  return { mode: 'walk', files: walk(root, root) };
}

// ---- allowlist ----
function globToRe(g) {
  const s = g.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*\*/g, '\u0001').replace(/\*/g, '[^/]*').replace(/\?/g, '[^/]').replace(/\u0001/g, '.*');
  return new RegExp(`^${s}$`);
}
function loadAllowlist(file) {
  const entries = [];
  if (!file || !fs.existsSync(file)) return entries;
  for (const raw of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = raw.replace(/#.*/, '').trim();
    if (!line) continue;
    if (line.startsWith('fp:')) { entries.push({ fp: line.slice(3).trim() }); continue; }
    const [loc, rule] = line.split(/\s+/);
    const m = loc.match(/^(.*?)(?::(\d+))?$/);
    entries.push({ path: globToRe(m[1]), line: m[2] ? Number(m[2]) : null, rule: rule ? globToRe(rule.replace(/\./g, '.')) : null });
  }
  return entries;
}
const allowed = (allow, f) => allow.some((e) => (e.fp ? e.fp === f.fp
  : e.path.test(f.file) && (e.line == null || e.line === f.line) && (!e.rule || e.rule.test(f.rule))));

// ---- scan ----
export function audit(root, opts = {}) {
  const { mode, files } = listFiles(root, opts.allFiles);
  const allow = loadAllowlist(opts.allowlist || path.join(root, '.audit-public-allow'));
  const res = { root, mode, scanned: 0, text: 0, findings: [], suppressed: 0, binary: { known: {}, knownFiles: [], unknown: [] }, unreadable: [] };
  const add = (f) => { if (allowed(allow, f)) res.suppressed++; else res.findings.push(f); };

  for (const rel of files) {
    const abs = path.join(root, rel);
    if (path.resolve(abs) === self) continue;
    res.scanned++;
    const base = path.basename(rel);
    for (const r of fileRules) {
      if ((r.test && r.test(base)) || (r.testPath && r.testPath(rel))) add({ rule: r.id, sev: r.sev, file: rel, line: 0 });
    }
    let buf;
    try {
      const st = fs.statSync(abs);
      if (st.size > MAX_TEXT_BYTES) { res.unreadable.push({ file: rel, reason: `too large (${st.size} bytes), not scanned` }); continue; }
      buf = fs.readFileSync(abs);
    } catch (e) { res.unreadable.push({ file: rel, reason: `not readable: ${e.code || e.message}` }); continue; }
    const bin = classifyBinary(buf);
    if (bin || !isPlainText(buf)) {
      const c = bin || { known: false, label: 'contains NUL or control bytes' };
      if (c.known) { res.binary.known[c.label] = (res.binary.known[c.label] || 0) + 1; res.binary.knownFiles.push(rel); }
      else if (allowed(allow, { rule: 'binary.unknown', file: rel, line: 0, fp: '' })) res.suppressed++;
      else res.binary.unknown.push({ file: rel, type: c.label });
      continue;
    }
    res.text++;
    const lines = buf.toString('utf8').split(/\r?\n/);
    lines.forEach((line, i) => {
      if (/audit-public:\s*allow(?!-next-line)/.test(line) || (i > 0 && /audit-public:\s*allow-next-line/.test(lines[i - 1]))) {
        if (forbidden.some((p) => p.test(line)) || lineRules.some((r) => new RegExp(r.re.source, r.re.flags.replace('g', '')).test(line))) res.suppressed++;
        return;
      }
      if (forbidden.some((p) => p.test(line))) add({ rule: 'private', sev: 'critical', file: rel, line: i + 1, fp: '' });
      if (line.length > 20000) return; // minified blob: identifier check only
      const seen = new Set();
      for (const r of lineRules) {
        const re = new RegExp(r.re.source, r.re.flags.includes('g') ? r.re.flags : `${r.re.flags}g`);
        for (const m of line.matchAll(re)) {
          const v = m[r.group || 0] ?? m[0];
          if (r.minEntropy && (looksPlaceholder(v) || entropy(v) < r.minEntropy)) continue;
          if (r.mixed && !(/\d/.test(v) && /[A-Za-z]/.test(v))) continue;
          if (r.check && !r.check(v)) continue;
          if (r.ctx && !r.ctx(line, m.index)) continue;
          let sev = r.sev;
          if (r.id === 'secret.private-key') { // header alone (docs/tests) is a warning; header + key body is critical
            const body = line.slice(m.index + m[0].length) + (lines[i + 1] || '');
            if (!/[A-Za-z0-9+/=]{40,}/.test(body)) sev = 'warn';
          }
          const key = `${r.id}:${v}`;
          if (seen.has(key)) continue;
          seen.add(key);
          add({ rule: r.id, sev, file: rel, line: i + 1, fp: fingerprint(v) });
        }
      }
    });
  }
  const knownCount = res.binary.knownFiles.length;
  // 20 基准 + hallmark 主题整页示例图 50 张 jpeg（见 THIRD_PARTY_NOTICES.md hallmark 行）。
  const maxBinary = opts.maxBinary ?? 60;
  const failing = res.findings.filter((f) => f.sev !== 'warn' || opts.strict);
  res.gate = {
    failingFindings: failing.length,
    unknownBinary: res.binary.unknown.length,
    unreadable: res.unreadable.length,
    knownBinary: knownCount,
    maxBinary,
    overThreshold: knownCount > maxBinary,
  };
  res.ok = !failing.length && !res.binary.unknown.length && !res.unreadable.length && knownCount <= maxBinary;
  return res;
}

function printText(res, opts) {
  const by = (pred) => res.findings.filter(pred);
  const fmt = (f) => `- ${f.file}${f.line ? `:${f.line}` : ''} [${f.rule}]${f.fp ? ` fp=${f.fp}` : ''}`;
  const priv = by((f) => f.rule === 'private');
  const secrets = by((f) => f.rule.startsWith('secret.') || (f.rule.startsWith('pii.') && f.sev !== 'warn'));
  const danger = by((f) => f.rule.startsWith('file.') && f.sev !== 'warn');
  const warns = by((f) => f.sev === 'warn');
  const out = res.ok ? console.log : console.error;
  if (priv.length) { out('public audit failed: private identifiers or local paths found'); priv.forEach((f) => out(`- ${f.file}:${f.line}`)); }
  if (secrets.length) { out('public audit failed: secrets / tokens / PII found (values hidden)'); secrets.forEach((f) => out(fmt(f))); }
  if (danger.length) { out('public audit failed: dangerous files present'); danger.forEach((f) => out(fmt(f))); }
  if (res.binary.unknown.length) { out('public audit failed: unknown binary files (cannot be scanned as text)'); res.binary.unknown.forEach((b) => out(`- ${b.file} [${b.type}]`)); }
  if (res.unreadable.length) { out('public audit failed: unreadable files'); res.unreadable.forEach((u) => out(`- ${u.file} [${u.reason}]`)); }
  if (res.gate.overThreshold) out(`public audit failed: ${res.gate.knownBinary} known binary files exceed --max-binary ${res.gate.maxBinary}`);
  if (warns.length) { out(`warnings (${opts.strict ? 'fail under --strict' : 'review, not failing'}):`); warns.forEach((f) => out(fmt(f))); }
  const kinds = Object.entries(res.binary.known).map(([k, n]) => `${k} ${n}`).join(', ') || 'none';
  out(`binary: ${res.gate.knownBinary} known (${kinds}), ${res.gate.unknownBinary} unknown; unreadable ${res.gate.unreadable}; allowlisted ${res.suppressed}`);
  if (res.binary.knownFiles.length && opts.listBinary) res.binary.knownFiles.forEach((f) => out(`  ~ ${f}`));
  if (res.ok) console.log(`public audit passed: ${res.scanned} files scanned (${res.text} text, mode ${res.mode})`);
}

// ---- selftest ----
function fakeToken(seed, len, alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789') {
  let s = '';
  for (let block = 0; s.length < len; block++) {
    for (const byte of crypto.createHash('sha256').update(`${seed}:${block}`).digest()) s += alphabet[byte % alphabet.length];
  }
  return s.slice(0, len);
}
function idCard(prefix17) {
  const w = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2];
  let sum = 0;
  for (let i = 0; i < 17; i++) sum += Number(prefix17[i]) * w[i];
  return prefix17 + '10X98765432'[sum % 11];
}
function selftest(dirArg) {
  const base = dirArg ? path.resolve(dirArg) : fs.mkdtempSync(path.join(os.tmpdir(), 'audit-public-'));
  const clean = path.join(base, 'clean');
  const leaky = path.join(base, 'leaky');
  for (const d of [clean, leaky]) fs.rmSync(d, { recursive: true, force: true });
  const w = (root, rel, data) => { fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true }); fs.writeFileSync(path.join(root, rel), data); };
  const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13]);
  const U = fakeToken.bind(null);
  const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  w(clean, 'README.md', ['# demo', 'export API_KEY="$MY_API_KEY"', 'token: ${{ secrets.GH_TOKEN }}', `key: ${'sk-'}${'x'.repeat(32)}`,
    'phone 13800138000, mail someone@example.com', 'Authorization: Bearer $TOKEN', 'password = getPassword()', `pem docs: ${'-----BEGIN '}${'PRIVATE KEY-----'} (header only)`,
    'url: "https://example.org/token/abc123def456"', 'credential_file = "/etc/app/credentials.json"', 'pattern = "KGAT_[0-9a-f]{32}"',
    '{"size": 15682749301, "model": "q4"}', 'TOKEN_NAME="CLOUDFLARE_API_TOKEN"', 'mount /home/aistudio/work'].join('\n'));
  w(clean, 'assets/logo.png', png);
  w(clean, '.env.example', 'OPENAI_API_KEY=\n');

  const expect = {
    'secret.openai-anthropic': `const k = "${'sk-'}${'proj-'}${U(1, 40)}";`,
    'secret.github': `token=${'ghp_'}${U(2, 36)}`,
    'secret.huggingface': `HF=${'hf_'}${U(3, 34)}`,
    'secret.aws-key': `id ${'AK' + 'IA'}${U(4, 16, upper)}`,
    'secret.slack': `slack ${'xo' + 'xb-'}${U(5, 12, '0123456789')}-${U(6, 24)}`,
    'secret.google-api': `g=${'AI' + 'za'}${U(7, 35)}`,
    'secret.bearer': `curl -H "Authorization: ${'Bea' + 'rer'} ${U(8, 40)}"`,
    'secret.private-key': `${'-----BEGIN '}${'OPENSSH '}${'PRIVATE KEY-----'}\n${U(18, 64)}`,
    'secret.kaggle': `kaggle ${'KG' + 'AT_'}${U(19, 32, '0123456789abcdef')}`,
    'secret.jwt': `jwt ${'ey' + 'J'}${U(9, 20)}.${'ey' + 'J'}${U(10, 30)}.${U(11, 30)}`,
    'secret.db-url': `${'postgres'}://admin:${U(12, 16)}@db.internal:5432/app`,
    'secret.generic': `db_password: "${U(13, 18)}!9"`,
    'pii.phone-cn': `call ${'159'}${'2746'}${'0318'}`,
    'pii.id-cn': `id ${idCard('11010519900307' + '123')}`,
    'pii.email-personal': `contact zhang.${'san'}@${'gmail'}.com`,
    private: `path /Users/${privateUser}/x`,
  };
  w(leaky, 'src/leaks.txt', Object.values(expect).join('\n') + '\n');
  w(leaky, 'src/env.sh', `export SERVICE_TOKEN=${U(14, 24)}9\n`);
  w(leaky, 'src/allowed.md', [`ok ${'gh' + 'p_'}${U(15, 36)} <!-- audit-public: allow -->`,
    '<!-- audit-public: allow-next-line -->', `ok ${'hf_'}${U(16, 34)}`, `skip-by-file ${'hf_'}${U(17, 34)}`].join('\n'));
  w(leaky, '.audit-public-allow', 'src/allowed.md:4 secret.*\n');
  w(leaky, '.env', `X=1\n`);
  w(leaky, 'keys/id_rsa', 'x\n');
  w(leaky, 'certs/client.p12', 'x\n');
  w(leaky, '.secrets/github/me.json', '{}\n');
  w(leaky, 'blob.bin', Buffer.from([0x01, 0x00, 0x02, 0x03]));
  w(leaky, 'fake.png', Buffer.from([0x50, 0x4b, 0x03, 0x04, 0, 0])); // zip disguised as png
  w(leaky, 'img/ok.png', png);

  const fails = [];
  const c = audit(clean, { allFiles: true });
  if (c.findings.some((f) => f.sev !== 'warn') || c.findings.length !== 1) fails.push(`clean fixture: expected exactly 1 warning (pem header), got ${JSON.stringify(c.findings)}`);
  if (!c.ok) fails.push(`clean fixture should pass, got ${JSON.stringify(c.findings)} ${JSON.stringify(c.binary.unknown)}`);
  if (c.binary.knownFiles.length !== 1) fails.push('clean fixture should count 1 known binary');

  const l = audit(leaky, { allFiles: true });
  const rules = new Set(l.findings.map((f) => f.rule));
  for (const id of [...Object.keys(expect), 'file.env', 'file.ssh-key', 'file.key', 'file.secrets-dir']) if (!rules.has(id)) fails.push(`missing detection: ${id}`);
  if (!l.findings.some((f) => f.rule === 'secret.private-key' && f.sev === 'critical')) fails.push('pem with key body should be critical');
  if (!l.findings.some((f) => f.file === 'src/env.sh' && f.rule === 'secret.generic')) fails.push('env-style generic secret not detected');
  if (l.findings.some((f) => f.file === 'src/allowed.md')) fails.push('allowlist (inline/file) not honoured');
  if (l.suppressed < 3) fails.push(`expected >=3 suppressed, got ${l.suppressed}`);
  const unk = l.binary.unknown.map((b) => b.file).sort().join(',');
  if (unk !== 'blob.bin,fake.png') fails.push(`unknown binaries wrong: ${unk}`);
  if (l.binary.knownFiles.length !== 1) fails.push('leaky fixture should count 1 known binary');
  if (l.ok) fails.push('leaky fixture should fail');
  const t = audit(clean, { allFiles: true, maxBinary: 0 });
  if (t.ok || !t.gate.overThreshold) fails.push('binary threshold gate not enforced');
  if (JSON.stringify(l).includes(U(1, 40))) fails.push('secret value leaked into result');

  const cli = (root) => spawnSync(process.execPath, [self, '--root', root, '--all-files'], { encoding: 'utf8' });
  const cc = cli(clean), lc = cli(leaky);
  if (cc.status !== 0) fails.push(`CLI clean exit ${cc.status}`);
  if (lc.status !== 1) fails.push(`CLI leaky exit ${lc.status}`);
  if ((lc.stdout + lc.stderr).includes(U(2, 36))) fails.push('CLI printed a secret value');

  if (!dirArg) fs.rmSync(base, { recursive: true, force: true });
  if (fails.length) { console.error('SELFTEST FAIL'); fails.forEach((f) => console.error(`- ${f}`)); process.exit(1); }
  console.log(`SELFTEST PASS: ${l.findings.length} findings in leaky fixture, ${rules.size} rule ids, clean fixture passes${dirArg ? `; fixtures kept in ${base}` : ''}`);
}

// ---- cli ----
function main(argv) {
  const opts = { root: defaultRoot, json: false, strict: false, allFiles: false, maxBinary: 60, allowlist: null, listBinary: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--root') opts.root = path.resolve(argv[++i] || '');
    else if (a === '--json') opts.json = true;
    else if (a === '--strict') opts.strict = true;
    else if (a === '--all-files') opts.allFiles = true;
    else if (a === '--list-binary') opts.listBinary = true;
    else if (a === '--max-binary') opts.maxBinary = Number(argv[++i]);
    else if (a === '--allowlist') opts.allowlist = path.resolve(argv[++i] || '');
    else if (a === '--selftest') { const d = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : null; return selftest(d); }
    else if (a === '-h' || a === '--help') { console.log(fs.readFileSync(self, 'utf8').split('\n').slice(1, 22).join('\n')); return; }
    else { console.error(`unknown option: ${a}`); process.exit(2); }
  }
  if (!Number.isFinite(opts.maxBinary) || !fs.existsSync(opts.root)) { console.error('invalid --max-binary or --root'); process.exit(2); }
  const res = audit(opts.root, opts);
  if (opts.json) console.log(JSON.stringify(res, null, 2));
  else printText(res, opts);
  process.exit(res.ok ? 0 : 1);
}

if (process.argv[1] && path.resolve(process.argv[1]) === self) {
  try { main(process.argv.slice(2)); } catch (e) { console.error(`audit-public internal error: ${e.stack || e}`); process.exit(2); }
}
