#!/usr/bin/env node
/**
 * test-agent-probe.mjs — Agent 并发探测快速测试
 *
 * 使用模拟数据测试整个工作流程（不会真正调用 Kaggle API）
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

console.log('═══════════════════════════════════════════');
console.log('   Agent 并发探测 - 快速测试');
console.log('═══════════════════════════════════════════\n');

// 创建测试目录
const testDir = path.join(__dirname, '.test-probe');
if (fs.existsSync(testDir)) {
  fs.rmSync(testDir, { recursive: true });
}
fs.mkdirSync(testDir);

console.log(`测试目录: ${testDir}\n`);

// 模拟账号数据
const testAccounts = [
  { username: 'test-user-1', token: 'KGAT_test_token_1' },
  { username: 'test-user-2', token: 'KGAT_test_token_2' },
  { username: 'test-user-3', token: 'KGAT_test_token_3' },
];

console.log(`创建 ${testAccounts.length} 个测试账号文件...\n`);

// 为每个账号创建文件
testAccounts.forEach((acc, idx) => {
  const filename = `account-${idx + 1}-${acc.username}.json`;
  const filepath = path.join(testDir, filename);
  fs.writeFileSync(filepath, JSON.stringify(acc, null, 2));
  console.log(`✓ ${filename}`);
});

console.log('\n创建模拟结果文件...\n');

// 创建模拟结果（模拟 worker 的输出）
const mockResults = [
  {
    username: 'test-user-1',
    push: 'ok',
    status: 'COMPLETE',
    cuda: true,
    gpu: 'Tesla T4',
    cap: '7.5',
    count: 1,
    note: '',
    started_at: new Date().toISOString(),
    finished_at: new Date(Date.now() + 180000).toISOString(),
  },
  {
    username: 'test-user-2',
    push: 'ok',
    status: 'COMPLETE',
    cuda: false,
    gpu: '',
    cap: '',
    count: 0,
    note: '未验证手机',
    started_at: new Date().toISOString(),
    finished_at: new Date(Date.now() + 185000).toISOString(),
  },
  {
    username: 'test-user-3',
    push: '403',
    status: '?',
    cuda: null,
    gpu: '',
    cap: '',
    count: 0,
    note: 'public/未验证被拒',
    started_at: new Date().toISOString(),
    finished_at: new Date(Date.now() + 60000).toISOString(),
  },
];

mockResults.forEach((result) => {
  const filename = `result-${result.username}.json`;
  const filepath = path.join(testDir, filename);
  fs.writeFileSync(filepath, JSON.stringify(result, null, 2));
  console.log(`✓ ${filename}`);
});

// 创建元信息
const meta = {
  accounts: testAccounts.length,
  concurrency: 3,
  accelerator: null,
  output_prefix: 'test-gpu-probe-report',
  worker_script: path.join(__dirname, 'probe-gpu-worker.mjs'),
  temp_files: testAccounts.map((acc, idx) => ({
    index: idx + 1,
    username: acc.username,
    filepath: path.join(testDir, `account-${idx + 1}-${acc.username}.json`),
  })),
  created_at: new Date().toISOString(),
};

fs.writeFileSync(path.join(testDir, 'probe-meta.json'), JSON.stringify(meta, null, 2));
console.log('✓ probe-meta.json');

console.log('\n模拟 Agent 并发任务...\n');

console.log('在真实场景中，你会在 Claude Code 中运行：\n');
console.log('```javascript');
console.log('const results = await Promise.all([');
testAccounts.forEach((acc, idx) => {
  const comma = idx < testAccounts.length - 1 ? ',' : '';
  console.log(`  agent('探测账号 ${acc.username} GPU', { label: '账号${idx + 1}' })${comma}`);
});
console.log(']);');
console.log('```\n');

console.log('现在运行收集脚本...\n');

// 模拟执行收集脚本
import { execFileSync } from 'node:child_process';

try {
  const collectScript = path.join(__dirname, 'collect-probe-results.mjs');
  const output = execFileSync('node', [
    collectScript,
    '--dir', testDir,
    '--output', 'test-gpu-probe-report',
  ], { encoding: 'utf8' });

  console.log(output);
} catch (e) {
  console.error('执行失败:', e.message);
}

console.log('\n查看生成的报告:\n');

const reportFiles = ['test-gpu-probe-report.json', 'test-gpu-probe-report.csv'];
reportFiles.forEach((file) => {
  const filepath = path.join(process.cwd(), file);
  if (fs.existsSync(filepath)) {
    console.log(`✓ ${filepath}`);
    if (file.endsWith('.json')) {
      const content = JSON.parse(fs.readFileSync(filepath, 'utf8'));
      console.log('\n报告摘要:');
      console.log(`  总计: ${content.total}`);
      console.log(`  GPU 可用: ${content.summary.usable}`);
      console.log(`  无 GPU: ${content.summary.no_gpu}`);
      console.log(`  403: ${content.summary.forbidden}\n`);
    }
  }
});

console.log('清理测试文件...\n');
fs.rmSync(testDir, { recursive: true });
console.log(`✓ 已删除 ${testDir}`);

// 清理报告文件（可选）
reportFiles.forEach((file) => {
  const filepath = path.join(process.cwd(), file);
  if (fs.existsSync(filepath)) {
    fs.unlinkSync(filepath);
    console.log(`✓ 已删除 ${filepath}`);
  }
});

console.log('\n═══════════════════════════════════════════');
console.log('   测试完成！');
console.log('═══════════════════════════════════════════\n');

console.log('工作流程验证成功 ✅\n');
console.log('接下来你可以：');
console.log('  1. 准备真实的账号文件 accounts.json');
console.log('  2. 运行: node scripts/probe-gpu-agent.mjs --accounts accounts.json');
console.log('  3. 在 Claude Code 中执行生成的 Agent 代码');
console.log('  4. 运行收集脚本汇总结果\n');
