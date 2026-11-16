import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { validate, render, generate, prepare, check, UPSTREAM } from './config.mjs';
import { proxyAddress, parseResponse, evaluate } from './probe.mjs';

// Tests use private temporary directories; no Cloudflare requests or existing client mutations.
const temp = fs.mkdtempSync(path.join(process.env.CF_VLESS_TEST_ROOT || os.tmpdir(), 'cf-vless-'));
const input = { host: 'edge.unit-check.net', entry: 'edge.unit-check.net', account: 'a'.repeat(32),
  name: 'test-vless', uuid: randomUUID(), paddr: '' };
process.on('exit', () => fs.rmSync(temp, { recursive: true, force: true }));

test('renders VLESS + WS + verified TLS and no exposed controller', () => {
  const files = render(input);
  const c = files['clash.yaml'];
  assert.equal(c.proxies[0].type, 'vless');
  assert.equal(c.proxies[0].servername, input.host);
  assert.equal(c.proxies[0]['ws-opts'].headers.Host, input.host);
  assert.equal(c.proxies[0]['skip-cert-verify'], false);
  assert.equal(c.proxies[0].udp, false);
  assert.equal(c['allow-lan'], false);
  assert.equal(c['external-controller'], undefined);
  assert.equal(files['worker-secrets.json'].ID, input.uuid);
  assert.equal(files['worker-secrets.json'].PADDR, '');
  assert.equal(files['wrangler.json'].vars.ENABLE_LOG, undefined);
  assert.equal(files['wrangler.json'].kv_namespaces[0].binding, 'amclubs');
});

test('rejects placeholders, injected hosts, malformed IDs and upstream default', () => {
  for (const h of ['example.com','edge.example.com','https://x.net','x.net:443','x.net/a', 'x.net\nfoo','-a.net','x..net','127.0.0.1']) {
    assert.throws(() => validate({ ...input, host: h }), h);
  }
  assert.throws(() => validate({ ...input, account: 'zone' }));
  assert.throws(() => validate({ ...input, name: '../../other' }));
  assert.throws(() => validate({ ...input, uuid: 'ec872d8f-72b0-4a04-b612-0327d85e18ed' }));
  assert.throws(() => validate({ ...input, paddr: 'https://proxy.net' }));
  assert.throws(() => validate({ ...input, paddr: 'proxy.net:443' }));
});

test('supports IPv4/IPv6 entry while preserving domain Host and SNI', () => {
  for (const entry of ['1.1.1.1','2606:4700::1111']) {
    const p = render({ ...input, entry })['clash.yaml'].proxies[0];
    assert.equal(p.server, entry);
    assert.equal(p.servername, input.host);
  }
});

test('never overwrites a directory and restricts POSIX file permissions', () => {
  const out = path.join(temp, 'generated');
  generate(input, out);
  assert.throws(() => generate(input, out), /EEXIST/);
  assert.throws(() => generate(input, 'relative-dir'));
  if (process.platform !== 'win32') assert.equal(fs.statSync(path.join(out, 'clash.yaml')).mode & 0o777, 0o600);
  assert.equal(check(path.join(out, 'connection.json'), path.join(out, 'clash.yaml')).status, 'PASS');
});

test('rejects broken protocol/SNI/Host/UUID/path/security profile fields', () => {
  const config = path.join(temp, 'generated/connection.json');
  const changes = [p => p.proxies[0].servername = 'undefined.xyz',
    p => p.proxies[0]['ws-opts'].headers.Host = 'wrong.net',
    p => p.proxies[0].type = 'trojan', p => p.proxies[0].uuid = randomUUID(),
    p => p.proxies[0]['skip-cert-verify'] = true,
    p => p.proxies[0]['client-fingerprint'] = 'randomized',
    p => p.proxies[0]['ws-opts'].path += '&PADDR=unknown.net',
    p => p.proxies = [], p => p['allow-lan'] = true,
    p => p['external-controller'] = '0.0.0.0:9090'];
  for (const [i, change] of changes.entries()) {
    const p = render(input)['clash.yaml']; change(p);
    const file = path.join(temp, `bad-${i}.json`);
    fs.writeFileSync(file, JSON.stringify(p));
    assert.throws(() => check(config, file));
  }
});

test('changed upstream hash fails without creating prepared output', () => {
  const file = path.join(temp, 'untrusted.js');
  fs.writeFileSync(file, 'export default {};');
  const out = path.join(temp, 'rejected');
  assert.throws(() => prepare(input, file, out), /SHA-256/);
  assert.equal(fs.existsSync(out), false);
});

test('CLI prints no credential and fails unknown flags', () => {
  const script = new URL('./config.mjs', import.meta.url);
  const out = path.join(temp, 'cli');
  const args = [script.pathname, 'init', '--host', input.host, '--account', input.account, '--out', out];
  const r = spawnSync(process.execPath, args, { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  const c = JSON.parse(fs.readFileSync(path.join(out, 'connection.json'), 'utf8'));
  assert.equal((r.stdout + r.stderr).includes(c.uuid), false);
  const bad = spawnSync(process.execPath, [...args, '--force', 'yes'], { encoding: 'utf8' });
  assert.equal(bad.status, 1);
});

test('probe accepts only explicit loopback HTTP proxy', () => {
  assert.equal(proxyAddress('http://127.0.0.1:7890'), 'http://127.0.0.1:7890/');
  for (const p of ['http://example.com:7890','socks5://127.0.0.1:7890', 'http://127.0.0.1',
    'http://u:p@localhost:7890','http://localhost:7890/path']) assert.throws(() => proxyAddress(p));
});

test('probe does not confuse HTML or error JSON with valid trace/exit', () => {
  const trace = 'https://www.cloudflare.com/cdn-cgi/trace';
  assert.equal(evaluate(trace, { status: 200, body: '<html>blocked</html>' }).ok, false);
  assert.equal(evaluate(trace, { status: 200, body: 'ip=1.1.1.1\nloc=JP\ncolo=NRT\n' }).ok, true);
  assert.equal(evaluate('https://ipinfo.io/json', { status: 200, body: '{"error":"quota"}' }).ok, false);
  assert.equal(evaluate('https://www.google.com/generate_204', { status: 200, body: '' }).ok, false);
  assert.equal(parseResponse('body\n__CF_PROBE__204 0.25').seconds, 0.25);
  assert.throws(() => parseResponse('incomplete'));
});

test('probe CLI completes nine explicit-proxy checks and refuses report overwrite', { skip: process.platform === 'win32' }, () => {
  const bin = path.join(temp, 'fake-bin'); fs.mkdirSync(bin);
  fs.writeFileSync(path.join(bin, 'curl'), `#!${process.execPath}
const args = process.argv.slice(2);
if (args[args.indexOf('--proxy') + 1] !== 'http://127.0.0.1:7890/' || args[args.indexOf('--noproxy') + 1] !== '') process.exit(4);
const url = args.at(-1);
let body = '', code = 204;
if (url.includes('cloudflare.com')) {body = 'ip=1.1.1.1\\nloc=JP\\ncolo=NRT\\n'; code = 200;}
if (url.includes('ipinfo.io')) {body = JSON.stringify({ip:'1.1.1.1',country:'JP'}); code = 200;}
console.log(body + '\\n__CF_PROBE__' + code + ' 0.2');
`, { mode: 0o700 });
  const out = path.join(temp, 'probe.json');
  const args = [new URL('./probe.mjs', import.meta.url).pathname, '--proxy', 'http://127.0.0.1:7890', '--out', out];
  const env = { ...process.env, PATH: bin + path.delimiter + process.env.PATH };
  const r = spawnSync(process.execPath, args, { env, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  const report = JSON.parse(fs.readFileSync(out, 'utf8'));
  assert.equal(report.status, 'PASS');
  assert.equal(report.rows.length, 9);
  assert.equal(fs.readFileSync(out, 'utf8').includes('1.1.1.1'), false);
  assert.equal(spawnSync(process.execPath, args, { env }).status, 1);
});

test('fixed upstream preparation + fail-closed wrapper', { skip: !process.env.CF_VLESS_UPSTREAM }, async () => {
  const out = path.join(temp, 'prepared');
  prepare(input, process.env.CF_VLESS_UPSTREAM, out);
  const lock = JSON.parse(fs.readFileSync(path.join(out, 'source-lock.json'), 'utf8'));
  assert.equal(lock.commit, UPSTREAM.commit);
  const s = fs.readFileSync(path.join(out, 'upstream.mjs'), 'utf8');
  assert.ok(s.includes(`let id = "${input.uuid}";`));
  assert.ok(s.includes('enableLog = false; // Do not log UUIDs'));
  let wrapper = fs.readFileSync(path.join(out, 'worker.mjs'), 'utf8');
  wrapper = wrapper.replace("import upstream from './upstream.mjs';", "const upstream = {fetch: (req, env) => new Response(env.PADDR === '' ? 'empty' : 'configured')};");
  const { default: worker } = await import('data:text/javascript;base64,' + Buffer.from(wrapper).toString('base64'));
  const req = new Request('https://edge.unit-check.net');
  assert.equal((await worker.fetch(req, {}, {})).status, 503);
  assert.equal((await worker.fetch(req, { ID: input.uuid }, {})).status, 503);
  const env = { ID: input.uuid, amclubs: { get: async () => null } };
  assert.equal(await (await worker.fetch(req, env, {})).text(), 'empty');
  assert.equal((await worker.fetch(req, { ...env, amclubs: { get: async () => ({ kv_id: randomUUID() }) } }, {})).status, 503);
  assert.equal((await worker.fetch(req, { ...env, amclubs: { get: async () => { throw new Error('unavailable'); } } }, {})).status, 503);
});
