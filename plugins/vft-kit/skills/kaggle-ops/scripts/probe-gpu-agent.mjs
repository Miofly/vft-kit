#!/usr/bin/env node
/**
 * probe-gpu-agent.mjs — 使用 Agent 并发探测 Kaggle 账号 GPU 可用性
 *
 * 与 probe-gpu.mjs 的区别：
 *   - probe-gpu.mjs: 单进程 + 自定义并发池（适合 Node 环境）
 *   - probe-gpu-agent.mjs: 调用多个 Agent 并发执行（适合 Claude Code 环境）
 *
 * 优势：
 *   - Agent 并发执行，充分利用系统资源
 *   - 每个 Agent 独立隔离，互不干扰
 *   - 更快的探测速度（尤其是账号数量多时）
 *
 * 用法：
 *   node probe-gpu-agent.mjs --accounts accounts.json
 *   node probe-gpu-agent.mjs --accounts accounts.json --limit 5
 *   node probe-gpu-agent.mjs --accounts accounts.json --concurrency 8
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ── 参数解析 ──────────────────────────────────────────
const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const m = a.match(/^--([^=]+)(?:=(.*))?$/);
    return m ? [m[1], m[2] ?? true] : [a, true];
  }),
);

const ACCOUNTS_FILE = args.accounts || null;
const USERNAME = args.username || process.env.KAGGLE_USERNAME || null;
const TOKEN = args.token || process.env.KAGGLE_API_TOKEN || null;
const LIMIT = args.limit ? parseInt(args.limit, 10) : 0;
const CONCURRENCY = Math.max(1, parseInt(args.concurrency || '8', 10));
const ACCELERATOR = args.accelerator || null;
const OUTPUT_PREFIX = args.output || 'gpu-probe-report';
const WORKER_SCRIPT = path.join(__dirname, 'probe-gpu-worker.mjs');

// ── 读取账号 ─────────────────────────────────────────
let accounts = [];

if (ACCOUNTS_FILE) {
  try {
    const raw = fs.readFileSync(ACCOUNTS_FILE, 'utf8');
    const data = JSON.parse(raw);
    accounts = Array.isArray(data) ? data : [];
    if (!accounts.length) throw new Error('账号列表为空');
    for (const acc of accounts) {
      if (!acc.username || !acc.token) {
        throw new Error(`账号格式错误: ${JSON.stringify(acc)}`);
      }
    }
  } catch (e) {
    console.error(`✗ 读取账号文件失败: ${e.message}`);
    process.exit(1);
  }
} else if (USERNAME && TOKEN) {
  accounts = [{ username: USERNAME, token: TOKEN }];
} else {
  console.error('✗ 缺少账号输入');
  console.error('用法:');
  console.error('  --accounts accounts.json  # JSON 文件');
  console.error('  --username xxx --token KGAT_xxx  # 单个账号');
  console.error('  或设置环境变量 KAGGLE_USERNAME + KAGGLE_API_TOKEN');
  process.exit(1);
}

if (LIMIT > 0) accounts = accounts.slice(0, LIMIT);

// ── 检查 worker 脚本 ──────────────────────────────────
if (!fs.existsSync(WORKER_SCRIPT)) {
  console.error(`✗ Worker 脚本不存在: ${WORKER_SCRIPT}`);
  console.error('请确保 probe-gpu-worker.mjs 在同一目录下');
  process.exit(1);
}

console.log(`待探测账号数=${accounts.length}  并发=${CONCURRENCY}`);
console.log(`加速器=${ACCELERATOR || '默认 GPU'}`);
console.log(`Worker 脚本: ${WORKER_SCRIPT}\n`);

// ── 生成 Agent 调用指令 ───────────────────────────────
console.log('═══════════════════════════════════════════');
console.log('  请在 Claude Code 中执行以下操作');
console.log('═══════════════════════════════════════════\n');

console.log('1. 准备临时账号文件（每个 Agent 一个）：\n');

// 为每个账号创建临时文件
const tempDir = path.join(__dirname, '.tmp-probe-accounts');
if (!fs.existsSync(tempDir)) {
  fs.mkdirSync(tempDir, { recursive: true });
}

const tempFiles = accounts.map((acc, i) => {
  const filename = `account-${i + 1}-${acc.username}.json`;
  const filepath = path.join(tempDir, filename);
  fs.writeFileSync(filepath, JSON.stringify(acc, null, 2));
  return { index: i + 1, username: acc.username, filepath };
});

console.log(`✓ 已创建 ${tempFiles.length} 个临时账号文件到: ${tempDir}\n`);

console.log('2. 使用以下命令启动并发探测：\n');
console.log('```javascript');
console.log('// 在 Claude Code 中运行此代码');
console.log('const results = await Promise.all([');

tempFiles.forEach((item, idx) => {
  const comma = idx < tempFiles.length - 1 ? ',' : '';
  const cmd = `node ${WORKER_SCRIPT} --account-file ${item.filepath}${ACCELERATOR ? ` --accelerator ${ACCELERATOR}` : ''}`;
  console.log(`  agent('探测账号 ${item.username} GPU', { label: '账号${item.index}' }).then(() => \`${cmd}\`)${comma}`);
});

console.log(']);');
console.log('```\n');

console.log('或者使用 Bash 工具批量执行：\n');
console.log('```bash');
tempFiles.forEach((item) => {
  console.log(`node ${WORKER_SCRIPT} --account-file ${item.filepath}${ACCELERATOR ? ` --accelerator ${ACCELERATOR}` : ''} &`);
});
console.log('wait');
console.log('```\n');

console.log('3. 收集结果：\n');
console.log('```bash');
console.log(`node ${__dirname}/collect-probe-results.mjs --dir ${tempDir} --output ${OUTPUT_PREFIX}`);
console.log('```\n');

console.log('═══════════════════════════════════════════\n');

// ── 输出元信息 ────────────────────────────────────────
const metaPath = path.join(tempDir, 'probe-meta.json');
fs.writeFileSync(metaPath, JSON.stringify({
  accounts: accounts.length,
  concurrency: CONCURRENCY,
  accelerator: ACCELERATOR,
  output_prefix: OUTPUT_PREFIX,
  worker_script: WORKER_SCRIPT,
  temp_files: tempFiles,
  created_at: new Date().toISOString(),
}, null, 2));

console.log(`元信息已保存到: ${metaPath}`);
console.log('\n提示: 探测完成后可删除临时目录');
console.log(`  rm -rf ${tempDir}\n`);
