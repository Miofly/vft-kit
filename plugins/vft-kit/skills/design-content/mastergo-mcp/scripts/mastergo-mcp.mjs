#!/usr/bin/env node
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const MODES = {
  vibe: {
    name: 'mastergo',
    package: '@mastergo/vibe-mcp@latest',
    url: 'http://localhost:50678',
  },
  magic: {
    name: 'mastergo-magic-mcp',
    package: '@mastergo/magic-mcp@latest',
    url: 'https://mastergo.com',
  },
};
const HOSTS = ['claude', 'codex'];
const secrets = [process.env.MG_MCP_TOKEN, process.env.MASTERGO_API_TOKEN].filter(Boolean);

function usage(message) {
  if (message) process.stderr.write(`${message}\n`);
  process.stderr.write('用法: mastergo-mcp.mjs status [--target claude|codex|both] | configure --mode vibe|magic --target claude|codex|both [--url URL] [--force] | doctor [--target claude|codex|both] [--health]\n');
  process.exit(2);
}

function parseArgs(argv) {
  const command = argv.shift();
  if (!['status', 'configure', 'doctor'].includes(command)) usage('未知命令');
  const options = { command, target: command === 'configure' ? undefined : 'both', force: false, health: false };
  const valued = new Set(['--target', '--mode', '--url']);
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (valued.has(arg)) {
      if (!argv[i + 1] || argv[i + 1].startsWith('--')) usage(`${arg} 缺少值`);
      options[arg.slice(2)] = argv[++i];
    } else if (arg === '--force') options.force = true;
    else if (arg === '--health') options.health = true;
    else usage(`未知参数: ${arg}`);
  }
  if (!['claude', 'codex', 'both'].includes(options.target)) usage('target 必须是 claude、codex 或 both');
  if (command === 'configure' && !['vibe', 'magic'].includes(options.mode)) usage('configure 必须指定 --mode vibe|magic');
  if (command !== 'configure' && (options.mode || options.url || options.force)) usage('该命令不接受 mode/url/force');
  if (command !== 'doctor' && options.health) usage('只有 doctor 接受 --health');
  if (options.url) {
    try {
      const url = new URL(options.url);
      if (!['http:', 'https:'].includes(url.protocol)) throw new Error();
    } catch { usage('--url 必须是 http(s) URL'); }
  }
  return options;
}

function redact(value) {
  let text = String(value ?? '');
  for (const secret of secrets) text = text.split(secret).join('<redacted>');
  return text
    .replace(/((?:token|api[_-]?key|authorization)\s*[=:]\s*)\S+/gi, '$1<redacted>')
    .replace(/(MG_MCP_TOKEN|MASTERGO_API_TOKEN)=\S+/g, '$1=<redacted>');
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', ...options });
  if (result.error?.code === 'ENOENT') return { ...result, status: 127, stderr: `找不到 ${command}` };
  return result;
}

function runHost(host, args) {
  const configured = process.env[`${host.toUpperCase()}_BIN`];
  const candidates = configured
    ? [configured]
    : [host, path.join(os.homedir(), `.volta/bin/${host}`), path.join(os.homedir(), `.local/bin/${host}`)];
  for (const command of [...new Set(candidates)]) {
    const result = run(command, args);
    if (result.status !== 127) return result;
  }
  return { status: 127, stdout: '', stderr: `找不到 ${host}` };
}

function hostsFor(target) {
  return target === 'both' ? HOSTS : [target];
}

function shellSplit(value) {
  const parts = [];
  let current = '';
  let quote;
  let escaped = false;
  for (const char of value.trim()) {
    if (escaped) { current += char; escaped = false; continue; }
    if (char === '\\' && quote !== "'") { escaped = true; continue; }
    if (quote) {
      if (char === quote) quote = undefined;
      else current += char;
      continue;
    }
    if (char === '"' || char === "'") { quote = char; continue; }
    if (/\s/.test(char)) {
      if (current) { parts.push(current); current = ''; }
    } else current += char;
  }
  if (current) parts.push(current);
  return parts;
}

function parseClaudeConfig(text) {
  const field = (name) => text.match(new RegExp(`^\\s{2}${name}:\\s*(.*)$`, 'mi'))?.[1]?.trim();
  const scopeText = field('Scope') || '';
  const scope = /^user/i.test(scopeText) ? 'user' : /^local/i.test(scopeText) ? 'local' : /^project/i.test(scopeText) ? 'project' : undefined;
  const command = field('Command');
  const args = shellSplit(field('Args') || '');
  const env = {};
  const environment = text.match(/^\s{2}Environment:\s*\n((?:\s{4}.*(?:\n|$))*)/mi)?.[1] || '';
  for (const line of environment.split('\n')) {
    const match = line.match(/^\s{4}([^=\s]+)=(.*)$/);
    if (match) env[match[1]] = match[2];
  }
  if (!command) return undefined;
  return {
    enabled: !/disabled/i.test(field('Status') || ''),
    scope,
    connection: /connected/i.test(field('Status') || '') ? 'connected' : /failed|error/i.test(field('Status') || '') ? 'failed' : 'unknown',
    transport: { type: (field('Type') || 'stdio').toLowerCase(), command, args, env },
  };
}

function getConfig(host, mode) {
  const name = MODES[mode].name;
  const args = host === 'codex' ? ['mcp', 'get', name, '--json'] : ['mcp', 'get', name];
  const result = runHost(host, args);
  if (result.status !== 0) {
    const detail = `${result.stdout || ''}\n${result.stderr || ''}`;
    if (result.status === 127) return { installed: false, host, mode, error: 'cli-missing' };
    if (/no mcp server|not found|does not exist|未找到/i.test(detail)) return { installed: false, host, mode };
    return { installed: false, host, mode, error: 'query-failed' };
  }
  if (host === 'codex') {
    try { return { installed: true, host, mode, config: JSON.parse(result.stdout) }; }
    catch { return { installed: true, host, mode, invalid: true }; }
  }
  const config = parseClaudeConfig(result.stdout);
  return config ? { installed: true, host, mode, config } : { installed: true, host, mode, invalid: true };
}

function flattened(entry) {
  return JSON.stringify(entry.config || '').toLowerCase();
}

function transportOf(entry) {
  return entry.config?.transport || entry.config || {};
}

function hasCredential(entry) {
  return Boolean(credentialValue(entry));
}

function credentialValue(entry) {
  const transport = transportOf(entry);
  const env = transport.env || transport.env_vars || {};
  for (const key of ['MG_MCP_TOKEN', 'MASTERGO_API_TOKEN']) {
    if (Object.hasOwn(env, key)) return env[key];
  }
  const args = transport.args || [];
  const index = args.findIndex((arg) => arg === '--token' || String(arg).startsWith('--token='));
  if (index < 0) return undefined;
  return String(args[index]).includes('=') ? String(args[index]).slice(8) : args[index + 1];
}

function officialPackage(entry) {
  const transport = transportOf(entry);
  if (transport.type !== 'stdio' || path.basename(String(transport.command || '')).replace(/\.cmd$/i, '') !== 'npx') return undefined;
  const expected = MODES[entry.mode].package.replace(/@latest$/, '');
  return (transport.args || []).find((arg) => String(arg) === expected || String(arg).startsWith(`${expected}@`));
}

function configuredVersion(entry) {
  const value = officialPackage(entry);
  if (!value) return undefined;
  const base = MODES[entry.mode].package.replace(/@latest$/, '');
  return value === base ? 'latest' : value.slice(base.length + 1);
}

function configuredUrl(entry) {
  if (!entry.installed) return undefined;
  if (entry.config) {
    const transport = entry.config.transport || entry.config;
    const args = transport.args || [];
    const urlIndex = args.findIndex((arg) => String(arg) === '--url' || String(arg).startsWith('--url='));
    if (urlIndex >= 0) return String(args[urlIndex]).includes('=') ? String(args[urlIndex]).slice(6) : args[urlIndex + 1];
    return transport.env?.API_BASE_URL || transport.env_vars?.API_BASE_URL;
  }
  const match = entry.text.match(/(?:--url(?:=|\s+)|API_BASE_URL=)(https?:\/\/[^\s,]+)/);
  return match?.[1];
}

function isEquivalent(entry, url, token) {
  if (!entry.installed || entry.invalid) return false;
  if (!officialPackage(entry) || entry.config?.enabled === false) return false;
  if (entry.mode === 'vibe') return configuredUrl(entry) === url;
  return credentialValue(entry) === token && configuredUrl(entry) === url;
}

function cacheVersion(packageName) {
  const scopeAndName = packageName.replace(/@latest$/, '').split('/');
  const cache = path.join(os.homedir(), '.npm/_npx');
  if (!fs.existsSync(cache)) return undefined;
  const versions = [];
  for (const dir of fs.readdirSync(cache)) {
    const file = path.join(cache, dir, 'node_modules', ...scopeAndName, 'package.json');
    try { versions.push({ mtime: fs.statSync(file).mtimeMs, version: JSON.parse(fs.readFileSync(file, 'utf8')).version }); } catch {}
  }
  return versions.sort((a, b) => b.mtime - a.mtime)[0]?.version;
}

function checkRuntime() {
  const nodeMajor = Number(process.versions.node.split('.')[0]);
  const npm = run('npm', ['--version']);
  const npmMajor = npm.status === 0 ? Number(npm.stdout.trim().split('.')[0]) : 0;
  process.stdout.write(`runtime node ${nodeMajor >= 18 ? 'ok' : 'unsupported'} (${process.versions.node})\n`);
  process.stdout.write(`runtime npm ${npmMajor >= 8 ? 'ok' : 'unsupported'} (${npm.status === 0 ? npm.stdout.trim() : 'missing'})\n`);
  return nodeMajor >= 18 && npmMajor >= 8;
}

function printEntry(entry) {
  const cache = cacheVersion(MODES[entry.mode].package);
  if (!entry.installed || entry.invalid) {
    const state = entry.error || (entry.invalid ? 'invalid' : 'missing');
    process.stdout.write(`${entry.host} ${entry.mode} ${state}${cache ? ` cache=${cache}` : ''}\n`);
    return;
  }
  const official = Boolean(officialPackage(entry));
  const enabled = entry.config?.enabled !== false;
  const url = configuredUrl(entry);
  const scope = entry.config?.scope || (entry.host === 'codex' ? 'merged' : 'unknown');
  const connection = entry.config?.connection ? ` connection=${entry.config.connection}` : '';
  const credential = entry.mode === 'magic' ? ` credential=${hasCredential(entry) ? 'present' : 'missing'}` : '';
  process.stdout.write(`${entry.host} ${entry.mode} installed package=${official ? 'official' : 'other'} version=${configuredVersion(entry) || 'unknown'} enabled=${enabled ? 'yes' : 'no'} scope=${scope}${connection}${credential}${url ? ` url=${url}` : ''}${cache ? ` cache=${cache}` : ''}\n`);
}

function entryIsHealthy(entry) {
  if (!entry.installed || entry.invalid || entry.error || !officialPackage(entry) || entry.config?.enabled === false) return false;
  if (entry.config?.connection === 'failed') return false;
  return entry.mode !== 'magic' || hasCredential(entry);
}

function safeSummary(entry, expectedUrl) {
  return [
    `package=${officialPackage(entry) || 'other'}`,
    `url=${configuredUrl(entry) || 'missing'}`,
    `enabled=${entry.config?.enabled !== false ? 'yes' : 'no'}`,
    `scope=${entry.config?.scope || (entry.host === 'codex' ? 'merged' : 'unknown')}`,
    ...(entry.mode === 'magic' ? [`credential=${hasCredential(entry) ? 'present' : 'missing'}`] : []),
    `expected_url=${expectedUrl}`,
  ].join(', ');
}

function chmodHostConfig(host) {
  const file = host === 'codex'
    ? path.join(process.env.CODEX_HOME || path.join(os.homedir(), '.codex'), 'config.toml')
    : path.join(os.homedir(), '.claude.json');
  if (fs.existsSync(file)) fs.chmodSync(file, 0o600);
}

function addArgs(host, mode, url, token) {
  const { name, package: pkg } = MODES[mode];
  const env = mode === 'magic' ? [`MG_MCP_TOKEN=${token}`, `API_BASE_URL=${url}`] : [];
  const command = ['npx', '-y', pkg, ...(mode === 'vibe' ? [`--url=${url}`] : [])];
  if (host === 'codex') return ['mcp', 'add', name, ...env.flatMap((item) => ['--env', item]), '--', ...command];
  return ['mcp', 'add', '--scope', 'user', name, ...env.flatMap((item) => ['--env', item]), '--', ...command];
}

function configureHost(host, mode, url, force) {
  const current = getConfig(host, mode);
  const token = mode === 'magic' ? process.env.MG_MCP_TOKEN || process.env.MASTERGO_API_TOKEN : undefined;
  if (current.error) {
    process.stderr.write(`${host} ${mode} 无法读取现有配置: ${current.error}\n`);
    return false;
  }
  if (current.invalid) {
    process.stderr.write(`${host} ${mode} 配置损坏，拒绝猜测修复；请先人工检查宿主配置\n`);
    return false;
  }
  if (isEquivalent(current, url, token)) {
    process.stdout.write(`${host} ${mode} 已是目标配置\n`);
    return true;
  }
  if (current.installed && !force) {
    process.stderr.write(`${host} ${mode} 配置冲突 (${safeSummary(current, url)})；确认后使用 --force 覆盖\n`);
    return false;
  }
  if (current.installed) {
    if (host === 'claude' && !current.config?.scope) {
      process.stderr.write(`${host} ${mode} 无法确定现有 scope，拒绝用 --force 猜测删除\n`);
      return false;
    }
    const removeArgs = host === 'claude'
      ? ['mcp', 'remove', '--scope', current.config.scope, MODES[mode].name]
      : ['mcp', 'remove', MODES[mode].name];
    const removed = runHost(host, removeArgs);
    if (removed.status !== 0) {
      process.stderr.write(`${host} ${mode} 移除旧配置失败: ${redact(removed.stderr)}\n`);
      return false;
    }
  }
  const added = runHost(host, addArgs(host, mode, url, token));
  if (added.status !== 0) {
    process.stderr.write(`${host} ${mode} 配置失败: ${redact(added.stderr)}\n`);
    return false;
  }
  chmodHostConfig(host);
  process.stdout.write(`${host} ${mode} configured\n`);
  return true;
}

function probe(url) {
  return new Promise((resolve) => {
    const parsed = new URL(url);
    const socket = net.createConnection({ host: parsed.hostname, port: Number(parsed.port || (parsed.protocol === 'https:' ? 443 : 80)) });
    const done = (ok) => { socket.destroy(); resolve(ok); };
    socket.setTimeout(800, () => done(false));
    socket.once('connect', () => done(true));
    socket.once('error', () => done(false));
  });
}

function healthConfig(entry, url) {
  if (entry.config?.transport) return entry.config;
  return { transport: transportOf(entry) };
}

function runHealth(entry, url) {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const checker = path.resolve(here, '../../../agent-ops/codex-baseline/scripts/check-mcp-health.mjs');
  const result = run(process.execPath, [checker], { input: JSON.stringify(healthConfig(entry, url)), timeout: Number(process.env.MCP_HEALTH_TIMEOUT_MS || 60000) + 1000 });
  return result.status === 0;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const hosts = hostsFor(options.target);
  if (options.command === 'configure') {
    if (options.mode === 'magic' && !(process.env.MG_MCP_TOKEN || process.env.MASTERGO_API_TOKEN)) {
      process.stderr.write('Magic 配置需要环境变量 MG_MCP_TOKEN 或 MASTERGO_API_TOKEN；不接受命令行明文 Token。\n');
      process.exitCode = 2;
      return;
    }
    const url = options.url || MODES[options.mode].url;
    if (options.mode === 'magic') process.stdout.write('Token 将由宿主原生命令写入用户级 MCP 配置，输出不会显示明文。\n');
    const results = hosts.map((host) => configureHost(host, options.mode, url, options.force));
    process.exitCode = results.every(Boolean) ? 0 : 1;
    return;
  }

  let ok = checkRuntime();
  const entries = hosts.flatMap((host) => Object.keys(MODES).map((mode) => getConfig(host, mode)));
  for (const entry of entries) {
    printEntry(entry);
    if (!entryIsHealthy(entry)) ok = false;
  }
  if (options.command === 'doctor') {
    const latestByMode = {};
    for (const [mode, spec] of Object.entries(MODES)) {
      const latest = run('npm', ['view', spec.package.replace(/@latest$/, ''), 'version', '--json']);
      if (latest.status === 0) {
        latestByMode[mode] = latest.stdout.trim().replaceAll('"', '');
        process.stdout.write(`${mode} registry latest=${redact(latestByMode[mode])}\n`);
      }
      else { process.stdout.write(`${mode} registry unavailable\n`); ok = false; }
    }
    for (const entry of entries.filter((item) => item.installed)) {
      const url = configuredUrl(entry) || MODES[entry.mode].url;
      const configured = configuredVersion(entry);
      const cached = cacheVersion(MODES[entry.mode].package);
      if (configured && configured !== 'latest' && latestByMode[entry.mode] && configured !== latestByMode[entry.mode]) {
        process.stdout.write(`${entry.host} ${entry.mode} 版本漂移 configured=${configured} latest=${latestByMode[entry.mode]}（不自动升级）\n`);
      }
      if (cached && latestByMode[entry.mode] && cached !== latestByMode[entry.mode]) {
        process.stdout.write(`${entry.host} ${entry.mode} npx 缓存漂移 cache=${cached} latest=${latestByMode[entry.mode]}（不自动清理）\n`);
      }
      if (entry.mode === 'vibe') {
        const listening = await probe(url);
        process.stdout.write(`${entry.host} vibe ${url} ${listening ? '监听正常' : '未监听；检查 MasterGo 客户端、当前文件 MCP 状态和实际端口'}\n`);
        if (!listening) ok = false;
      } else if (!hasCredential(entry)) {
        process.stdout.write(`${entry.host} magic 缺少凭据；并确认团队版权限和文件位于团队项目\n`);
        ok = false;
      } else {
        process.stdout.write(`${entry.host} magic 凭据已配置；若无权限请检查团队版与团队项目\n`);
      }
      if (options.health) {
        const healthy = runHealth(entry, url);
        process.stdout.write(`${entry.host} ${entry.mode} initialize ${healthy ? 'ok' : 'failed'}\n`);
        if (!healthy) ok = false;
      }
    }
  }
  process.exitCode = ok ? 0 : 1;
}

await main();
