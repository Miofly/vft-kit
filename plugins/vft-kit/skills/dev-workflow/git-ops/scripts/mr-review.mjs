#!/usr/bin/env node
// git-ops-private 的 MR 评审：拉取 Gitee Code（code.iflytek.com，GitLab 兼容 API）MR 的 diff，
// 生成带行号的评审输入；把 AI 评审结论按「行内评论 + 汇总评论」写回 MR。
// 零依赖，Node 18+。token 只从环境变量或 token 文件读取，不打印。
//
// 接口要点（2026-10-08 在 code.iflytek.com 实测）：
// - 读 diff：GET /projects/:id/merge_requests/:iid/diffs（/changes、/versions、/discussions 均 404）
// - diff_refs 只在单个 MR 详情里有值，列表接口里是空串
// - 发评论：POST /projects/:id/merge_requests/:iid/notes，正文字段是 note，必须带 noteable_type=PullRequest
// - 行内评论：再带 commit_id=head_sha、line_code、diff_position_attributes{base_sha,start_sha,head_sha,old_path,new_path,old_line,new_line}
// - line_code = sha1(文件路径)_旧行号_新行号；新增行的旧行号取「下一个旧行号」，删除行的新行号取「下一个新行号」
// - token 删不了评论（DELETE 404），只能在网页上删，所以 post 默认只预览，加 --yes 才真写

import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const skillDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const vftAiDir = resolve(skillDir, '../../..');
// 与 git-private.mjs 共用 config.json 的 iflytek 段（host、api_prefix、secret、mr_review_out_root）
const config = JSON.parse(readFileSync(join(skillDir, 'config.json'), 'utf8')).iflytek;
const host = process.env.GITEE_CODE_HOST || config.host || 'code.iflytek.com';
const apiPrefix = process.env.GITEE_CODE_API_PREFIX || config.api_prefix || '/api/gitlab';
let cachedToken;
const MARK = '<sub>🤖 AI 评审</sub>';
const SEVERITY = {
  blocker: '🔴 阻断',
  major: '🟠 重要',
  minor: '🟡 一般',
  nit: '⚪ 建议',
};
// 不送去评审的文件：锁文件、构建产物、压缩文件、二进制
const SKIP_FILE = /(^|\/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|composer\.lock|Cargo\.lock|go\.sum)$|(^|\/)(dist|build|node_modules)\/|\.min\.(js|css)$|\.(png|jpe?g|gif|webp|svg|ico|woff2?|ttf|mp3|mp4|zip|jar)$/i;

const [command, ...args] = process.argv.slice(2);
switch (command) {
  case 'check':
    await check();
    break;
  case 'fetch':
    await fetchMr(args);
    break;
  case 'post':
    await post(args);
    break;
  case 'notes':
    await notes(args);
    break;
  case 'selftest':
    selftest();
    break;
  case undefined:
  case 'help':
  case '--help':
    console.log(`mr-review <command>
  check                                  校验 token 与 API 连通（只读）
  fetch <MR链接|iid> [--repo group/repo] [--out 目录] [--max-lines 3000]
                                         拉取 MR 元信息与 diff，生成 bundle.json 和带行号的 review-input.md
  post <findings.json> [--yes] [--no-summary]
                                         校验评审结论能否落到 diff 行；默认只预览，--yes 才写入 MR
  notes <MR链接|iid> [--repo group/repo] 列出 MR 上本工具发过的评论
  selftest                               离线校验 diff 解析与 line_code 规则（不联网）

环境变量：GITEE_CODE_TOKEN（或 GITEE_CODE_TOKEN_FILE 指向 {"token": "..."} 文件）、GITEE_CODE_HOST（默认 code.iflytek.com）`);
    break;
  default:
    fail(`未知命令：${command}`);
}

async function check() {
  const user = await api('GET', '/user');
  console.log(`token 有效：${user.username ?? user.login}（${host}）`);
}

async function fetchMr(rawArgs) {
  const { repo, iid } = parseTarget(rawArgs);
  const maxLines = Number(option(rawArgs, '--max-lines') ?? 3000);
  const project = encodeURIComponent(repo);
  const mr = await api('GET', `/projects/${project}/merge_requests/${iid}`);
  const rawDiffs = await api('GET', `/projects/${project}/merge_requests/${iid}/diffs?per_page=500`);
  const diffs = Array.isArray(rawDiffs) ? rawDiffs : rawDiffs.data ?? [];
  if (!mr.diff_refs?.head_sha) fail('MR 详情缺少 diff_refs.head_sha，无法定位行内评论');

  const files = [];
  const skipped = [];
  let total = 0;
  for (const item of diffs) {
    const path = item.new_path || item.old_path;
    if (SKIP_FILE.test(path) || !item.diff) {
      skipped.push(path);
      continue;
    }
    const lines = parseDiff(item.diff);
    total += lines.length;
    files.push({
      old_path: item.old_path,
      new_path: item.new_path,
      new_file: Boolean(item.new_file),
      deleted_file: Boolean(item.deleted_file),
      renamed_file: Boolean(item.renamed_file),
      lines,
    });
  }

  const outRoot = config.mr_review_out_root || join(tmpdir(), 'mr-review');
  const out = resolve(option(rawArgs, '--out') ?? join(outRoot, `${repo.replaceAll('/', '_')}-${iid}`));
  mkdirSync(out, { recursive: true });
  const me = await api('GET', '/user');
  const reviewer = me.username ?? me.login;
  const author = mr.author?.username ?? mr.author?.user_name;
  const previous = existsSync(join(out, 'bundle.json')) ? JSON.parse(readFileSync(join(out, 'bundle.json'), 'utf8')) : null;
  const bundle = {
    host,
    repo,
    iid: Number(iid),
    title: mr.title,
    description: mr.description ?? '',
    author,
    reviewer,
    source_branch: mr.source_branch,
    target_branch: mr.target_branch,
    state: mr.state,
    web_url: mr.web_url,
    diff_refs: mr.diff_refs,
    skipped,
    files,
  };
  writeFileSync(join(out, 'bundle.json'), JSON.stringify(bundle, null, 2));
  writeFileSync(join(out, 'review-input.md'), renderReviewInput(bundle));
  const findingsFile = join(out, 'findings.json');
  // MR 有新提交时旧结论的行号可能已失效：备份旧结论，换新模板
  const headChanged = previous && previous.diff_refs?.head_sha !== mr.diff_refs.head_sha;
  if (headChanged && existsSync(findingsFile)) {
    const backup = join(out, `findings.${previous.diff_refs.head_sha.slice(0, 7)}.json`);
    writeFileSync(backup, readFileSync(findingsFile));
    console.log(`MR 有新提交，旧结论已备份到 ${backup}`);
  }
  if (!existsSync(findingsFile) || headChanged) {
    writeFileSync(findingsFile, JSON.stringify({ verdict: '', summary: '', findings: [] }, null, 2));
  }

  console.log(`MR：${mr.web_url}`);
  console.log(`作者：${author ?? '-'}；当前 token 账号：${reviewer}${author === reviewer ? '（本人的 MR）' : ''}`);
  if (mr.state !== 'opened') console.log(`⚠️ MR 状态是 ${mr.state}，不是 opened：评论不会再影响合并，写回前先问用户是否还需要`);
  console.log(`标题：${mr.title}（${mr.source_branch} → ${mr.target_branch}，${mr.state}）`);
  console.log(`文件：${files.length} 个参与评审，${skipped.length} 个跳过；diff 共 ${total} 行`);
  if (total > maxLines) console.log(`⚠️ diff 超过 ${maxLines} 行，按文件分批评审，或请作者拆分 MR`);
  console.log(`评审输入：${join(out, 'review-input.md')}`);
  console.log(`结论写到：${findingsFile}`);
}

async function post(rawArgs) {
  const findingsFile = rawArgs.find(item => !item.startsWith('--'));
  if (!findingsFile) fail('用法：post <findings.json> [--yes]');
  const bundleFile = join(dirname(resolve(findingsFile)), 'bundle.json');
  if (!existsSync(bundleFile)) fail(`同目录下缺少 bundle.json，先运行 fetch：${bundleFile}`);
  const bundle = JSON.parse(readFileSync(bundleFile, 'utf8'));
  const review = JSON.parse(readFileSync(findingsFile, 'utf8'));
  const write = rawArgs.includes('--yes');
  if (!['approve', 'comment', 'request_changes'].includes(review.verdict)) fail('findings.json 的 verdict 未填写（approve/comment/request_changes）');
  if (!review.summary?.trim() && !rawArgs.includes('--no-summary')) fail('findings.json 的 summary 未填写');
  const project = encodeURIComponent(bundle.repo);
  const notesPath = `/projects/${project}/merge_requests/${bundle.iid}/notes`;

  const current = await api('GET', `/projects/${project}/merge_requests/${bundle.iid}`);
  if (current.diff_refs?.head_sha && current.diff_refs.head_sha !== bundle.diff_refs.head_sha) {
    fail('MR 在 fetch 之后有新提交，行号可能已变化：重新 fetch 并核对结论后再 post');
  }
  if (current.state !== 'opened') console.log(`⚠️ MR 状态是 ${current.state}`);

  const inline = [];
  const unplaced = [];
  for (const finding of review.findings ?? []) {
    if (!SEVERITY[finding.severity]) fail(`severity 只能是 ${Object.keys(SEVERITY).join('/')}：${JSON.stringify(finding).slice(0, 120)}`);
    const anchor = locate(bundle, finding);
    if (anchor) inline.push({ finding, anchor });
    else unplaced.push(finding);
  }

  // 已发过的同位置同标题评论不再重复发，方便修改后重跑
  const existing = await listNotes(notesPath);
  const seen = new Set(existing.map(note => `${note.line_code ?? ''}|${firstLine(note.note)}`));

  console.log(`${write ? '写入' : '预览（加 --yes 才写入）'}：${bundle.web_url}`);
  let posted = 0;
  for (const { finding, anchor } of inline) {
    const body = renderFinding(finding);
    const key = `${anchor.line_code}|${firstLine(body)}`;
    const where = `${anchor.path}:${finding.line}（${finding.side === 'old' ? '旧' : '新'}）`;
    if (seen.has(key)) {
      console.log(`  跳过已存在  ${where}  ${finding.title}`);
      continue;
    }
    console.log(`  行内评论    ${where}  ${SEVERITY[finding.severity]} ${finding.title}`);
    if (!write) continue;
    await api('POST', notesPath, {
      note: body,
      noteable_type: 'PullRequest',
      commit_id: bundle.diff_refs.head_sha,
      line_code: anchor.line_code,
      diff_position_attributes: {
        base_sha: bundle.diff_refs.base_sha,
        start_sha: bundle.diff_refs.base_sha,
        head_sha: bundle.diff_refs.head_sha,
        old_path: anchor.old_path,
        new_path: anchor.new_path,
        // 与网页端一致：新增行不传 old_line，删除行不传 new_line
        ...(anchor.old_line === null ? {} : { old_line: anchor.old_line }),
        ...(anchor.new_line === null ? {} : { new_line: anchor.new_line }),
      },
    });
    posted += 1;
  }
  for (const finding of unplaced) {
    console.log(`  无法定位行  ${finding.path ?? '-'}:${finding.line ?? '-'}  ${finding.title}（并入汇总评论）`);
  }

  if (!rawArgs.includes('--no-summary')) {
    const summary = renderSummary(review, inline.map(item => item.finding), unplaced);
    const duplicated = existing.some(note => !note.line_code && note.note === summary);
    console.log(duplicated ? '  跳过已存在  汇总评论' : '  汇总评论（全文如下）');
    if (!duplicated && !write) console.log(summary.split('\n').map(line => `    │ ${line}`).join('\n'));
    if (write && !duplicated) {
      await api('POST', notesPath, { note: summary, noteable_type: 'PullRequest' });
      posted += 1;
    }
  }
  console.log(write ? `完成：新写入 ${posted} 条。删除评论只能在网页上操作。` : '预览结束，确认无误后加 --yes 写入。');
}

async function notes(rawArgs) {
  const { repo, iid } = parseTarget(rawArgs);
  const list = await listNotes(`/projects/${encodeURIComponent(repo)}/merge_requests/${iid}/notes`);
  const mine = list.filter(note => note.note?.includes(MARK));
  console.log(`MR 上共 ${list.length} 条评论，其中本工具发的 ${mine.length} 条`);
  for (const note of mine) console.log(`  #${note.id} ${note.line_code ? '行内' : '汇总'}  ${firstLine(note.note)}`);
}

// 期望值取自 2026-10-08 code.iflytek.com 网页端 diff 行的锚点 id
function selftest() {
  const path = 'modern/baymoon/src/components/result/starlight-result.vue';
  const diff = '@@ -17,4 +17,3 @@\n   <div>\n   <p>a</p>\n-  <!-- x -->\n   <div>\n@@ -276,3 +275,5 @@\n   display: flex;\n+  position: absolute;\n+  top: 471px;\n   flex: 1;\n';
  const bundle = { files: [{ old_path: path, new_path: path, lines: parseDiff(diff) }] };
  const sha = createHash('sha1').update(path).digest('hex');
  const cases = [
    [{ path, line: 18, side: 'new' }, `${sha}_18_18`, 18, 18],
    [{ path, line: 19, side: 'old' }, `${sha}_19_19`, 19, null],
    [{ path, line: 277, side: 'new' }, `${sha}_277_277`, null, 277],
    [{ path, line: 277, side: 'old' }, `${sha}_277_278`, 277, 278],
    [{ path, line: 999, side: 'new' }, null],
  ];
  let failed = 0;
  for (const [finding, code, oldLine, newLine] of cases) {
    const anchor = locate(bundle, finding);
    const ok = code === null ? anchor === null : anchor?.line_code === code && anchor.old_line === oldLine && anchor.new_line === newLine;
    if (!ok) failed += 1;
    console.log(`${ok ? '✓' : '✗'} ${finding.side}:${finding.line} → ${anchor ? `${anchor.line_code.slice(-12)} old=${anchor.old_line} new=${anchor.new_line}` : '无法定位'}`);
  }
  if (failed) fail(`${failed} 项失败`);
  console.log('selftest 通过');
}

// ---- diff 解析与行定位 ----

function parseDiff(diff) {
  const lines = [];
  let oldLine = 0;
  let newLine = 0;
  for (const raw of diff.split('\n')) {
    const hunk = raw.match(/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)/);
    if (hunk) {
      oldLine = Number(hunk[1]);
      newLine = Number(hunk[2]);
      lines.push({ type: 'hunk', text: raw });
      continue;
    }
    if (raw.startsWith('\\')) continue;
    const mark = raw[0];
    const text = raw.slice(1);
    // 新增行的旧行号、删除行的新行号都取「下一个」行号，与网页端 line_code 一致
    if (mark === '+') lines.push({ type: 'add', old: oldLine, new: newLine++, text });
    else if (mark === '-') lines.push({ type: 'del', old: oldLine++, new: newLine, text });
    else if (mark === ' ' || raw === '') lines.push({ type: 'ctx', old: oldLine++, new: newLine++, text });
  }
  // diff 末尾的空串会被当成上下文行，去掉
  while (lines.length && lines.at(-1).type === 'ctx' && lines.at(-1).text === '') lines.pop();
  return lines;
}

function locate(bundle, finding) {
  if (!finding.path || !Number.isInteger(finding.line)) return null;
  const file = bundle.files.find(item => item.new_path === finding.path || item.old_path === finding.path);
  if (!file) return null;
  const side = finding.side === 'old' ? 'old' : 'new';
  const line = file.lines.find(item =>
    item.type !== 'hunk' && item[side] === finding.line && (side === 'new' ? item.type !== 'del' : item.type !== 'add'),
  );
  if (!line) return null;
  const path = side === 'old' ? file.old_path : file.new_path;
  return {
    path,
    old_path: file.old_path,
    new_path: file.new_path,
    old_line: line.type === 'add' ? null : line.old,
    new_line: line.type === 'del' ? null : line.new,
    line_code: `${createHash('sha1').update(path).digest('hex')}_${line.old}_${line.new}`,
  };
}

// ---- 渲染 ----

function renderReviewInput(bundle) {
  const out = [
    `# MR 评审输入：${bundle.repo} !${bundle.iid}`,
    '',
    `- 标题：${bundle.title}`,
    `- 分支：${bundle.source_branch} → ${bundle.target_branch}`,
    `- 作者：${bundle.author ?? '-'}`,
    `- 链接：${bundle.web_url}`,
    bundle.skipped.length ? `- 跳过文件：${bundle.skipped.join('、')}` : '',
    '',
    '## 描述',
    '',
    bundle.description || '（无）',
    '',
    '## Diff',
    '',
    '行首标记：`+N` 新增行（新行号 N）、`-O` 删除行（旧行号 O）、` N` 未改动上下文（新行号 N）。',
    '评论新增或上下文行时用 side=new + 新行号；评论删除行时用 side=old + 旧行号。',
    '',
  ];
  for (const file of bundle.files) {
    const flag = file.new_file ? '（新文件）' : file.deleted_file ? '（已删除）' : file.renamed_file ? `（由 ${file.old_path} 重命名）` : '';
    out.push(`### ${file.new_path}${flag}`, '', '```diff');
    for (const line of file.lines) {
      if (line.type === 'hunk') out.push(line.text);
      else if (line.type === 'add') out.push(`+${String(line.new).padStart(5)} | ${line.text}`);
      else if (line.type === 'del') out.push(`-${String(line.old).padStart(5)} | ${line.text}`);
      else out.push(` ${String(line.new).padStart(5)} | ${line.text}`);
    }
    out.push('```', '');
  }
  return out.filter(item => item !== null).join('\n');
}

function renderFinding(finding) {
  const parts = [`**${SEVERITY[finding.severity]}｜${finding.title}**`, '', finding.body ?? ''];
  if (finding.suggestion) parts.push('', '建议改为：', '', '```', finding.suggestion, '```');
  parts.push('', MARK);
  return parts.join('\n');
}

function renderSummary(review, inline, unplaced) {
  const all = [...inline, ...unplaced];
  const count = severity => all.filter(item => item.severity === severity).length;
  const verdict = { approve: '✅ 建议合并', comment: '💬 有建议，可酌情合并', request_changes: '⛔ 建议修改后再合并' }[review.verdict] ?? '💬 评审意见';
  const lines = [
    `### AI 评审结论：${verdict}`,
    '',
    review.summary || '',
    '',
    `问题统计：${Object.keys(SEVERITY).map(key => `${SEVERITY[key]} ${count(key)}`).join('　')}`,
  ];
  if (inline.length) {
    lines.push('', '| 级别 | 位置 | 问题 |', '| --- | --- | --- |');
    for (const item of inline) lines.push(`| ${SEVERITY[item.severity]} | \`${item.path}:${item.line}\` | ${item.title} |`);
  }
  if (unplaced.length) {
    lines.push('', '**未能定位到 diff 行的意见：**', '');
    for (const item of unplaced) lines.push(`- ${SEVERITY[item.severity]} ${item.path ? `\`${item.path}${item.line ? `:${item.line}` : ''}\` ` : ''}**${item.title}**：${item.body ?? ''}`);
  }
  lines.push('', MARK);
  return lines.join('\n');
}

// ---- 通用 ----

function parseTarget(rawArgs) {
  const first = rawArgs.find(item => !item.startsWith('--') && !isOptionValue(rawArgs, item));
  if (!first) fail('缺少 MR 链接或 iid');
  const url = first.match(/\/_source\/(.+?)\/-\/(?:pull_requests|merge_requests)\/(\d+)/);
  if (url) return { repo: decodeURIComponent(url[1]), iid: url[2] };
  if (!/^\d+$/.test(first)) fail(`无法识别 MR：${first}`);
  const repo = option(rawArgs, '--repo') ?? repoFromOrigin();
  if (!repo) fail('当前目录不是 Gitee Code 仓库，请传 MR 链接或 --repo group/repo');
  return { repo, iid: first };
}

function repoFromOrigin() {
  const result = spawnSync('git', ['remote', 'get-url', 'origin'], { encoding: 'utf8' });
  const remote = result.status === 0 ? result.stdout.trim() : '';
  if (!remote.includes(host)) return null;
  // ssh://git@host:30004/group/repo.git、git@host:group/repo.git、https://host/group/repo.git
  return remote.replace(new RegExp(`^.*?${host.replaceAll('.', '\\.')}(:\\d+)?[/:]`), '').replace(/\.git$/, '');
}

async function listNotes(path) {
  const all = [];
  for (let page = 1; page <= 20; page += 1) {
    const data = await api('GET', `${path}?per_page=100&page=${page}`);
    const items = Array.isArray(data) ? data : data.data ?? [];
    all.push(...items);
    const totalPages = data.meta?.total_pages ?? 1;
    if (page >= totalPages || items.length === 0) break;
  }
  return all;
}

async function api(method, path, body) {
  const url = `https://${host}${apiPrefix}${path}`;
  // Node fetch 不读 HTTP(S)_PROXY，内网域名直连
  const response = await fetch(url, {
    method,
    headers: { 'PRIVATE-TOKEN': readToken(), ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(30000),
  }).catch(error => fail(`请求失败（需在公司内网或 VPN）：${error.cause?.code ?? error.message}`));
  const text = await response.text();
  if (!response.ok) fail(`${method} ${path.split('?')[0]} → HTTP ${response.status}：${text.slice(0, 200)}`);
  return text ? JSON.parse(text) : {};
}

function readToken() {
  if (cachedToken) return cachedToken;
  if (process.env.GITEE_CODE_TOKEN) return (cachedToken = process.env.GITEE_CODE_TOKEN.trim());
  // 源码态读本仓库 .secrets；插件缓存态回落 VFT_AI_SECRETS_DIR
  const secretsDir = [process.env.VFT_AI_SECRETS_DIR, resolve(vftAiDir, '.secrets')]
    .filter(Boolean).find(dir => existsSync(resolve(dir, config.secret)));
  const file = process.env.GITEE_CODE_TOKEN_FILE || (secretsDir && resolve(secretsDir, config.secret));
  if (file) {
    const path = resolve(file.replace(/^~(?=\/)/, homedir()));
    if (!existsSync(path)) fail(`token 文件不存在：${path}`);
    const content = readFileSync(path, 'utf8').trim();
    cachedToken = content.startsWith('{') ? JSON.parse(content).token : content;
    if (cachedToken) return cachedToken;
  }
  fail(`缺少 token：私有凭据 ${config.secret} 不存在，或设置 GITEE_CODE_TOKEN。生成地址：https://${host}/osc/_users/gitee/#/private_token/new`);
}

function option(list, name) {
  const index = list.indexOf(name);
  return index >= 0 ? list[index + 1] : undefined;
}

function isOptionValue(list, value) {
  const index = list.indexOf(value);
  return index > 0 && list[index - 1].startsWith('--') && !['--yes', '--no-summary'].includes(list[index - 1]);
}

function firstLine(text = '') {
  return text.split('\n')[0].trim();
}

function fail(message) {
  console.error(`✗ ${message}`);
  process.exit(1);
}
