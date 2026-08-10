import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const here = path.dirname(fileURLToPath(import.meta.url));
const cli = path.resolve(here, '../scripts/mastergo-mcp.mjs');

function fixture(state = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'mastergo-mcp-test-'));
  const bin = path.join(root, 'bin');
  const home = path.join(root, 'home');
  const stateFile = path.join(root, 'state.json');
  const logFile = path.join(root, 'calls.jsonl');
  fs.mkdirSync(bin);
  fs.mkdirSync(home);
  fs.writeFileSync(stateFile, JSON.stringify({ claude: {}, codex: {}, ...state }));
  const fake = `#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const host = path.basename(process.argv[1]);
const args = process.argv.slice(2);
const stateFile = process.env.FAKE_MCP_STATE;
const logFile = process.env.FAKE_MCP_LOG;
const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
fs.appendFileSync(logFile, JSON.stringify({ host, args }) + '\\n');
if (host === 'npm') {
  if (args[0] === '--version') process.stdout.write('10.9.2\\n');
  else if (args[0] === 'view') process.stdout.write(JSON.stringify(args[1].includes('vibe') ? '1.0.28' : '0.2.7') + '\\n');
  else process.exitCode = 2;
  return;
}
if (args[0] !== 'mcp') process.exit(2);
const action = args[1];
const name = action === 'get' ? args[2] : action === 'remove' ? args.at(-1) : args[2] === '--scope' ? args[5] : args[2];
if (action === 'get') {
  if (process.env.FAKE_QUERY_FAIL_HOST === host) { process.stderr.write('configuration unreadable\\n'); process.exit(3); }
  const value = state[host]?.[name];
  if (!value) { process.stderr.write('No MCP server named ' + name + '\\n'); process.exit(1); }
  if (host === 'codex') process.stdout.write(value === '__INVALID_JSON__' ? '{broken' : JSON.stringify(value) + '\\n');
  else {
    const t = value.transport || value;
    const scope = value.scope || 'user';
    const status = value.enabled === false ? 'Disabled' : value.connection === 'failed' ? 'Failed to connect' : 'Connected';
    process.stdout.write([name + ':', '  Scope: ' + scope[0].toUpperCase() + scope.slice(1) + ' config', '  Status: ' + status, '  Type: stdio', '  Command: ' + t.command, '  Args: ' + (t.args || []).join(' '), '  Environment:', ...Object.entries(t.env || {}).map(([k,v]) => '    ' + k + '=' + v)].join('\\n') + '\\n');
  }
  return;
}
if (action === 'add' && process.env.FAKE_FAIL_HOST === host) { process.stderr.write('forced failure\\n'); process.exit(1); }
if (action === 'add' || action === 'remove') return;
process.exit(2);
`;
  for (const name of ['claude', 'codex', 'npm']) {
    const file = path.join(bin, name);
    fs.writeFileSync(file, fake, { mode: 0o755 });
  }
  const fakeMcp = `#!/usr/bin/env node
process.stdin.setEncoding('utf8');
let input = '';
process.stdin.on('data', chunk => {
  input += chunk;
  if (!input.includes('\\n')) return;
  const message = JSON.parse(input.split('\\n')[0]);
  process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id: message.id, result: { protocolVersion: '2025-06-18', capabilities: {}, serverInfo: { name: 'fake', version: '1' } } }) + '\\n');
});
`;
  for (const name of ['fake-mcp', 'npx']) fs.writeFileSync(path.join(bin, name), fakeMcp, { mode: 0o755 });
  const env = {
    ...process.env,
    HOME: home,
    PATH: `${bin}:${process.env.PATH}`,
    FAKE_MCP_STATE: stateFile,
    FAKE_MCP_LOG: logFile,
  };
  return {
    root,
    home,
    env,
    run(args, extraEnv = {}) {
      return spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8', env: { ...env, ...extraEnv } });
    },
    calls() {
      if (!fs.existsSync(logFile)) return [];
      return fs.readFileSync(logFile, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse);
    },
    cleanup() { fs.rmSync(root, { recursive: true, force: true }); },
  };
}

function codexConfig(args, env = {}) {
  return { enabled: true, transport: { type: 'stdio', command: 'npx', args, env } };
}

test('status 同时检查两套宿主且缺失时返回非零', () => {
  const f = fixture();
  try {
    const result = f.run(['status']);
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stdout, /claude\s+vibe\s+missing/);
    assert.match(result.stdout, /claude\s+magic\s+missing/);
    assert.match(result.stdout, /codex\s+vibe\s+missing/);
    assert.match(result.stdout, /codex\s+magic\s+missing/);
  } finally { f.cleanup(); }
});

test('configure vibe 使用官方包和当前默认端口，只修改点名宿主', () => {
  const f = fixture();
  try {
    const result = f.run(['configure', '--mode', 'vibe', '--target', 'codex']);
    assert.equal(result.status, 0, result.stderr);
    const add = f.calls().find((call) => call.host === 'codex' && call.args[1] === 'add');
    assert.deepEqual(add.args, ['mcp', 'add', 'mastergo', '--', 'npx', '-y', '@mastergo/vibe-mcp@latest', '--url=http://localhost:30678']);
    assert.equal(f.calls().some((call) => call.host === 'claude'), false);
  } finally { f.cleanup(); }
});

test('等价配置幂等退出，不重复 add', () => {
  const f = fixture({ codex: { mastergo: codexConfig(['-y', '@mastergo/vibe-mcp@latest', '--url', 'http://localhost:30678']) } });
  try {
    const result = f.run(['configure', '--mode', 'vibe', '--target', 'codex']);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /已是目标配置/);
    assert.equal(f.calls().some((call) => call.args[1] === 'add'), false);
  } finally { f.cleanup(); }
});

test('both 中一个宿主失败时仍尝试另一个宿主', () => {
  const f = fixture();
  try {
    const result = f.run(['configure', '--mode', 'vibe', '--target', 'both'], { FAKE_FAIL_HOST: 'claude' });
    assert.equal(result.status, 1);
    assert.deepEqual(f.calls().filter((call) => call.args[1] === 'add').map((call) => call.host), ['claude', 'codex']);
  } finally { f.cleanup(); }
});

test('冲突配置默认停止，显式 force 才重注册', () => {
  const state = { codex: { mastergo: codexConfig(['unrelated-package']) } };
  const first = fixture(state);
  try {
    const result = first.run(['configure', '--mode', 'vibe', '--target', 'codex']);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /配置冲突/);
    assert.equal(first.calls().some((call) => ['add', 'remove'].includes(call.args[1])), false);
  } finally { first.cleanup(); }

  const forced = fixture(state);
  try {
    const result = forced.run(['configure', '--mode', 'vibe', '--target', 'codex', '--force']);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(forced.calls().filter((call) => ['remove', 'add'].includes(call.args[1])).map((call) => call.args[1]), ['remove', 'add']);
  } finally { forced.cleanup(); }
});

test('Magic 只从环境变量取 Token，并对输出脱敏', () => {
  const secret = 'mg_test_secret_never_print';
  const missing = fixture();
  try {
    const result = missing.run(['configure', '--mode', 'magic', '--target', 'codex']);
    assert.equal(result.status, 2);
    assert.match(result.stderr, /MG_MCP_TOKEN|MASTERGO_API_TOKEN/);
  } finally { missing.cleanup(); }

  const configured = fixture();
  try {
    const result = configured.run(['configure', '--mode', 'magic', '--target', 'both', '--url', 'https://mastergo.com'], { MG_MCP_TOKEN: secret });
    assert.equal(result.status, 0, result.stderr);
    assert.doesNotMatch(result.stdout + result.stderr, new RegExp(secret));
    const adds = configured.calls().filter((call) => call.args[1] === 'add');
    assert.equal(adds.length, 2);
    for (const call of adds) {
      assert.ok(call.args.includes(`MG_MCP_TOKEN=${secret}`));
      assert.ok(call.args.includes('API_BASE_URL=https://mastergo.com'));
      assert.ok(call.args.includes('@mastergo/magic-mcp@latest'));
    }
  } finally { configured.cleanup(); }
});

test('拒绝命令行明文 Token 和未知参数', () => {
  const f = fixture();
  try {
    for (const args of [
      ['configure', '--mode', 'magic', '--target', 'codex', '--token', 'secret'],
      ['status', '--unknown'],
      ['configure', '--mode', 'vibe'],
    ]) {
      const result = f.run(args);
      assert.equal(result.status, 2, `${args.join(' ')}: ${result.stderr}`);
    }
  } finally { f.cleanup(); }
});

test('doctor 检出 Vibe 配置端口未监听', () => {
  const url = 'http://127.0.0.1:65530';
  const f = fixture({ codex: { mastergo: codexConfig(['-y', '@mastergo/vibe-mcp@latest', `--url=${url}`]) } });
  try {
    const result = f.run(['doctor', '--target', 'codex']);
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stdout, /65530/);
    assert.match(result.stdout, /未监听/);
  } finally { f.cleanup(); }
});

test('Claude 官方 --token 配置正确识别凭据、scope 和实际 health', () => {
  const token = 'mg_existing_secret';
  const f = fixture({ claude: { 'mastergo-magic-mcp': { scope: 'user', transport: { type: 'stdio', command: 'npx', args: ['-y', '@mastergo/magic-mcp', `--token=${token}`, '--url=https://mastergo.com'], env: {} } } } });
  try {
    const status = f.run(['status', '--target', 'claude']);
    assert.match(status.stdout, /claude magic installed package=official version=latest enabled=yes scope=user connection=connected credential=present url=https:\/\/mastergo\.com/);
    assert.doesNotMatch(status.stdout + status.stderr, new RegExp(token));
    const doctor = f.run(['doctor', '--target', 'claude', '--health'], { MCP_HEALTH_TIMEOUT_MS: '2000' });
    assert.match(doctor.stdout, /claude magic 凭据已配置/);
    assert.match(doctor.stdout, /claude magic initialize ok/);
    assert.doesNotMatch(doctor.stdout + doctor.stderr, new RegExp(token));
  } finally { f.cleanup(); }
});

test('status 区分 disabled、损坏配置与查询失败', () => {
  const disabled = fixture({ codex: { mastergo: { ...codexConfig(['-y', '@mastergo/vibe-mcp@latest', '--url=http://localhost:30678']), enabled: false }, 'mastergo-magic-mcp': '__INVALID_JSON__' } });
  try {
    const result = disabled.run(['status', '--target', 'codex']);
    assert.equal(result.status, 1);
    assert.match(result.stdout, /codex vibe installed package=official version=latest enabled=no/);
    assert.match(result.stdout, /codex magic invalid/);
  } finally { disabled.cleanup(); }

  const failed = fixture();
  try {
    const result = failed.run(['status', '--target', 'claude'], { FAKE_QUERY_FAIL_HOST: 'claude' });
    assert.match(result.stdout, /claude vibe query-failed/);
    assert.match(result.stdout, /claude magic query-failed/);
  } finally { failed.cleanup(); }
});

test('force 按 Claude 真实 scope 删除，配置文件权限收紧', () => {
  const f = fixture({ claude: { mastergo: { scope: 'local', transport: { type: 'stdio', command: 'npx', args: ['other-package'], env: {} } } } });
  try {
    const config = path.join(f.home, '.claude.json');
    fs.writeFileSync(config, '{}\n', { mode: 0o644 });
    const result = f.run(['configure', '--mode', 'vibe', '--target', 'claude', '--force']);
    assert.equal(result.status, 0, result.stderr);
    const remove = f.calls().find((call) => call.args[1] === 'remove');
    assert.deepEqual(remove.args, ['mcp', 'remove', '--scope', 'local', 'mastergo']);
    assert.equal(fs.statSync(config).mode & 0o777, 0o600);
  } finally { f.cleanup(); }
});

test('doctor 报告固定配置版本漂移但不自动升级', () => {
  const f = fixture({ codex: { mastergo: codexConfig(['-y', '@mastergo/vibe-mcp@1.0.1', '--url=http://127.0.0.1:65530']) } });
  try {
    const result = f.run(['doctor', '--target', 'codex']);
    assert.match(result.stdout, /版本漂移 configured=1\.0\.1 latest=1\.0\.28（不自动升级）/);
    assert.equal(f.calls().some((call) => call.args[1] === 'add'), false);
  } finally { f.cleanup(); }
});

test('损坏配置即使 force 也停止，不猜测重建', () => {
  const f = fixture({ codex: { mastergo: '__INVALID_JSON__' } });
  try {
    const result = f.run(['configure', '--mode', 'vibe', '--target', 'codex', '--force']);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /配置损坏/);
    assert.equal(f.calls().some((call) => ['remove', 'add'].includes(call.args[1])), false);
  } finally { f.cleanup(); }
});

test('包名藏在非 npx 命令参数中不算官方配置', () => {
  const f = fixture({ codex: { mastergo: { enabled: true, transport: { type: 'stdio', command: 'evil-runner', args: ['@mastergo/vibe-mcp@latest', '--url=http://localhost:30678'], env: {} } } } });
  try {
    const status = f.run(['status', '--target', 'codex']);
    assert.match(status.stdout, /codex vibe installed package=other/);
    const configure = f.run(['configure', '--mode', 'vibe', '--target', 'codex']);
    assert.equal(configure.status, 1);
    assert.match(configure.stderr, /配置冲突/);
    assert.equal(f.calls().some((call) => call.args[1] === 'add'), false);
  } finally { f.cleanup(); }
});

test('Magic Token 等值时幂等，轮换必须显式 force', () => {
  const oldToken = 'mg_old_secret';
  const newToken = 'mg_new_secret';
  const state = { codex: { 'mastergo-magic-mcp': codexConfig(['-y', '@mastergo/magic-mcp@latest'], { MG_MCP_TOKEN: oldToken, API_BASE_URL: 'https://mastergo.com' }) } };

  const same = fixture(state);
  try {
    const result = same.run(['configure', '--mode', 'magic', '--target', 'codex'], { MG_MCP_TOKEN: oldToken });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /已是目标配置/);
    assert.equal(same.calls().some((call) => ['remove', 'add'].includes(call.args[1])), false);
  } finally { same.cleanup(); }

  const changed = fixture(state);
  try {
    const result = changed.run(['configure', '--mode', 'magic', '--target', 'codex'], { MG_MCP_TOKEN: newToken });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /配置冲突/);
    assert.doesNotMatch(result.stdout + result.stderr, new RegExp(`${oldToken}|${newToken}`));
    assert.equal(changed.calls().some((call) => ['remove', 'add'].includes(call.args[1])), false);
  } finally { changed.cleanup(); }

  const forced = fixture(state);
  try {
    const result = forced.run(['configure', '--mode', 'magic', '--target', 'codex', '--force'], { MG_MCP_TOKEN: newToken });
    assert.equal(result.status, 0, result.stderr);
    const mutation = forced.calls().filter((call) => ['remove', 'add'].includes(call.args[1]));
    assert.deepEqual(mutation.map((call) => call.args[1]), ['remove', 'add']);
    assert.ok(mutation[1].args.includes(`MG_MCP_TOKEN=${newToken}`));
    assert.doesNotMatch(result.stdout + result.stderr, new RegExp(`${oldToken}|${newToken}`));
  } finally { forced.cleanup(); }
});
