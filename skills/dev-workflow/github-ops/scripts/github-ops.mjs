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

if (area === 'issue') {
  const options = {
    list: ['repo', 'state', 'limit', 'search'],
    view: ['repo', 'number'],
    comments: ['repo', 'number'],
    comment: ['repo', 'number', 'body-file'],
    close: ['repo', 'number', 'reason'],
  }[action];
  if (!options) fail(`未知 Issue 命令: ${action}`);
  for (const key of args.keys()) if (!options.includes(key)) fail(`不支持 --${key}`);
}

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
  case 'issue:list': {
    requireRepo();
    const state = args.get('state') ?? 'open';
    if (!['open', 'closed', 'all'].includes(state)) fail('无效的 --state open|closed|all');
    const command = ['issue', 'list', '--repo', repo, '--state', state, '--limit', args.get('limit') ?? '20',
      '--json', 'number,title,state,url,updatedAt'];
    if (args.has('search')) command.push('--search', args.get('search'));
    run(command);
    break;
  }
  case 'issue:view':
    issueInfo();
    run(['issue', 'view', issueNumber(), '--repo', repo, '--json',
      'number,title,body,author,state,stateReason,url,labels,assignees,updatedAt']);
    break;
  case 'issue:comments':
    issueInfo();
    console.log(JSON.stringify(issueComments(), null, 2));
    break;
  case 'issue:comment': {
    issueInfo();
    if (args.has('body') || !args.has('body-file')) fail('回复正文请使用 --body-file FILE（- 表示 stdin）');
    const file = required('body-file');
    const body = readFileSync(file === '-' ? 0 : file, 'utf8');
    if (!body.trim() || body.includes('\0')) fail('回复正文为空或包含 NUL');
    const login = JSON.parse(run(['api', 'user'], undefined, true)).login;
    const matching = () => issueComments().find(comment => comment.user.login === login && comment.body === body);
    let comment = matching();
    if (!comment) {
      run(['issue', 'comment', issueNumber(), '--repo', repo, '--body-file', '-'], Buffer.from(body));
      comment = matching();
      if (!comment) fail('回复已提交但回读未匹配；先检查远端评论，不要直接重试');
    }
    console.log(JSON.stringify({ id: comment.id, url: comment.html_url, body: comment.body }));
    break;
  }
  case 'issue:close': {
    const before = issueInfo();
    const reason = args.get('reason') ?? 'completed';
    if (!['completed', 'not planned'].includes(reason)) fail('无效的 --reason completed|not planned');
    const expected = reason === 'completed' ? 'completed' : 'not_planned';
    if (before.state === 'closed' && before.state_reason !== expected) {
      fail('Issue 已关闭且原因不同；保留现状，不自动改写关闭原因');
    }
    if (before.state !== 'closed') {
      run(['issue', 'close', issueNumber(), '--repo', repo, '--reason', reason]);
    }
    const after = issueInfo();
    if (after.state !== 'closed' || after.state_reason !== expected) fail('关闭后远端状态/原因未匹配');
    console.log(JSON.stringify({ number: after.number, state: after.state, reason: after.state_reason, url: after.html_url }));
    break;
  }
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

function issueNumber() {
  const number = required('number');
  if (!/^[1-9]\d*$/.test(number)) fail('无效的 --number 正整数');
  return number;
}

function issueInfo() {
  requireRepo();
  const info = JSON.parse(run(['api', `repos/${repo}/issues/${issueNumber()}`], undefined, true));
  if (info.pull_request) fail('目标是 Pull Request，不是 Issue');
  return info;
}

function issueComments() {
  return JSON.parse(run(['api', `repos/${repo}/issues/${issueNumber()}/comments`,
    '--paginate', '--slurp'], undefined, true)).flat();
}

function run(command, input, capture = false) {
  const result = spawnSync('gh', command, {
    encoding: 'utf8',
    input,
    stdio: capture ? ['ignore', 'pipe', 'inherit'] : input ? ['pipe', 'inherit', 'inherit'] : ['ignore', 'inherit', 'inherit'],
    env: process.env,
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) fail(`无法执行 gh: ${result.error.message}`);
  if (result.status !== 0) process.exit(result.status ?? 1);
  return result.stdout;
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
  issue list --repo owner/repo [--state open|closed|all] [--limit N] [--search QUERY]
  issue view --repo owner/repo --number N
  issue comments --repo owner/repo --number N
  issue comment --repo owner/repo --number N --body-file FILE
  issue close --repo owner/repo --number N [--reason completed|"not planned"]
  secret list --repo owner/repo
  secret set --repo owner/repo --name NAME [--value-file FILE]
  secret delete --repo owner/repo --name NAME
  run list --repo owner/repo [--limit N]
  run view --repo owner/repo --id ID
  run rerun-failed --repo owner/repo --id ID
  workflow run --repo owner/repo --workflow FILE [--ref REF]`);
  process.exit(0);
}
