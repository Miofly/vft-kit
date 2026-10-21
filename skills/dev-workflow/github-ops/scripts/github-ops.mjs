#!/usr/bin/env node

import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const tokens = process.argv.slice(2);
const area = tokens.shift();
const action = tokens[0]?.startsWith('--') ? undefined : tokens.shift();
const rawArgs = tokens;
const args = new Map();
for (let i = 0; i < rawArgs.length; i += 2) {
  const key = rawArgs[i];
  if (!key?.startsWith('--') || rawArgs[i + 1] == null) fail(`参数错误: ${key ?? ''}`);
  args.set(key.slice(2), rawArgs[i + 1]);
}

const repo = args.get('repo');

if (!area || area === 'help' || area === '--help') usage();

switch (`${area}:${action ?? ''}`) {
  case 'auth:': {
    run(['api', 'user', '--jq', '{login:.login}']);
    if (repo) run(['api', `repos/${repo}`, '--jq', '{name:.full_name,permissions:.permissions}']);
    break;
  }
  case 'repo:':
    requireRepo();
    run(['repo', 'view', repo, '--json', 'nameWithOwner,isPrivate,defaultBranchRef,url,viewerPermission']);
    break;
  case 'secret:list':
    requireRepo();
    run(['secret', 'list', '--repo', repo, '--app', 'actions', '--json', 'name,updatedAt']);
    break;
  case 'secret:set': {
    requireRepo();
    if (args.has('value')) fail('禁止使用 --value；请通过 stdin 或 --value-file 传入 Secret');
    const name = required('name');
    const file = args.get('value-file');
    const value = file ? readFileSync(file) : readFileSync(0);
    if (!value.length) fail('Secret 值为空');
    run(['secret', 'set', name, '--repo', repo, '--app', 'actions'], value);
    break;
  }
  case 'secret:delete':
    requireRepo();
    run(['secret', 'delete', required('name'), '--repo', repo, '--app', 'actions']);
    break;
  case 'run:list':
    requireRepo();
    run(['run', 'list', '--repo', repo, '--limit', args.get('limit') ?? '20', '--json',
      'databaseId,workflowName,status,conclusion,createdAt,url']);
    break;
  case 'run:view':
    requireRepo();
    run(['run', 'view', required('id'), '--repo', repo, '--json',
      'databaseId,workflowName,status,conclusion,attempt,url,jobs']);
    break;
  case 'run:rerun-failed':
    requireRepo();
    run(['run', 'rerun', required('id'), '--failed', '--repo', repo]);
    break;
  case 'workflow:run': {
    requireRepo();
    const command = ['workflow', 'run', required('workflow'), '--repo', repo];
    if (args.has('ref')) command.push('--ref', args.get('ref'));
    run(command);
    break;
  }
  default:
    fail(`未知命令: ${area}${action ? ` ${action}` : ''}`);
}

function run(command, input) {
  const result = spawnSync('gh', command, {
    encoding: input ? undefined : 'utf8',
    input,
    stdio: input ? ['pipe', 'inherit', 'inherit'] : ['ignore', 'inherit', 'inherit'],
    env: process.env,
  });
  if (result.error) fail(`无法执行 gh: ${result.error.message}`);
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function required(name) {
  const value = args.get(name);
  if (!value) fail(`缺少 --${name}`);
  return value;
}

function requireRepo() {
  if (!repo || !/^[^/\s]+\/[^/\s]+$/.test(repo)) fail('缺少或无效的 --repo owner/repo');
}

function fail(message) {
  console.error(message);
  process.exit(2);
}

function usage() {
  console.log(`github-ops
  auth [--repo owner/repo]
  repo --repo owner/repo
  secret list --repo owner/repo
  secret set --repo owner/repo --name NAME [--value-file FILE]
  secret delete --repo owner/repo --name NAME
  run list --repo owner/repo [--limit N]
  run view --repo owner/repo --id ID
  run rerun-failed --repo owner/repo --id ID
  workflow run --repo owner/repo --workflow FILE [--ref REF]`);
  process.exit(0);
}
