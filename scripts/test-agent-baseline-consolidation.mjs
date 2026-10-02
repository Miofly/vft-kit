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
for (const old of ['cc-baseline', 'codex-baseline']) {
  assert(!skills.includes(old));
  assert(!fs.existsSync(path.join(plugin, 'skills/agent-ops', old)));
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
console.log('PASS consolidated skills: baseline routes, frontend lint order/filter/failure and HTTP smoke, links, catalog and manifests');
