import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const script = fileURLToPath(new URL('./github-ops.mjs', import.meta.url));
function fixture(t, overrides = {}) {
  const dir = mkdtempSync(resolve(process.env.GITHUB_OPS_TEST_TMP || tmpdir(), 'github-ops-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const state = resolve(dir, 'state.json');
  const body = resolve(dir, 'body.md');
  writeFileSync(state, JSON.stringify({ state: 'open', state_reason: null, comments: [], calls: [], ...overrides }));
  writeFileSync(body, 'Fixed in 1.2.3.\n\nVerified CJS and ESM.\n');
  const gh = resolve(dir, 'gh');
  writeFileSync(gh, `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2);
const path = process.env.MOCK_GH_STATE;
const state = JSON.parse(fs.readFileSync(path));
state.calls.push(args);
const save = () => fs.writeFileSync(path, JSON.stringify(state));
save();
if (state.fail) process.exit(state.fail);
if (args[0] === 'api') {
  if (args[1] === 'user') console.log(JSON.stringify({login:'owner'}));
  else if (args[1].endsWith('/comments')) console.log(JSON.stringify([state.comments.slice(0,1),state.comments.slice(1)]));
  else console.log(JSON.stringify({number:14,state:state.state,state_reason:state.state_reason,html_url:'https://github.com/owner/repo/issues/14',...(state.pr?{pull_request:{}}:{})}));
} else if (args[0] === 'issue' && args[1] === 'comment') {
  const body = fs.readFileSync(0,'utf8');
  if (!state.dropComment) state.comments.push({id:state.comments.length+1,html_url:'https://github.com/owner/repo/issues/14#issuecomment-1',body,user:{login:'owner'}});
  save();
} else if (args[0] === 'issue' && args[1] === 'close') {
  if (!state.dropClose) {state.state='closed';state.state_reason=args[args.indexOf('--reason')+1]==='completed'?'completed':'not_planned';}
  save();
} else console.log(JSON.stringify({args}));
`);
  chmodSync(gh, 0o700);
  return {
    body,
    state: () => JSON.parse(readFileSync(state, 'utf8')),
    run: (...args) => spawnSync(process.execPath, [script, ...args], {
      env: { ...process.env, PATH: dir + delimiter + process.env.PATH, MOCK_GH_STATE: state },
      encoding: 'utf8', input: readFileSync(body),
    }),
  };
}
const base = ['--repo', 'owner/repo', '--number', '14'];

test('issue list forwards filters; view returns details; comments flatten all pages', t => {
  const f = fixture(t, { comments: [{ id: 1 }, { id: 2 }] });
  assert.equal(f.run('issue', 'list', '--repo', 'owner/repo', '--state', 'all', '--search', 'dist missing').status, 0);
  assert.equal(f.run('issue', 'view', ...base).status, 0);
  assert.deepEqual(JSON.parse(f.run('issue', 'comments', ...base).stdout), [{ id: 1 }, { id: 2 }]);
  assert(f.state().calls.some(a => a.includes('--search') && a.includes('dist missing')));
});

test('comment reads file/stdin, verifies body, and avoids duplicate writes', t => {
  const f = fixture(t);
  assert.equal(f.run('issue', 'comment', ...base, '--body-file', f.body).status, 0);
  assert.equal(f.run('issue', 'comment', ...base, '--body-file', '-').status, 0);
  assert.equal(f.state().comments.length, 1);
  assert.equal(f.state().comments[0].body, readFileSync(f.body, 'utf8'));
});

test('close verifies state/reason and is idempotent', t => {
  const f = fixture(t);
  assert.equal(f.run('issue', 'close', ...base).status, 0);
  assert.equal(f.run('issue', 'close', ...base).status, 0);
  assert.equal(f.state().calls.filter(a => a[0] === 'issue' && a[1] === 'close').length, 1);
  assert.equal(f.state().state_reason, 'completed');
});

test('not planned maps correctly; existing different reason remains unchanged', t => {
  const f = fixture(t);
  assert.equal(f.run('issue', 'close', ...base, '--reason', 'not planned').status, 0);
  assert.equal(f.state().state_reason, 'not_planned');
  assert.notEqual(f.run('issue', 'close', ...base).status, 0);
});

test('rejects PR target and invalid/unknown parameters without mutation', t => {
  const f = fixture(t, { pr: true });
  assert.notEqual(f.run('issue', 'comment', ...base, '--body-file', f.body).status, 0);
  for (const args of [
    ['issue', 'view', '--repo', 'owner/repo', '--number', '-1'],
    ['issue', 'close', ...base, '--reason', 'typo'],
    ['issue', 'close', ...base, '--reson', 'completed'],
    ['issue', 'list', '--repo', 'owner/repo', '--state', 'typo'],
    ['issue', 'comment', ...base],
  ]) assert.notEqual(f.run(...args).status, 0);
  assert(!f.state().calls.some(a => a[0] === 'issue' && ['close', 'comment'].includes(a[1])));
});

test('empty body, failed readback and CLI errors fail closed', t => {
  const empty = fixture(t); writeFileSync(empty.body, '   ');
  assert.notEqual(empty.run('issue', 'comment', ...base, '--body-file', empty.body).status, 0);
  const comment = fixture(t, { dropComment: true });
  assert.notEqual(comment.run('issue', 'comment', ...base, '--body-file', comment.body).status, 0);
  const close = fixture(t, { dropClose: true });
  assert.notEqual(close.run('issue', 'close', ...base).status, 0);
  const failure = fixture(t, { fail: 7 });
  assert.equal(failure.run('issue', 'view', ...base).status, 7);
});

test('existing auth/repo/secret/run/workflow commands still dispatch', t => {
  const f = fixture(t);
  for (const args of [
    ['auth'], ['repo', '--repo', 'owner/repo'],
    ['secret', 'list', '--repo', 'owner/repo'],
    ['secret', 'set', '--repo', 'owner/repo', '--name', 'NAME'],
    ['secret', 'delete', '--repo', 'owner/repo', '--name', 'NAME'],
    ['run', 'list', '--repo', 'owner/repo'],
    ['run', 'view', '--repo', 'owner/repo', '--id', '123'],
    ['run', 'rerun-failed', '--repo', 'owner/repo', '--id', '123'],
    ['workflow', 'run', '--repo', 'owner/repo', '--workflow', 'ci.yml'],
  ]) assert.equal(f.run(...args).status, 0, args.join(' '));
});
