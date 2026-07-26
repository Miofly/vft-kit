#!/usr/bin/env node
/**
 * example-agent-probe.mjs — Agent 并发探测示例
 *
 * 演示如何在 Claude Code 中使用 Agent 并发探测 Kaggle GPU
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

console.log('═══════════════════════════════════════════');
console.log('   Agent 并发 GPU 探测 - 使用示例');
console.log('═══════════════════════════════════════════\n');

console.log('这是一个示例，展示如何使用 Agent 并发探测多个 Kaggle 账号的 GPU 可用性。\n');

// 示例账号数据（请替换为真实数据）
const exampleAccounts = [
  { username: 'user1', token: 'KGAT_example1' },
  { username: 'user2', token: 'KGAT_example2' },
  { username: 'user3', token: 'KGAT_example3' },
  { username: 'user4', token: 'KGAT_example4' },
  { username: 'user5', token: 'KGAT_example5' },
];

console.log('步骤 1: 准备账号文件\n');
console.log('创建一个 JSON 文件，格式如下：\n');
console.log('```json');
console.log(JSON.stringify(exampleAccounts, null, 2));
console.log('```\n');

console.log('假设保存为: accounts.json\n');

console.log('步骤 2: 运行 probe-gpu-agent.mjs\n');
console.log('```bash');
console.log('node scripts/probe-gpu-agent.mjs --accounts accounts.json --concurrency 5');
console.log('```\n');

console.log('这会生成临时文件和 Agent 调用指令。\n');

console.log('步骤 3: 在 Claude Code 中执行 Agent 任务\n');
console.log('脚本会输出类似下面的代码，复制到 Claude Code 中执行：\n');

console.log('```javascript');
console.log('// 方式1：使用 Agent 工具（推荐）');
console.log('const results = await Promise.all([');
exampleAccounts.forEach((acc, idx) => {
  const comma = idx < exampleAccounts.length - 1 ? ',' : '';
  console.log(`  agent('探测账号 ${acc.username} GPU', {`);
  console.log(`    label: '账号${idx + 1}'`);
  console.log(`  }).then(() => 'node scripts/probe-gpu-worker.mjs --account-file .tmp-probe-accounts/account-${idx + 1}-${acc.username}.json')${comma}`);
});
console.log(']);');
console.log('```\n');

console.log('或者：\n');

console.log('```bash');
console.log('# 方式2：使用 Bash 后台任务');
exampleAccounts.forEach((acc, idx) => {
  console.log(`node scripts/probe-gpu-worker.mjs --account-file .tmp-probe-accounts/account-${idx + 1}-${acc.username}.json &`);
});
console.log('wait');
console.log('```\n');

console.log('步骤 4: 收集结果\n');
console.log('```bash');
console.log('node scripts/collect-probe-results.mjs --dir .tmp-probe-accounts --output gpu-probe-report');
console.log('```\n');

console.log('步骤 5: 查看报告\n');
console.log('```bash');
console.log('cat gpu-probe-report.json');
console.log('cat gpu-probe-report.csv');
console.log('```\n');

console.log('步骤 6: 清理临时文件\n');
console.log('```bash');
console.log('rm -rf .tmp-probe-accounts');
console.log('```\n');

console.log('═══════════════════════════════════════════');
console.log('   性能对比');
console.log('═══════════════════════════════════════════\n');

console.log('假设有 10 个账号，每个账号探测需要 3 分钟：\n');
console.log('单进程顺序执行: 10 × 3 = 30 分钟');
console.log('probe-gpu.mjs (并发=5): 6 分钟（2批）');
console.log('probe-gpu-agent.mjs (Agent并发): 3-4 分钟（真正并行）\n');

console.log('Agent 并发的优势：');
console.log('  ✅ 充分利用多核 CPU');
console.log('  ✅ 每个 Agent 独立进程，稳定性更好');
console.log('  ✅ Claude Code 中可视化进度');
console.log('  ✅ 单个账号失败不影响其他账号\n');

console.log('═══════════════════════════════════════════\n');
