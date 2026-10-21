#!/usr/bin/env node
// Supply-chain scan for third-party skills / plugins before installing or trusting them.
// Static and read-only: nothing found is executed or fetched.
//
// Usage: node skill-supply-scan.mjs <dir|file>... [--json] [--summary] [--min <sev>] [--fail-on <sev>|none]
//   --min      lowest severity to print (default low; info adds the outbound URL inventory)
//   --fail-on  exit 1 when a finding reaches this level (default high); `none` = always 0
//   --summary  only per-rule counts and the top outbound hosts
// Severities: critical > high > medium > low > info.
// Inline allow: a line containing `supply-scan: allow` is skipped.
//
// Checks: hidden Unicode (zero-width, bidi controls, BOM mid-file, tag characters), curl/wget piped
// to a shell, base64-decode-and-execute, reverse shells, writes to ANTHROPIC_/OPENAI_ endpoint or key
// variables, reads of ~/.ssh ~/.aws and other credential stores, hook commands with interpolated
// input or catch-all matchers, settings that bypass permissions or auto-enable project MCP servers,
// unpinned `npx -y` / uvx / bunx packages, exfil-style endpoints, and an inventory of outbound URLs.
//
// Partly adapted from affaan-m/ECC (MIT): the-security-guide.md (hidden Unicode, outbound commands),
// skills/agent-security-hardening, skills/security-scan, skills/mcp-dependency-review.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { classifyNpm, classifyPy } from './mcp-pin-check.mjs';

const self = fileURLToPath(import.meta.url);
const selfDir = path.dirname(self);
const SKIP_DIRS = new Set(['.git', 'node_modules', '__pycache__', '.venv', 'venv', '.codegraph', '.remember']);
const MAX_BYTES = 3 * 1024 * 1024;
const SEV = { info: 0, low: 1, medium: 2, high: 3, critical: 4 };
const DOC_EXT = /\.(md|mdx|markdown|txt|rst)$/i;
const CODE_EXT = /\.(sh|bash|zsh|mjs|cjs|js|ts|py|rb|ps1|json|toml|ya?ml)$/i;

const lower = (sev) => Object.keys(SEV).find((k) => SEV[k] === Math.max(0, SEV[sev] - 1));

// ---- hidden unicode ----
const HIDDEN = /[\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]|[\u{E0000}-\u{E007F}]/gu;
const PICTO = /\p{Extended_Pictographic}|\uFE0F|[\u{1F3FB}-\u{1F3FF}]/u;
function hiddenFindings(line, lineNo) {
  const out = [];
  for (const m of line.matchAll(HIDDEN)) {
    const ch = m[0];
    const cp = ch.codePointAt(0);
    const i = m.index;
    if (cp === 0xfeff && lineNo === 1 && i === 0) continue; // BOM at file start
    const prev = [...line.slice(Math.max(0, i - 2), i)].at(-1) || '';
    const next = [...line.slice(i + ch.length, i + ch.length + 2)][0] || '';
    if (cp === 0x200d && PICTO.test(prev) && PICTO.test(next)) continue; // emoji ZWJ sequence
    if (cp >= 0xe0000 && /\u{1F3F4}|[\u{E0020}-\u{E007F}]/u.test(prev)) continue; // subdivision flag tags
    if ((cp === 0x200c || cp === 0x200d) && /[\u0600-\u06FF\u0900-\u0DFF]/.test(prev + next)) continue; // Arabic/Indic shaping
    const bidi = (cp >= 0x202a && cp <= 0x202e) || (cp >= 0x2066 && cp <= 0x2069);
    const tag = cp >= 0xe0000;
    out.push({ rule: tag ? 'unicode.tag-chars' : bidi ? 'unicode.bidi' : 'unicode.zero-width', col: i, cp: `U+${cp.toString(16).toUpperCase().padStart(4, '0')}` });
  }
  // one finding per rule per line; a lone zero-width char is usually a copy-paste artifact (medium),
  // runs of them can encode a payload (high); bidi overrides and tag characters are critical.
  const agg = new Map();
  for (const h of out) { const a = agg.get(h.rule) || { rule: h.rule, cps: [], col: h.col }; a.cps.push(h.cp); agg.set(h.rule, a); }
  return [...agg.values()].map((a) => ({ rule: a.rule, col: a.col, n: a.cps.length, cp: [...new Set(a.cps)].join(','),
    sev: a.rule === 'unicode.zero-width' ? (a.cps.length >= 4 ? 'high' : 'medium') : 'critical' }));
}

// ---- line rules ----
// docSev: severity when the hit sits in prose docs (instructions to the user) rather than code/config.
const RULES = [
  { id: 'exec.pipe-shell', sev: 'critical', docSev: 'high', re: /\b(?:curl|wget|iwr|Invoke-WebRequest)\b[^\n;&]*?\|\s*(?:sudo\s+)?(?:env\s+\S+\s+)?(?:ba|z|da|k|fi)?sh\b|\b(?:curl|wget)\b[^\n;&]*?\|\s*(?:sudo\s+)?(?:python3?|node|perl|ruby|iex)\b|(?:ba|z)?sh\s+<\(\s*(?:curl|wget)|\b(?:sh|bash)\s+-c\s+["']?\$\(\s*(?:curl|wget)|\biex\s*\(\s*(?:iwr|irm|New-Object)/i },
  { id: 'exec.base64', sev: 'high', re: /(?:base64\s+(?:-d|--decode|-D)\b|b64decode|atob\s*\(|Buffer\.from\([^)]*['"]base64['"]\)|frombase64string)[^\n]*(?:\|\s*(?:ba|z)?sh\b|\beval\b|\bexec\b|Function\s*\(|python3?\s+-c|node\s+-e|\biex\b)|(?:\beval\b|\bexec\b|Function\s*\()[^\n]*(?:base64\s+(?:-d|--decode|-D)|b64decode|atob\s*\(|['"]base64['"])/i },
  { id: 'exec.reverse-shell', sev: 'critical', re: /\/dev\/tcp\/[\w.-]+\/\d+|\bnc(?:at)?\s+(?:-\w+\s+)*-e\s|\bsocat\b[^\n]*exec:|bash\s+-i\s+>&/i },
  { id: 'env.endpoint-override', sev: 'high', docSev: 'medium', re: /(?:\bexport\s+|\bset(?:x|env)?\s+|\$env:|["']|\b)(?:ANTHROPIC_(?:BASE_URL|API_KEY|AUTH_TOKEN|CUSTOM_HEADERS)|OPENAI_(?:BASE_URL|API_BASE|API_KEY)|CLAUDE_CODE_USE_BEDROCK|ANTHROPIC_BEDROCK_BASE_URL)["']?\s*(?:=|:\s*["'$\w{]|\]\s*=)(?!=)(?!["'])/ },
  { id: 'env.endpoint-read', sev: 'info', re: /\b(?:ANTHROPIC_(?:BASE_URL|API_KEY|AUTH_TOKEN)|OPENAI_(?:BASE_URL|API_BASE|API_KEY))\b/ },
  { id: 'sensitive.path', sev: 'high', docSev: 'medium', re: /(?:~|\$HOME|\$\{HOME\}|%USERPROFILE%|os\.homedir\(\)[^\n]{0,20}|expanduser\(["']~)\/?(?:\/|\\|['"],\s*['"])?\.(?:ssh|aws|gnupg|kube\/config|docker\/config\.json|netrc|npmrc|pypirc|git-credentials|config\/gh\/hosts\.yml|claude\/\.credentials\.json|codex\/auth\.json)|Library\/Keychains|\bsecurity\s+find-(?:generic|internet)-password\b|\bkeyring\.get_password\b/ },
  { id: 'settings.bypass', sev: 'high', docSev: 'medium', re: /["']?defaultMode["']?\s*[:=]\s*["']bypassPermissions["']|--dangerously-skip-permissions|--permission-mode[ =]+bypassPermissions|permission_mode\s*=\s*["']?bypassPermissions|skipDangerousModePermissionPrompt["']?\s*:\s*true|--dangerously-bypass-approvals-and-sandbox|approval_policy\s*=\s*["']never["']/ },
  { id: 'settings.mcp-autoenable', sev: 'high', docSev: 'medium', re: /enableAllProjectMcpServers["']?\s*[:=]\s*true/ },
  { id: 'settings.allow-all-bash', sev: 'high', docSev: 'low', re: /["']Bash\((?:\*|:\*)\)["']/ },
  { id: 'net.exfil-endpoint', sev: 'high', docSev: 'medium', re: /https?:\/\/(?:[\w-]+\.)*(?:webhook\.site|requestbin\.\w+|pipedream\.net|ngrok(?:-free)?\.(?:io|app|dev)|trycloudflare\.com|transfer\.sh|pastebin\.com|paste\.ee|hastebin\.com|interact\.sh|oast\.\w+|burpcollaborator\.net|discord(?:app)?\.com\/api\/webhooks)|api\.telegram\.org\/bot/i },
  { id: 'net.ip-literal', sev: 'medium', docSev: 'low', re: /https?:\/\/(?!127\.|0\.0\.0\.0|10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\// },
  { id: 'persist.shell-rc', sev: 'medium', docSev: 'low', re: />>?\s*(?:~|\$HOME)\/\.(?:bashrc|zshrc|zprofile|bash_profile|profile)\b|\bcrontab\s+-?[^l\s-]|launchctl\s+(?:load|bootstrap)\b/ },
  { id: 'md.hidden-comment', sev: 'medium', docOnly: true, re: /<!--(?![^>]*(?:prettier|markdownlint|eslint|toc|end|begin|TODO|lint|cspell|textlint|omit|vale|ALL-CONTRIBUTORS|supply-scan))[^>]*\b(?:ignore (?:all|previous|the above)|system prompt|you must|do not tell|execute|curl|wget|token|secret|exfil)\b/i },
  { id: 'md.data-html', sev: 'medium', re: /data:text\/html|data:application\/(?:x-)?javascript/i },
];

// unpinned package runners on a command line: npx -y foo, npx foo@latest, uvx foo, bunx foo
const RUNNER = /\b(npx|bunx|pnpm\s+dlx|yarn\s+dlx|npm\s+exec|uvx|pipx\s+run)\s+((?:--?[\w-]+(?:=\S*)?\s+)*)([@\w][^\s'"`;|&)]*)/g;
function runnerFindings(line) {
  const out = [];
  for (const m of line.matchAll(RUNNER)) {
    const [, runner, flags, spec] = m;
    if (/^(-|\$|<|\{)/.test(spec) || /^(install|i|add|run|create|init)$/.test(spec)) continue;
    const r = /uvx|pipx/.test(runner) ? classifyPy(spec) : classifyNpm(spec);
    if (r.verdict !== 'high' && r.verdict !== 'medium') continue;
    const yes = /(^|\s)(-y|--yes)(\s|$)/.test(flags || '');
    out.push({ rule: 'pkg.unpinned-runner', sev: yes || /@latest$/.test(spec) ? 'medium' : 'low', detail: `${runner.replace(/\s+/g, ' ')} ${spec}: ${r.reason}` });
  }
  return out;
}

// ---- hooks / settings JSON structure ----
const SAFE_VARS = /^(CLAUDE_PLUGIN_ROOT|CLAUDE_PROJECT_DIR|CLAUDE_PLUGIN_DATA|HOME|PWD|TMPDIR|PATH|USER|SHELL|CODEX_HOME|XDG_[A-Z_]+)$/;
function walkHooks(obj, visit, event = null) {
  if (Array.isArray(obj)) { obj.forEach((x) => walkHooks(x, visit, event)); return; }
  if (!obj || typeof obj !== 'object') return;
  if (Array.isArray(obj.hooks) && ('matcher' in obj || obj.hooks.some((h) => h && h.command))) visit(event, obj);
  for (const [k, v] of Object.entries(obj)) if (k !== 'hooks' || !Array.isArray(v)) walkHooks(v, visit, /^[A-Z][A-Za-z]+$/.test(k) ? k : event);
}
function hookFindings(text, rel) {
  let j;
  try { j = JSON.parse(text); } catch { return []; }
  const out = [];
  const lineOf = (needle) => {
    const k = text.indexOf(JSON.stringify(needle).slice(1, 40));
    return k < 0 ? 1 : text.slice(0, k).split('\n').length;
  };
  walkHooks(j, (event, entry) => {
    const matcher = entry.matcher;
    for (const h of entry.hooks || []) {
      const cmd = typeof h?.command === 'string' ? h.command : '';
      if (!cmd) continue;
      const line = lineOf(cmd);
      const vars = [...cmd.matchAll(/\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/g)].map((m) => m[1]).filter((v) => !SAFE_VARS.test(v));
      const tmpl = cmd.match(/\{\{[^}]+\}\}|\$ARGUMENTS|\$\{file\}|\$TOOL_INPUT|\$CLAUDE_FILE_PATHS|\$CLAUDE_TOOL_INPUT/);
      if (tmpl || vars.some((v) => /^(file|FILE|FILE_PATH|TOOL_INPUT|ARGUMENTS|CLAUDE_FILE_PATHS|CLAUDE_TOOL_INPUT|INPUT|PROMPT|COMMAND)$/.test(v))) {
        out.push({ rule: 'hook.interpolation', sev: 'high', line, detail: `${event || 'hook'}: command interpolates tool/user input (${(tmpl && tmpl[0]) || vars.join(',')}); read stdin JSON instead` });
      }
      if (/\b(curl|wget|nc|scp|ssh|rsync)\b/.test(cmd)) out.push({ rule: 'hook.network', sev: 'high', line, detail: `${event || 'hook'}: hook command makes network calls` });
      if ((matcher === '*' || matcher === '.*' || matcher === '' ) && /PreToolUse|PostToolUse/.test(event || '')) out.push({ rule: 'hook.catch-all-matcher', sev: 'low', line, detail: `${event}: matcher "${matcher}" runs on every tool call` });
      if (/2>\s*\/dev\/null\s*\|\|\s*true|\|\|\s*true\s*$/.test(cmd)) out.push({ rule: 'hook.silent-errors', sev: 'low', line, detail: `${event || 'hook'}: errors suppressed` });
    }
  });
  return out.map((f) => ({ ...f, file: rel }));
}

// ---- walk ----
function listFiles(target) {
  const st = fs.statSync(target);
  if (st.isFile()) return [{ abs: target, rel: path.basename(target) }];
  const out = [];
  const seen = new Set(); // real paths, guards symlink cycles
  const stack = [[target, '']];
  while (stack.length) {
    const [d, relDir] = stack.pop();
    let real;
    try { real = fs.realpathSync(d); } catch { continue; }
    if (seen.has(real)) continue;
    seen.add(real);
    let ents;
    try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch { out.push({ abs: d, rel: relDir, unreadableDir: true }); continue; }
    for (const e of ents) {
      if (SKIP_DIRS.has(e.name)) continue;
      const p = path.join(d, e.name);
      const rel = relDir ? path.join(relDir, e.name) : e.name;
      let isDir = e.isDirectory(), isFile = e.isFile();
      if (e.isSymbolicLink()) { try { const st = fs.statSync(p); isDir = st.isDirectory(); isFile = st.isFile(); } catch { continue; } }
      if (isDir) stack.push([p, rel]);
      else if (isFile) out.push({ abs: p, rel });
    }
  }
  return out;
}

export function scan(targets, opts = {}) {
  const findings = [];
  const hosts = new Map();
  const stats = { files: 0, text: 0, binary: 0, skippedLarge: 0, unreadable: 0 };
  for (const target of targets) {
    const label = path.resolve(target);
    for (const f of listFiles(label)) {
      if (f.unreadableDir) { stats.unreadable++; continue; }
      const real = path.resolve(f.abs);
      if (path.dirname(real) === selfDir && /^(skill-supply-scan|mcp-pin-check)\.mjs$|^test-(skill-supply-scan|mcp-pin-check)\.sh$/.test(path.basename(real)) && !opts.includeSelf) continue;
      stats.files++;
      let buf;
      try {
        if (fs.statSync(f.abs).size > MAX_BYTES) { stats.skippedLarge++; continue; }
        buf = fs.readFileSync(f.abs);
      } catch { stats.unreadable++; continue; }
      if (buf.includes(0)) { stats.binary++; continue; }
      stats.text++;
      const text = buf.toString('utf8');
      const isDoc = DOC_EXT.test(f.rel);
      // tests and fixtures are not run by the agent: one level lower, still listed
      const isTest = /(^|\/)(tests?|__tests__|testdata|fixtures?|spec|[A-Za-z]+Tests?)\/|\.(test|spec)\.[cm]?[jt]sx?$|_test\.(go|py)$/.test(f.rel);
      const file = targets.length > 1 ? path.join(path.basename(label), f.rel) : f.rel;
      const lines = text.split(/\r?\n/);
      const perRule = new Map();
      const add = (x) => {
        const k = `${x.rule}`;
        const n = (perRule.get(k) || 0) + 1;
        perRule.set(k, n);
        if (n > (opts.perFileCap ?? 10)) return; // cap noisy files; total still counted
        findings.push(x);
      };
      lines.forEach((line, i) => {
        if (line.includes('supply-scan: allow')) return;
        const ln = i + 1;
        const excerpt = () => line.trim().replace(HIDDEN, (c) => `<U+${c.codePointAt(0).toString(16).toUpperCase()}>`).slice(0, 160);
        for (const h of hiddenFindings(line, ln)) add({ file, line: ln, rule: h.rule, sev: isTest ? lower(h.sev) : h.sev, detail: `${h.n}x ${h.cp} from col ${h.col}`, excerpt: excerpt() });
        if (line.length > 4000) return; // minified: unicode check only
        const hit = new Set();
        for (const r of RULES) {
          if (r.docOnly && !isDoc) continue;
          if (r.id === 'env.endpoint-read' && hit.has('env.endpoint-override')) continue;
          if (!r.re.test(line)) continue;
          hit.add(r.id);
          const comment = !isDoc && /^\s*(\/\/|#(?!!)|\*|\/\*|<!--|--\s)/.test(line);
          let sev = (isDoc || comment) && r.docSev ? r.docSev : r.sev;
          if (comment && sev !== 'info') sev = lower(sev); // code comments describe, they do not run
          if (isTest && sev !== 'info') sev = lower(sev);
          add({ file, line: ln, rule: r.id, sev, excerpt: excerpt() });
        }
        if (isDoc || CODE_EXT.test(f.rel) || /(^|\/)(hooks|bin|scripts)\//.test(f.rel)) {
          for (const r of runnerFindings(line)) add({ file, line: ln, rule: r.rule, sev: isDoc ? lower(r.sev) : r.sev, detail: r.detail, excerpt: excerpt() });
        }
        for (const m of line.matchAll(/\bhttps?:\/\/([A-Za-z0-9.-]+\.[A-Za-z]{2,}|\d{1,3}(?:\.\d{1,3}){3})(?::\d+)?/g)) {
          const h = m[1].toLowerCase();
          if (/^(localhost|127\.0\.0\.1|0\.0\.0\.0)$|(^|\.)example\.(com|org|net)$/.test(h)) continue;
          const e = hosts.get(h) || { count: 0, files: new Set() };
          e.count++; e.files.add(file); hosts.set(h, e);
        }
      });
      if (/\.json$/i.test(f.rel) && /"hooks"\s*:/.test(text)) for (const h of hookFindings(text, file)) add(h);
      for (const [rule, n] of perRule) if (n > (opts.perFileCap ?? 10)) findings.push({ file, line: 0, rule, sev: 'info', detail: `${n - (opts.perFileCap ?? 10)} more ${rule} hits in this file not listed` });
    }
  }
  const outbound = [...hosts.entries()].map(([host, e]) => ({ host, count: e.count, files: e.files.size })).sort((a, b) => b.count - a.count);
  return { targets: targets.map((t) => path.resolve(t)), stats, findings, outbound };
}

function main(argv) {
  const opts = { json: false, summary: false, min: 'low', failOn: 'high', targets: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--json') opts.json = true;
    else if (a === '--summary') opts.summary = true;
    else if (a === '--min') opts.min = argv[++i];
    else if (a === '--fail-on') opts.failOn = argv[++i];
    else if (a === '-h' || a === '--help') { console.log(fs.readFileSync(self, 'utf8').split('\n').slice(1, 20).join('\n')); return 0; }
    else if (a.startsWith('--')) { console.error(`unknown option: ${a}`); return 2; }
    else opts.targets.push(a);
  }
  if (!opts.targets.length || !(opts.min in SEV) || !(opts.failOn in SEV || opts.failOn === 'none')) { console.error('usage: skill-supply-scan.mjs <dir|file>... [--json] [--summary] [--min sev] [--fail-on sev|none]'); return 2; }
  for (const t of opts.targets) if (!fs.existsSync(t)) { console.error(`not found: ${t}`); return 2; }
  const res = scan(opts.targets, opts);
  const shown = res.findings.filter((f) => SEV[f.sev] >= SEV[opts.min]);
  const counts = {};
  for (const f of res.findings) if (f.sev !== 'info' || f.rule !== 'env.endpoint-read') counts[f.sev] = (counts[f.sev] || 0) + 1;
  if (opts.json) {
    console.log(JSON.stringify({ ...res, findings: shown, counts }, null, 2));
  } else if (opts.summary) {
    const byRule = {};
    for (const f of res.findings) byRule[`${f.sev} ${f.rule}`] = (byRule[`${f.sev} ${f.rule}`] || 0) + 1;
    for (const [k, n] of Object.entries(byRule).sort((a, b) => SEV[b[0].split(' ')[0]] - SEV[a[0].split(' ')[0]] || b[1] - a[1])) console.log(`${String(n).padStart(6)}  ${k}`);
    console.log(`top outbound hosts: ${res.outbound.slice(0, 15).map((h) => `${h.host}(${h.count})`).join(' ')}`);
  } else {
    for (const sev of ['critical', 'high', 'medium', 'low', 'info']) {
      if (SEV[sev] < SEV[opts.min]) continue;
      const fs2 = shown.filter((f) => f.sev === sev);
      if (!fs2.length) continue;
      console.log(`== ${sev.toUpperCase()} (${fs2.length})`);
      for (const f of fs2) console.log(`- ${f.file}:${f.line} [${f.rule}]${f.detail ? ` ${f.detail}` : ''}${f.excerpt ? `\n    ${f.excerpt}` : ''}`);
    }
    if (SEV[opts.min] <= SEV.info) console.log(`outbound hosts (${res.outbound.length}): ${res.outbound.map((h) => `${h.host}(${h.count})`).join(' ')}`);
  }
  if (!opts.json) {
    const c = ['critical', 'high', 'medium', 'low'].map((s) => `${s} ${counts[s] || 0}`).join(', ');
    console.log(`skill-supply-scan: ${res.stats.files} files (${res.stats.text} text, ${res.stats.binary} binary, ${res.stats.skippedLarge} >3MB skipped, ${res.stats.unreadable} unreadable); ${c}; ${res.outbound.length} outbound hosts`);
  }
  if (opts.failOn === 'none') return 0;
  return res.findings.some((f) => SEV[f.sev] >= SEV[opts.failOn]) ? 1 : 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === self) {
  try { process.exitCode = main(process.argv.slice(2)); } catch (e) { console.error(`skill-supply-scan internal error: ${e.stack || e}`); process.exitCode = 2; }
}
