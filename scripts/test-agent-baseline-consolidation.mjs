#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import http from 'node:http';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const plugin = path.join(root, 'plugins/vft-kit');
const base = path.join(plugin, 'skills/agent-ops/agent-baseline');
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'catalog/skills.json'), 'utf8'));
const skills = catalog.categories.flatMap((category) => category.skills);
assert(skills.includes('agent-baseline'));
for (const old of ['cc-baseline', 'codex-baseline', 'cc-backup-restore', 'cc-switch-add-provider']) {
  assert(!skills.includes(old));
  assert(!catalog.invocationPolicy.explicitOnly.includes(old));
  assert(!fs.existsSync(path.join(plugin, 'skills/agent-ops', old)));
  assert(!fs.existsSync(path.join(plugin, 'commands', old + '.md')));
}
for (const route of ['claude-code', 'codex']) {
  assert(fs.existsSync(path.join(base, route, 'scripts/run.sh')));
  assert(fs.existsSync(path.join(base, route, 'scripts/check.sh')));
  const reference = fs.readFileSync(path.join(base, 'references', route + '.md'), 'utf8');
  assert(reference.includes('agent-baseline/' + route + '/scripts/run.sh'));
  for (const file of [path.join(base, 'SKILL.md'), path.join(base, 'references', route + '.md')]) {
    const text = fs.readFileSync(file, 'utf8');
    for (const [, link] of text.matchAll(/\]\(([^)]+)\)/g)) {
      if (!/^(https?:|#)/.test(link)) assert(fs.existsSync(path.resolve(path.dirname(file), link)), 'Missing link: ' + link);
    }
  }
}

for (const route of ['backup', 'cc-switch']) {
  const router = fs.readFileSync(path.join(base, 'SKILL.md'), 'utf8');
  assert(router.includes('references/' + route + '.md'));
  const file = path.join(base, 'references', route + '.md');
  for (const [, link] of fs.readFileSync(file, 'utf8').matchAll(/\]\(([^)]+)\)/g)) {
    if (!/^(https?:|#)/.test(link)) assert(fs.existsSync(path.resolve(path.dirname(file), link)), 'Missing link: ' + link);
  }
}
const provider = spawnSync('python3', [path.join(base, 'cc-switch/scripts/upsert_provider.py'), '--self-test'], { encoding: 'utf8' });
assert.equal(provider.status, 0, provider.stdout + provider.stderr);
assert(provider.stdout.includes('SELF_TEST=PASS'));
const backupTemp = fs.mkdtempSync(path.join(os.tmpdir(), 'vft-backup-'));
try {
  const source = path.join(backupTemp, 'source');
  const target = path.join(backupTemp, 'target');
  const sourceClaude = path.join(source, '.claude');
  const targetClaude = path.join(target, '.claude');
  fs.mkdirSync(path.join(sourceClaude, 'plugins'), { recursive: true });
  fs.mkdirSync(targetClaude, { recursive: true });
  fs.writeFileSync(path.join(sourceClaude, 'CLAUDE.md'), '@RULES.md\n');
  fs.writeFileSync(path.join(sourceClaude, 'RULES.md'), 'test rules\n');
  fs.writeFileSync(path.join(sourceClaude, 'settings.json'), JSON.stringify({ env: { TOKEN: 'old-secret' }, oauthToken: 'old-token', permissions: { defaultMode: 'default' } }));
  fs.writeFileSync(path.join(sourceClaude, 'plugins/known_marketplaces.json'), '{}');
  const backupRoot = path.join(backupTemp, 'backups');
  const backup = spawnSync('bash', [path.join(base, 'backup/scripts/cc-backup.sh')], { env: { ...process.env, HOME: source, CC_BACKUP_ROOT: backupRoot }, encoding: 'utf8' });
  assert.equal(backup.status, 0, backup.stdout + backup.stderr);
  const saved = path.join(backupRoot, fs.readdirSync(backupRoot)[0]);
  assert(fs.existsSync(path.join(saved, 'MANIFEST.txt')));
  assert(fs.existsSync(path.join(saved, 'plugins/known_marketplaces.json')));
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(saved, 'settings.json'), 'utf8')), { permissions: { defaultMode: 'default' } });
  assert.equal(fs.readFileSync(path.join(saved, 'cc-restore.sh'), 'utf8'), fs.readFileSync(path.join(base, 'backup/scripts/cc-restore.sh'), 'utf8'));
  const live = { env: { TOKEN: 'live-secret' }, oauthToken: 'live-token', keep: true };
  fs.writeFileSync(path.join(targetClaude, 'settings.json'), JSON.stringify(live));
  const restore = spawnSync('bash', [path.join(saved, 'cc-restore.sh'), '-y'], { env: { ...process.env, HOME: target }, encoding: 'utf8' });
  assert.equal(restore.status, 0, restore.stdout + restore.stderr);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(targetClaude, 'settings.json'), 'utf8')), { ...live, permissions: { defaultMode: 'default' } });
  assert.equal(fs.readFileSync(path.join(targetClaude, 'RULES.md'), 'utf8'), 'test rules\n');
  const rollback = fs.readdirSync(targetClaude).find((name) => name.startsWith('settings.json.pre-restore-'));
  assert(rollback);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(targetClaude, rollback), 'utf8')), live);
} finally { fs.rmSync(backupTemp, { recursive: true, force: true }); }

const quality = path.join(plugin, 'skills/dev-workflow/fe-quality-ops');
assert(skills.includes('fe-quality-ops'));
for (const old of ['fe-auto-test', 'fe-lint-fix']) {
  assert(!skills.includes(old));
  assert(!fs.existsSync(path.join(plugin, 'skills/dev-workflow', old)));
}
for (const name of ['SKILL.md', 'references/lint.md', 'references/browser.md']) {
  const file = path.join(quality, name);
  const content = fs.readFileSync(file, 'utf8');
  for (const [, link] of content.matchAll(/\]\(([^)]+)\)/g)) {
    if (!/^(https?:|#)/.test(link)) assert(fs.existsSync(path.resolve(path.dirname(file), link)), 'Missing link: ' + link);
  }
}
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'vft-quality-'));
try {
  const bin = path.join(temp, 'bin');
  fs.mkdirSync(bin);
  const trace = path.join(temp, 'trace');
  fs.writeFileSync(path.join(temp, 'package.json'), JSON.stringify({
    packageManager: 'npm@10', scripts: { 'lint:prettier': 'mock', 'lint:stylelint': 'mock', 'lint:eslint': 'mock', 'type-check': 'mock' },
  }));
  fs.writeFileSync(path.join(temp, 'package-lock.json'), '{}');
  fs.writeFileSync(path.join(bin, 'npm'), '#!/bin/sh\nprintf "%s\\n" "$*" >> "$CHECK_TRACE"\nif [ "$CHECK_FAIL" = "1" ] && [ "$*" = "run -- lint:eslint" ]; then exit 1; fi\n', { mode: 0o755 });
  const env = { ...process.env, HOME: temp, PATH: bin + ':' + path.dirname(process.execPath) + ':/usr/bin:/bin', CHECK_TRACE: trace, CHECK_FAIL: '0' };
  const run = (args = [], overrides = {}) => spawnSync('bash', [path.join(quality, 'scripts/lint-fix.sh'), temp, ...args], { env: { ...env, ...overrides }, encoding: 'utf8' });
  assert.equal(run().status, 0);
  assert.deepEqual(fs.readFileSync(trace, 'utf8').trim().split('\n'), ['run -- lint:prettier', 'run -- lint:stylelint', 'run -- lint:eslint', 'run -- type-check']);
  fs.writeFileSync(trace, '');
  assert.equal(run(['--ts']).status, 0);
  assert.equal(fs.readFileSync(trace, 'utf8').trim(), 'run -- type-check');
  assert.equal(run([], { CHECK_FAIL: '1' }).status, 1);
  const { request } = await import(pathToFileURL(path.join(quality, 'scripts/_http.mjs')));
  const server = http.createServer((req, res) => { res.writeHead(200, { 'cache-control': 'max-age=60' }); res.end('quality smoke'); });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const response = await request('http://127.0.0.1:' + server.address().port);
    assert.equal(response.status, 200);
    assert.equal(response.headers['cache-control'], 'max-age=60');
    assert.equal(response.body, 'quality smoke');
  } finally { await new Promise((resolve) => server.close(resolve)); }
} finally { fs.rmSync(temp, { recursive: true, force: true }); }

assert(!skills.includes('plugin-refresh'));
assert(!fs.existsSync(path.join(plugin, 'skills/agent-ops/plugin-refresh')));
const pluginReference = fs.readFileSync(path.join(base, 'references/plugins.md'), 'utf8');
for (const name of ['refresh-local-plugin.sh', 'refresh-local-codex-plugin.sh']) {
  assert(fs.existsSync(path.join(base, 'plugins/scripts', name)));
  assert(pluginReference.includes('agent-baseline/plugins/scripts/' + name));
}
const refreshRegression = spawnSync('bash', [path.join(base, 'plugins/tests/test-refresh-local-codex-plugin.sh')], { encoding: 'utf8' });
assert.equal(refreshRegression.status, 0, refreshRegression.stdout + refreshRegression.stderr);
assert(!fs.readFileSync(path.join(plugin, '.codex-plugin/plugin.json'), 'utf8').includes('./skills/requirements'));
const validation = spawnSync(process.execPath, [path.join(root, 'scripts/validate-skill-catalog.mjs'), '--working-tree'], { encoding: 'utf8' });
assert.equal(validation.status, 0, validation.stdout + validation.stderr);
console.log('PASS consolidated skills: baseline routes, isolated backup/restore, provider self-test, frontend checks, links, catalog and manifests');
