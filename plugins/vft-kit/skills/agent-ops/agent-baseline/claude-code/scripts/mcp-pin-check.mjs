#!/usr/bin/env node
// Read-only MCP version-pinning check for Claude Code and Codex configs.
//
// Sources (all optional, missing files are skipped):
//   ~/.claude.json            mcpServers + projects[<path>].mcpServers (+ <path>/.mcp.json)
//   ~/.claude/settings.json   mcpServers, enableAllProjectMcpServers
//   ~/.claude/plugins/installed_plugins.json -> <installPath>/.mcp.json, plugin.json mcpServers
//   ~/.codex/config.toml      [mcp_servers.<name>]
//
// Usage: node mcp-pin-check.mjs [--json] [--home <dir>] [--config <file>]... [--fail-on high|medium|none]
//   --home    read configs under another home (tests)
//   --config  scan only the given files (.json with mcpServers, or Codex .toml)
// Exit: 0 by default (report only); with --fail-on, 1 when a finding reaches that level; 2 on usage error.
// Never executes a discovered command, never resolves registry versions, never prints env/header values
// (only their key names).
//
// Classification adapted from affaan-m/ECC (MIT) skills/mcp-dependency-review.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const SEV_ORDER = { safe: 0, info: 1, review: 2, medium: 3, high: 4 };
const EXACT_SEMVER = /^v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;
const SHA40 = /^[0-9a-f]{40}$/i;

// ---- selector classifiers ----
function classifyGitRef(spec) {
  // github:user/repo#ref, git+https://...#ref, git+https://...@ref (uv), user/repo
  const m = spec.match(/#(.+)$/) || spec.match(/^git\+[^@]+(?:@[^/]+)?\/.*?@([^/@#]+)$/);
  const ref = m ? m[1].replace(/^semver:/, '') : '';
  if (!ref) return { verdict: 'high', reason: 'git source without ref (default branch, mutable)' };
  if (SHA40.test(ref)) return { verdict: 'review', reason: 'git source pinned to a full commit; review source separately' };
  if (EXACT_SEMVER.test(ref)) return { verdict: 'medium', reason: `git source pinned to tag ${ref} (tags can move)` };
  return { verdict: 'high', reason: `git source pinned to branch/ref "${ref}" (mutable)` };
}
export function classifyNpm(spec) {
  if (/^(git\+|git:|github:|gitlab:|bitbucket:)/.test(spec) || /^[\w.-]+\/[\w.-]+(#.*)?$/.test(spec)) return { selector: spec, ...classifyGitRef(spec) };
  if (/^(https?:|file:|\.{0,2}\/)/.test(spec)) return { selector: spec, verdict: 'review', reason: 'tarball/local path; version drift rules do not apply' };
  const m = spec.match(/^(@[^/@]+\/[^@]+|[^@]+)(?:@(.*))?$/);
  if (!m) return { selector: spec, verdict: 'review', reason: 'unparsed selector' };
  const ver = m[2];
  if (ver === undefined || ver === '') return { selector: spec, verdict: 'high', reason: 'no version (resolves latest at every launch)' };
  if (EXACT_SEMVER.test(ver)) return { selector: spec, verdict: 'safe', reason: 'exact version (direct selector only)' };
  if (/^[A-Za-z][\w.-]*$/.test(ver)) return { selector: spec, verdict: 'high', reason: `dist-tag @${ver} (mutable)` };
  return { selector: spec, verdict: 'medium', reason: `version range ${ver}` };
}
export function classifyPy(spec) {
  if (/^git\+|^https?:|^file:|^\.{0,2}\//.test(spec)) return { selector: spec, ...(spec.startsWith('git+') ? classifyGitRef(spec) : { verdict: 'review', reason: 'direct URL / path' }) };
  const at = spec.match(/^([A-Za-z0-9._\-[\]]+)@(.+)$/);
  if (at) {
    if (at[2] === 'latest') return { selector: spec, verdict: 'high', reason: '@latest (mutable)' };
    if (EXACT_SEMVER.test(at[2]) || /^\d+(\.\d+)*$/.test(at[2])) return { selector: spec, verdict: 'safe', reason: 'exact version (direct selector only)' };
  }
  const eq = spec.match(/^[A-Za-z0-9._\-[\]]+==([^,;*\s]+)$/);
  if (eq) return { selector: spec, verdict: 'safe', reason: 'exact version (direct selector only)' };
  if (/[<>=~!*,]/.test(spec)) return { selector: spec, verdict: 'medium', reason: 'version range' };
  return { selector: spec, verdict: 'high', reason: 'no version (resolves latest at every launch)' };
}
function classifyDocker(image) {
  if (/@sha256:[0-9a-f]{64}$/.test(image)) return { selector: image, verdict: 'safe', reason: 'pinned by digest' };
  return { selector: image, verdict: 'high', reason: 'docker tag without digest (tags can move)' };
}

const NPM_VALUE_FLAGS = new Set(['-p', '--package', '-c', '--call', '--registry', '--cache', '--userconfig', '--prefix', '-w', '--workspace']);
const UV_VALUE_FLAGS = new Set(['--from', '--with', '--python', '-p', '--index', '--index-url', '--extra-index-url', '--spec', '--with-editable', '--with-requirements']);
const DOCKER_VALUE_FLAGS = new Set(['-e', '--env', '-v', '--volume', '--name', '-p', '--publish', '--network', '--env-file', '-w', '--workdir', '--user', '-u', '--entrypoint', '--mount', '--platform', '-l', '--label', '--add-host', '--cpus', '--memory', '-m']);

// Classify one stdio invocation. Returns a list of {selector, verdict, reason} plus runner name.
export function classifyInvocation(command, args = []) {
  const base = path.basename(String(command || '')).replace(/\.(cmd|exe)$/i, '');
  let argv = args.map(String);
  let runner = base;
  if (['sh', 'bash', 'zsh', 'cmd'].includes(base)) {
    const i = argv.findIndex((a) => a === '-c' || a === '/c' || a === '-lc');
    if (i >= 0 && argv[i + 1] !== undefined) {
      const inner = argv.slice(i + 1).join(' ').trim().split(/\s+/);
      const sub = classifyInvocation(inner[0], inner.slice(1));
      return { runner: `${base} -c → ${sub.runner}`, items: sub.items.map((x) => ({ ...x, verdict: x.verdict === 'safe' ? 'review' : x.verdict, reason: `${x.reason}; wrapped in a shell` })) };
    }
    return { runner, items: [{ selector: argv.join(' '), verdict: 'review', reason: 'shell wrapper' }] };
  }
  if (base === 'npm' && ['exec', 'x'].includes(argv[0])) { runner = 'npm exec'; argv = argv.slice(1); }
  else if (['pnpm', 'yarn'].includes(base) && argv[0] === 'dlx') { runner = `${base} dlx`; argv = argv.slice(1); }
  else if (base === 'bun' && argv[0] === 'x') { runner = 'bun x'; argv = argv.slice(1); }
  else if (base === 'uv' && argv[0] === 'tool' && argv[1] === 'run') { runner = 'uv tool run'; argv = argv.slice(2); }
  else if (base === 'pipx' && argv[0] === 'run') { runner = 'pipx run'; argv = argv.slice(1); }
  else if (base === 'docker' && ['run', 'container'].includes(argv[0])) { runner = 'docker run'; argv = argv.slice(argv[0] === 'container' ? 2 : 1); }

  const npmLike = ['npx', 'bunx', 'npm exec', 'pnpm dlx', 'yarn dlx', 'bun x'].includes(runner);
  const pyLike = ['uvx', 'uv tool run', 'pipx run'].includes(runner);
  const items = [];
  const autoYes = argv.some((a) => a === '-y' || a === '--yes');
  if (npmLike) {
    let positional = null;
    for (let i = 0; i < argv.length; i++) {
      const a = argv[i];
      const eqv = a.match(/^(--package|--call)=(.+)$/);
      if (eqv) { if (eqv[1] === '--package') items.push(classifyNpm(eqv[2])); continue; }
      if (a === '-p' || a === '--package') { items.push(classifyNpm(argv[++i] || '')); continue; }
      if (NPM_VALUE_FLAGS.has(a)) { i++; continue; }
      if (a === '--') continue;
      if (a.startsWith('-')) continue;
      positional = a; break;
    }
    if (!items.length && positional) items.push(classifyNpm(positional));
    if (!items.length) items.push({ selector: argv.join(' '), verdict: 'review', reason: 'no package selector found' });
  } else if (pyLike) {
    let positional = null;
    for (let i = 0; i < argv.length; i++) {
      const a = argv[i];
      const eqv = a.match(/^(--from|--spec|--with)=(.+)$/);
      if (eqv) { items.push(classifyPy(eqv[2])); continue; }
      if (a === '--from' || a === '--spec' || a === '--with') { items.push(classifyPy(argv[++i] || '')); continue; }
      if (UV_VALUE_FLAGS.has(a)) { i++; continue; }
      if (a.startsWith('-')) continue;
      positional = a; break;
    }
    if (!argv.some((a) => /^--(from|spec)/.test(a)) && positional) items.push(classifyPy(positional));
    if (!items.length) items.push({ selector: argv.join(' '), verdict: 'review', reason: 'no package selector found' });
  } else if (runner === 'docker run') {
    let image = null;
    for (let i = 0; i < argv.length; i++) {
      const a = argv[i];
      if (DOCKER_VALUE_FLAGS.has(a)) { i++; continue; }
      if (a.startsWith('-')) continue;
      image = a; break;
    }
    items.push(image ? classifyDocker(image) : { selector: argv.join(' '), verdict: 'review', reason: 'docker image not found' });
  } else if (base === 'docker') {
    items.push({ selector: argv.join(' '), verdict: 'review', reason: 'unsupported docker subcommand' });
  } else if (path.isAbsolute(String(command || '')) || ['node', 'python', 'python3', 'deno', 'bun'].includes(base)) {
    items.push({ selector: [command, ...argv.slice(0, 1)].join(' '), verdict: 'info', reason: 'local script/binary; updates follow whatever installed it' });
  } else {
    items.push({ selector: String(command || ''), verdict: 'info', reason: 'binary on PATH; pin via its installer' });
  }
  return { runner, autoYes, items };
}

// ---- config readers ----
const readJson = (f) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return null; } };

// Minimal TOML subset reader for Codex config: [tables], key = string|array|bool|number|inline-table.
export function parseTomlSubset(text) {
  const root = {};
  let cur = root;
  const lines = text.split(/\r?\n/);
  const splitKey = (k) => k.match(/"[^"]*"|'[^']*'|[^.\s]+/g).map((p) => p.replace(/^["']|["']$/g, ''));
  const parseValue = (raw) => {
    raw = raw.trim();
    if (/^"""/.test(raw)) return raw.replace(/^"""|"""$/g, '');
    if (raw.startsWith('"')) return JSON.parse(raw.match(/^"(?:[^"\\]|\\.)*"/)[0]);
    if (raw.startsWith("'")) return raw.match(/^'([^']*)'/)[1];
    if (raw.startsWith('[')) {
      const out = [];
      const body = raw.slice(1, raw.lastIndexOf(']'));
      for (const m of body.matchAll(/"(?:[^"\\]|\\.)*"|'[^']*'|[^,\s]+/g)) out.push(parseValue(m[0]));
      return out;
    }
    if (raw.startsWith('{')) {
      const obj = {};
      const body = raw.slice(1, raw.lastIndexOf('}'));
      for (const m of body.matchAll(/("[^"]*"|[A-Za-z0-9_-]+)\s*=\s*("(?:[^"\\]|\\.)*"|'[^']*'|[^,}]+)/g)) obj[m[1].replace(/"/g, '')] = parseValue(m[2]);
      return obj;
    }
    if (raw === 'true' || raw === 'false') return raw === 'true';
    const n = Number(raw.replace(/#.*$/, '').trim());
    return Number.isNaN(n) ? raw : n;
  };
  for (let i = 0; i < lines.length; i++) {
    let line = lines[i].trim();
    if (!line || line.startsWith('#')) continue;
    const t = line.match(/^\[([^\]]+)\]\s*(#.*)?$/);
    if (t) {
      cur = root;
      for (const k of splitKey(t[1])) cur = cur[k] = cur[k] && typeof cur[k] === 'object' ? cur[k] : {};
      continue;
    }
    const kv = line.match(/^("[^"]+"|'[^']+'|[A-Za-z0-9_.-]+)\s*=\s*(.*)$/);
    if (!kv) continue;
    let raw = kv[2];
    const opens = (s) => (s.match(/\[/g) || []).length - (s.match(/\]/g) || []).length;
    while (raw.trim().startsWith('[') && opens(raw.replace(/"(?:[^"\\]|\\.)*"/g, '')) > 0 && i + 1 < lines.length) raw += ' ' + lines[++i].trim();
    if (raw.trim().startsWith('"""')) while (!/"""\s*$/.test(raw.trim().slice(3)) && i + 1 < lines.length) raw += '\n' + lines[++i];
    const keys = splitKey(kv[1]);
    let tgt = cur;
    for (const k of keys.slice(0, -1)) tgt = tgt[k] = tgt[k] || {};
    tgt[keys.at(-1)] = parseValue(raw);
  }
  return root;
}

function collect(home, configs) {
  const servers = [];
  const notes = [];
  const push = (source, name, cfg, extra = {}) => servers.push({ source, name, cfg: cfg || {}, ...extra });
  const fromJsonFile = (file, label) => {
    const j = readJson(file);
    if (!j) return false;
    for (const [n, c] of Object.entries(j.mcpServers || {})) push(label || file, n, c);
    return true;
  };
  if (configs.length) {
    for (const f of configs) {
      if (f.endsWith('.toml')) {
        const t = parseTomlSubset(fs.readFileSync(f, 'utf8'));
        for (const [n, c] of Object.entries(t.mcp_servers || {})) push(f, n, c, { codex: true });
      } else if (!fromJsonFile(f)) notes.push(`unreadable: ${f}`);
    }
    return { servers, notes };
  }
  const claudeJson = path.join(home, '.claude.json');
  const cj = readJson(claudeJson);
  if (cj) {
    for (const [n, c] of Object.entries(cj.mcpServers || {})) push('~/.claude.json', n, c);
    for (const [p, v] of Object.entries(cj.projects || {})) {
      for (const [n, c] of Object.entries(v.mcpServers || {})) push(`~/.claude.json projects[${p}]`, n, c);
      const pm = path.join(p, '.mcp.json');
      if (fs.existsSync(pm)) fromJsonFile(pm, pm);
    }
  }
  for (const f of ['settings.json', 'settings.local.json']) {
    const s = readJson(path.join(home, '.claude', f));
    if (!s) continue;
    for (const [n, c] of Object.entries(s.mcpServers || {})) push(`~/.claude/${f}`, n, c);
    if (s.enableAllProjectMcpServers === true) notes.push(`HIGH ~/.claude/${f}: enableAllProjectMcpServers=true (any repo's .mcp.json starts without approval)`);
  }
  const installed = readJson(path.join(home, '.claude', 'plugins', 'installed_plugins.json'));
  const enabled = (readJson(path.join(home, '.claude', 'settings.json')) || {}).enabledPlugins || {};
  for (const [id, entries] of Object.entries(installed?.plugins || {})) {
    for (const e of [].concat(entries)) {
      if (!e?.installPath) continue;
      const on = enabled[id] === true;
      if (!fs.existsSync(e.installPath)) { notes.push(`REVIEW plugin ${id}${on ? '' : ' (disabled)'}: installPath missing, its MCP servers (if any) cannot be checked`); continue; }
      const mcp = readJson(path.join(e.installPath, '.mcp.json'));
      const pj = readJson(path.join(e.installPath, '.claude-plugin', 'plugin.json'));
      const map = { ...(mcp?.mcpServers || (mcp && !mcp.mcpServers ? mcp : {})), ...(typeof pj?.mcpServers === 'object' ? pj.mcpServers : {}) };
      for (const [n, c] of Object.entries(map)) if (c && typeof c === 'object' && (c.command || c.url)) push(`plugin ${id}${on ? '' : ' (disabled)'}`, n, c, { disabled: !on });
    }
  }
  const codex = path.join(home, '.codex', 'config.toml');
  if (fs.existsSync(codex)) {
    const t = parseTomlSubset(fs.readFileSync(codex, 'utf8'));
    for (const [n, c] of Object.entries(t.mcp_servers || {})) push('~/.codex/config.toml', n, c, { codex: true });
  }
  return { servers, notes };
}

const literalSecret = (v) => typeof v === 'string' && v.length >= 12 && !/^\$\{?[A-Z_][A-Z0-9_]*\}?$/.test(v) && !/^(https?:\/\/|\/|~)/.test(v) && /\d/.test(v) && /[A-Za-z]/.test(v);
const AUTH_HEADER = /^(authorization|x-api-key|api-key|x-auth-token|cookie)$/i;

export function evaluate(server) {
  const c = server.cfg;
  const envKeys = Object.keys(c.env || {});
  const headerKeys = Object.keys(c.headers || c.http_headers || {});
  const out = { source: server.source, name: server.name, disabled: !!server.disabled, envKeys, headerKeys, findings: [] };
  const url = c.url || (['http', 'sse', 'streamable-http'].includes(c.type) ? c.url : null);
  if (url) {
    out.type = c.type || 'http';
    out.target = url.replace(/[?#].*$/, '');
    const local = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:|\/|$)/.test(url);
    if (/^http:\/\//.test(url) && !local) out.findings.push({ verdict: 'high', reason: 'remote MCP over plain http' });
    const hasAuth = headerKeys.some((h) => AUTH_HEADER.test(h)) || c.bearer_token_env_var || c.env_http_headers || c.headersHelper || c.oauth || c.auth;
    if (!hasAuth && !local) out.findings.push({ verdict: 'medium', reason: 'remote MCP with no auth configured (OAuth at runtime or public endpoint; confirm and document which)' });
    if (/[?&](key|token|api_key|apikey|access_token)=/i.test(url)) out.findings.push({ verdict: 'high', reason: 'credential in URL query string (value not shown)' });
    for (const h of headerKeys) if (AUTH_HEADER.test(h) && literalSecret(String((c.headers || c.http_headers)[h]).replace(/^Bearer\s+/i, ''))) out.findings.push({ verdict: 'high', reason: `literal credential in header ${h} (value not shown)` });
  } else {
    out.type = c.type || 'stdio';
    const inv = classifyInvocation(c.command, Array.isArray(c.args) ? c.args : []);
    out.runner = inv.runner;
    out.target = inv.items.map((i) => i.selector).join(', ');
    for (const it of inv.items) out.findings.push({ verdict: it.verdict, reason: it.reason, selector: it.selector });
    const local = [c.command, ...(Array.isArray(c.args) ? c.args.slice(0, 1) : [])].map(String).filter((x) => path.isAbsolute(x) && !x.includes('${'));
    for (const f of local) if (!fs.existsSync(f)) out.findings.push({ verdict: 'review', reason: `path does not exist: ${f} (server will fail to start or a stale config)` });
    if (inv.autoYes && inv.items.some((i) => i.verdict === 'high' || i.verdict === 'medium')) out.findings.push({ verdict: 'info', reason: '-y/--yes auto-installs without prompt (context, not a finding by itself)' });
  }
  for (const k of envKeys) if (/(TOKEN|KEY|SECRET|PASSWORD|PASS|AUTH)/i.test(k) && literalSecret(String(c.env[k]))) out.findings.push({ verdict: 'medium', reason: `env ${k} holds a literal credential in the config file (value not shown); prefer env passthrough or a secret store` });
  out.worst = out.findings.reduce((w, f) => (SEV_ORDER[f.verdict] > SEV_ORDER[w] ? f.verdict : w), 'safe');
  return out;
}

function main(argv) {
  const opts = { json: false, home: os.homedir(), configs: [], failOn: 'none' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--json') opts.json = true;
    else if (a === '--home') opts.home = path.resolve(argv[++i] || '');
    else if (a === '--config') opts.configs.push(path.resolve(argv[++i] || ''));
    else if (a === '--fail-on') opts.failOn = argv[++i];
    else if (a === '-h' || a === '--help') { console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(1, 18).join('\n')); return 0; }
    else { console.error(`unknown option: ${a}`); return 2; }
  }
  if (!['none', 'high', 'medium', 'review'].includes(opts.failOn)) { console.error('--fail-on must be none|high|medium|review'); return 2; }
  const { servers, notes } = collect(opts.home, opts.configs);
  const results = servers.map(evaluate);
  const counts = { high: 0, medium: 0, review: 0, info: 0, safe: 0 };
  for (const r of results) counts[r.worst]++;
  if (opts.json) {
    console.log(JSON.stringify({ home: opts.configs.length ? null : opts.home, counts, notes, results }, null, 2));
  } else {
    const order = ['high', 'medium', 'review', 'info', 'safe'];
    for (const sev of order) {
      const rs = results.filter((r) => r.worst === sev);
      if (!rs.length) continue;
      console.log(`== ${sev.toUpperCase()} (${rs.length})`);
      for (const r of rs) {
        const why = r.findings.filter((f) => f.verdict === sev).map((f) => f.reason).join('; ');
        const keys = [r.envKeys.length ? `env keys: ${r.envKeys.join(',')}` : '', r.headerKeys.length ? `header keys: ${r.headerKeys.join(',')}` : ''].filter(Boolean).join(' ');
        const shown = r.runner && !String(r.target || '').startsWith(r.runner) && !String(r.target || '').endsWith(`/${r.runner}`) ? `${r.runner} ${r.target}` : r.target || '';
        console.log(`- [${r.source}] ${r.name}: ${shown} -> ${why || sev}${keys ? ` (${keys})` : ''}`);
      }
    }
    for (const n of notes) console.log(`note: ${n}`);
    console.log(`mcp-pin-check: ${results.length} servers; high ${counts.high}, medium ${counts.medium}, review ${counts.review}, info ${counts.info}, safe ${counts.safe}`);
    console.log('boundary: static read of config only; SAFE covers the direct selector, not transitive deps or package integrity; pin to a version you reviewed, not today\'s latest.');
  }
  if (opts.failOn !== 'none') {
    const lvl = SEV_ORDER[opts.failOn];
    if (results.some((r) => SEV_ORDER[r.worst] >= lvl) || (lvl <= SEV_ORDER.high && notes.some((n) => n.startsWith('HIGH')))) return 1;
  }
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { process.exitCode = main(process.argv.slice(2)); } catch (e) { console.error(`mcp-pin-check internal error: ${e.message}`); process.exitCode = 2; }
}
