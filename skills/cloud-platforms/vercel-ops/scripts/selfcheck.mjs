#!/usr/bin/env node
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { VercelConfig, VercelAPI, commands, parseArgs, parseEnv, timestamp } from './vercel-ops.js';

const dir = await mkdtemp(join(tmpdir(), 'vercel-ops-check-'));
const oldFetch = globalThis.fetch;
const oldToken = process.env.VERCEL_TOKEN;
const oldLog = console.log;
const oldError = console.error;
const output = [], diagnostic = [], calls = [];
let response = {}, failed = false;
const mockFetch = async (url, options) => {
  calls.push({ url: new URL(url), ...options, body: options.body && JSON.parse(options.body) });
  if (failed) throw new TypeError('network failed');
  const data = options.method === 'GET' && /\/projects\/p$/.test(new URL(url).pathname) ?
    { name: 'example', link: { type: 'github', repoId: 42, productionBranch: 'main' } } : response;
  return new Response(JSON.stringify(data), { status: 200 });
};
try {
  console.log = (...args) => output.push(args.join(' '));
  console.error = (...args) => diagnostic.push(args.join(' '));
  globalThis.fetch = mockFetch;
  const configFile = join(dir, 'config.json');
  await writeFile(configFile, JSON.stringify({ default: { access_token: 'file-token', team_id: 'team_test' } }));
  process.env.VERCEL_TOKEN = 'env-token';
  const config = new VercelConfig();
  await config.load({ config: configFile });
  assert.equal(config.token, 'env-token');
  assert.equal(config.teamId, 'team_test');
  await assert.rejects(config.load({ config: configFile, profile: 'typo' }), /profile not found/);
  await assert.rejects(config.load({ config: join(dir, 'missing') }), /ENOENT/);
  await config.load({ config: configFile });
  const api = new VercelAPI(config);
  config.verbose = true;
  await api.post('/v10/projects/p/env', { value: 'sensitive-env-value' });
  assert.equal(calls.at(-1).url.searchParams.get('teamId'), 'team_test');
  assert.equal(calls.at(-1).headers.Authorization, 'Bearer env-token');
  assert.equal(calls.at(-1).redirect, 'error');
  assert(!diagnostic.join('').includes('sensitive-env-value'));
  assert(!diagnostic.join('').includes('env-token'));
  for (const endpoint of ['//attacker.invalid', '/\\attacker.invalid', 'https://attacker.invalid']) {
    await assert.rejects(api.get(endpoint), /endpoint/);
  }
  assert.deepEqual(parseArgs(['--json', 'projects', 'list', '--limit=2'])._, ['projects', 'list']);
  assert.equal(parseArgs(['env', 'add', 'p', '--value=']).value, '');
  assert.throws(() => parseArgs(['--profile']), /requires a value/);
  assert.throws(() => parseArgs(['--typo']), /Unknown option/);
  assert(timestamp('1h') < Date.now());
  assert.throws(() => timestamp('invalid'), /Time must/);
  output.length = 0;
  response = { ok: true };
  await commands.api(api, parseArgs(['api', 'GET', '/v9/projects', '--query', 'search=a%3Db%26c&limit=2']));
  assert.equal(calls.at(-1).url.searchParams.get('search'), 'a=b&c');
  assert.deepEqual(JSON.parse(output.join('\n')), { ok: true });
  failed = true;
  const before = calls.length;
  await assert.rejects(api.post('/v13/deployments', { name: 'example' }), /check remote state/);
  assert.equal(calls.length, before + 1, 'uncertain mutations must not retry');
  failed = false;
  globalThis.fetch = async () => new Response(null, { status: 204 });
  assert.equal(await api.delete('/v9/projects/p'), null);
  globalThis.fetch = mockFetch;

  assert.deepEqual(parseEnv(' # comment\nexport A="x=y#z"\nEMPTY=\nB=foo # comment'), [['A', 'x=y#z'], ['EMPTY', ''], ['B', 'foo']]);
  assert.throws(() => parseEnv('INVALID'), /line 1/);
  assert.throws(() => parseEnv('KEY="unfinished'), /multiline/);
  const envFile = join(dir, 'env.json');
  await writeFile(envFile, JSON.stringify({ MULTILINE: 'a\nb', EMPTY: '' }));
  response = {};
  await commands.env(api, parseArgs(['env', 'import', 'p', '--file', envFile, '--json']));
  assert.equal(calls.at(-1).url.searchParams.get('upsert'), 'true');
  assert.equal(calls.at(-1).body.value, '');
  response = { envs: [{ key: 'KEY', value: 'private', target: ['production'] }] };
  output.length = 0;
  await commands.env(api, parseArgs(['env', 'list', 'p', '--json']));
  assert(!output.join('').includes('private'));
  globalThis.fetch = async () => new Response('{}', { status: 403 });
  await assert.rejects(commands.env(api, parseArgs(['env', 'import', 'p', '--file', envFile])), /HTTP 403/);
  globalThis.fetch = mockFetch;

  output.length = 0;
  response = { id: 'dpl_test', readyState: 'READY' };
  await commands.deployments(api, parseArgs(['--json', 'deployments', 'create', 'p']));
  assert.equal(JSON.parse(output.join('\n')).id, 'dpl_test');
  assert.equal(calls.at(-1).body.target, undefined, 'default must be preview');
  assert.equal(calls.at(-1).body.gitSource.repoId, 42);
  output.length = 0;
  await commands.deployments(api, parseArgs(['deployments', 'wait', 'dpl_test', '--json']));
  assert.equal(JSON.parse(output.join('\n')).readyState, 'READY');
  response = { readyState: 'ERROR' };
  await assert.rejects(commands.deployments(api, parseArgs(['deployments', 'wait', 'dpl_test'])), /ERROR/);
  await assert.rejects(commands.domains(api, parseArgs(['domains', 'remove', 'example.com'])), /--project/);
  await commands.domains(api, parseArgs(['domains', 'remove', 'example.com', '--project', 'p', '--json']));
  assert.equal(calls.at(-1).url.pathname, '/v9/projects/p/domains/example.com');
  assert.equal(calls.at(-1).method, 'DELETE');
  await commands.domains(api, parseArgs(['domains', 'verify', 'example.com', '--project', 'p', '--json']));
  assert.equal(calls.at(-1).method, 'POST');
  assert.equal(calls.at(-1).url.pathname, '/v9/projects/p/domains/example.com/verify');
  await commands['edge-config'](api, parseArgs(['edge-config', 'set', 'ecfg_test', '--key', 'flag', '--value', 'false']));
  assert.equal(calls.at(-1).url.pathname, '/v1/global-config/ecfg_test/items');
  assert.deepEqual(calls.at(-1).body, { items: [{ operation: 'upsert', key: 'flag', value: false }] });
  const secretFile = join(dir, 'webhook-secret');
  response = { id: 'hook_test', secret: 'signing-secret' };
  output.length = 0;
  await commands.webhooks(api, parseArgs(['webhooks', 'create', '--url', 'https://example.com/hook', '--events', 'deployment.created', '--secret-file', secretFile]));
  assert(!output.join('').includes('signing-secret'));
  assert.equal(await readFile(secretFile, 'utf8'), 'signing-secret');
  assert.equal((await stat(secretFile)).mode & 0o777, 0o600);
  const beforeDuplicate = calls.length;
  await assert.rejects(commands.webhooks(api, parseArgs(['webhooks', 'create', '--url', 'https://example.com/hook', '--events', 'deployment.created', '--secret-file', secretFile])), /EEXIST/);
  assert.equal(calls.length, beforeDuplicate);

  const script = fileURLToPath(new URL('./vercel-ops.js', import.meta.url));
  for (const command of [['--help'], ['blob', 'list'], ['--profile']]) {
    const result = spawnSync(process.execPath, [script, ...command], { encoding: 'utf8' });
    assert.equal(result.status, command[0] === '--help' ? 0 : 1);
  }
} finally {
  globalThis.fetch = oldFetch;
  console.log = oldLog;
  console.error = oldError;
  if (oldToken === undefined) delete process.env.VERCEL_TOKEN;
  else process.env.VERCEL_TOKEN = oldToken;
  await rm(dir, { recursive: true, force: true });
}
console.log('PASS: config, CLI parsing, JSON, request safety, env import, deployments, domains, Edge Config, webhooks (offline)');
