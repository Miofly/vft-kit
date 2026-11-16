#!/usr/bin/env node
// Local-only generation. Never deploys, downloads code, or replaces an existing directory.
import fs from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import { randomUUID, createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';

export const UPSTREAM = Object.freeze({
  commit: 'e70a3a7f6923811b0e168339662e60d00bee44f0',
  sha256: 'e87c3165ff1c985b15b97f9e1fb88331c1be524ad3b8df71e643ced87dae3cbd',
});
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DEFAULT_ID_B64 = 'ZWM4NzJkOGYtNzJiMC00YTA0LWI2MTItMDMyN2Q4NWUxOGVk';
const fail = message => { throw new Error(message); };
const absolute = value => typeof value === 'string' && path.isAbsolute(value)
  ? value : fail('需要绝对路径');
function host(value) {
  if (typeof value !== 'string' || value.length > 253 || !value.includes('.') || net.isIP(value)
    || !value.split('.').every(s => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i.test(s))) {
    fail('host 必须是纯域名，不带协议、端口或路径');
  }
  if (/(^|\.)(example\.(com|net|org)|invalid|test|localhost)$/i.test(value)) fail('拒绝部署示例域名');
  return value.toLowerCase();
}
function address(value) {
  if (net.isIP(value)) return value;
  return host(value);
}
export function validate(input) {
  const c = { ...input };
  c.host = host(c.host);
  c.entry = address(c.entry || c.host);
  if (!/^[0-9a-f]{32}$/i.test(c.account || '')) fail('account 必须是 32 位 Account ID');
  if (!/^[a-z][a-z0-9-]{0,62}$/.test(c.name || '')) fail('Worker 名称只允许小写字母、数字和连字符');
  if (!UUID.test(c.uuid || '') || c.uuid.toLowerCase() === Buffer.from(DEFAULT_ID_B64, 'base64').toString()) fail('需要私有随机 UUID v4');
  if (typeof c.paddr !== 'string') fail('paddr 必须是字符串，首次可留空');
  if (c.paddr) address(c.paddr); // First recipe uses port 443 only; no URL or embedded credential.
  return c;
}
export function render(input) {
  const c = validate(input);
  return {
    'connection.json': c,
    'worker-secrets.json': { ID: c.uuid, PADDR: c.paddr },
    'wrangler.json': {
      name: c.name, account_id: c.account, main: 'worker.mjs',
      compatibility_date: '2026-11-01', workers_dev: false, preview_urls: false,
      routes: [{ pattern: c.host, custom_domain: true }],
      vars: { PROT_TYPE: 'vless' },
      // Fill from the namespace created for this new Worker, not another application's KV.
      kv_namespaces: [{ binding: 'amclubs', id: 'REPLACE_WITH_NEW_KV_NAMESPACE_ID' }],
    },
    // JSON is valid YAML. mihomo reads this as a local configuration file.
    'clash.yaml': {
      'mixed-port': 7890, 'allow-lan': false, 'bind-address': '127.0.0.1',
      mode: 'rule', 'log-level': 'warning', ipv6: false,
      proxies: [{ name: 'CF-VLESS', type: 'vless', server: c.entry, port: 443,
        uuid: c.uuid, tls: true, servername: c.host, 'skip-cert-verify': false,
        'client-fingerprint': 'chrome', network: 'ws', udp: false,
        'ws-opts': { path: '/?PROT_TYPE=vless', headers: { Host: c.host } } }],
      'proxy-groups': [{ name: 'PROXY', type: 'select', proxies: ['CF-VLESS', 'DIRECT'] }],
      rules: ['IP-CIDR,127.0.0.0/8,DIRECT,no-resolve',
        'IP-CIDR,10.0.0.0/8,DIRECT,no-resolve', 'IP-CIDR,172.16.0.0/12,DIRECT,no-resolve', // audit-public: allow — standard RFC1918 ranges, not a personal network
        'IP-CIDR,192.168.0.0/16,DIRECT,no-resolve', 'MATCH,PROXY'], // audit-public: allow — standard RFC1918 range
    },
  };
}
function createDirectory(out) {
  absolute(out);
  fs.mkdirSync(out, { mode: 0o700 }); // EEXIST is intentional: never replace a working profile.
}
function write(file, data) {
  fs.writeFileSync(file, typeof data === 'string' ? data : JSON.stringify(data, null, 2) + '\n',
    { flag: 'wx', mode: 0o600 });
}
export function generate(input, out) {
  const files = render(input);
  createDirectory(out);
  for (const [name, data] of Object.entries(files)) write(path.join(out, name), data);
}
export function prepare(input, source, out) {
  const c = validate(input);
  const bytes = fs.readFileSync(absolute(source));
  if (createHash('sha256').update(bytes).digest('hex') !== UPSTREAM.sha256) fail('上游 SHA-256 不符，拒绝准备；不要绕过校验');
  const code = bytes.toString('utf8');
  const marker = `let id = atob('${DEFAULT_ID_B64}');`;
  if (code.split(marker).length !== 2) fail('上游凭据初始化结构变化，需人工复核');
  const logMarker = "enableLog = url.searchParams.get('ENABLE_LOG') || ENABLE_LOG || enableLog;";
  if (code.split(logMarker).length !== 2) fail('上游日志开关结构变化，需人工复核');
  const patched = code.replace(marker, `let id = ${JSON.stringify(c.uuid)};`)
    .replace(logMarker, 'enableLog = false; // Do not log UUIDs or destination metadata.');
  // Refuse startup with missing ID or stale KV. Secret rotation must not silently fall back.
  const wrapper = `import upstream from './upstream.mjs';
export default {
  async fetch(request, env, ctx) {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(env.ID || '')) {
      return new Response('Service not configured', {status: 503});
    }
    if (!env.amclubs) return new Response('KV not configured', {status: 503});
    try {
      // This pinned upstream can store an ID overriding env.ID. Isolate KV per Worker.
      const value = await env.amclubs.get('KV_CONFIG', {type: 'json'});
      if (value?.kv_id && value.kv_id.toLowerCase() !== env.ID.toLowerCase()) {
        return new Response('KV identity mismatch', {status: 503});
      }
    } catch {
      return new Response('KV unavailable', {status: 503});
    }
    return upstream.fetch(request, { ...env, PADDR: env.PADDR ?? '' }, ctx);
  }
};
`;
  createDirectory(out);
  write(path.join(out, 'upstream.mjs'), patched);
  write(path.join(out, 'worker.mjs'), wrapper);
  write(path.join(out, 'source-lock.json'), { ...UPSTREAM, patched: true });
}
export function check(configFile, profileFile) {
  const c = validate(JSON.parse(fs.readFileSync(absolute(configFile), 'utf8')));
  const profile = JSON.parse(fs.readFileSync(absolute(profileFile), 'utf8'));
  if (profile['allow-lan'] !== false || profile['bind-address'] !== '127.0.0.1'
    || profile['external-controller'] || profile['external-controller-tls']
    || profile['external-controller-unix'] || profile['external-controller-pipe']) fail('本配方只接受 loopback 且无 controller 的独立配置');
  if (!Array.isArray(profile.proxies) || !profile.proxies.length) fail('没有节点');
  for (const p of profile.proxies) {
    if (p.type !== 'vless' || p.uuid !== c.uuid || p.tls !== true || p.port !== 443
      || p.servername !== c.host || p['ws-opts']?.headers?.Host !== c.host
      || p['ws-opts']?.path !== '/?PROT_TYPE=vless' || p.network !== 'ws'
      || p['skip-cert-verify'] !== false || p.udp !== false
      || p['client-fingerprint'] !== 'chrome') fail('节点不符合本配方的协议/UUID/TLS/SNI/Host/path');
    address(p.server);
  }
  return { status: 'PASS', nodes: profile.proxies.length };
}
function options(args) {
  const result = {};
  for (let i = 0; i < args.length; i += 2) {
    const key = args[i];
    if (!key?.startsWith('--') || args[i + 1] === undefined || Object.hasOwn(result, key.slice(2))) fail('参数必须成对且不能重复，见 --help');
    result[key.slice(2)] = args[i + 1];
  }
  return result;
}
function main(args) {
  const [cmd, ...rest] = args;
  if (!cmd || cmd === '--help') {
    console.log(`本地生成器（Node.js 22+，不联网、不部署、不修改现用配置）
init --host DOMAIN --account ACCOUNT_ID --out ABS_NEW_DIR [--name personal-vless] [--entry DOMAIN_OR_IP] [--paddr HOST_OR_IP]
render --config ABS_CONNECTION_JSON --out ABS_NEW_DIR
prepare-worker --config ABS_CONNECTION_JSON --source ABS_UPSTREAM_JS --out ABS_NEW_DIR
check --config ABS_CONNECTION_JSON --profile ABS_GENERATED_CLASH_YAML
所有输出目录必须尚不存在；密钥仅写入文件，标准输出不含密钥。
check 只检查本工具的 JSON 格式 YAML，不解析外部 YAML 订阅。外部订阅须用 mihomo -t 和人工字段校验。`);
    return;
  }
  const o = options(rest);
  const allowed = { init: ['host','account','out','name','entry','paddr'], render: ['config','out'],
    'prepare-worker': ['config','source','out'], check: ['config','profile'] }[cmd];
  if (!allowed || Object.keys(o).some(k => !allowed.includes(k))) fail('未知命令或参数，见 --help');
  if (cmd === 'init') generate({ host: o.host, account: o.account, name: o.name || 'personal-vless',
    entry: o.entry, paddr: o.paddr || '', uuid: randomUUID() }, o.out);
  else {
    const c = JSON.parse(fs.readFileSync(absolute(o.config), 'utf8'));
    if (cmd === 'render') generate(c, o.out);
    if (cmd === 'prepare-worker') prepare(c, o.source, o.out);
    if (cmd === 'check') { console.log(JSON.stringify(check(o.config, o.profile))); return; }
  }
  console.log(JSON.stringify({ status: 'CREATED', directory: o.out }));
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try { main(process.argv.slice(2)); }
  catch (error) { console.error(`FAIL: ${error.code || error.message}`); process.exitCode = 1; }
}
