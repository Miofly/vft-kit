#!/usr/bin/env node
/**
 * collect-probe-results.mjs — 收集并汇总 GPU 探测结果
 *
 * 读取临时目录下所有 result-*.json 文件，生成汇总报告
 */

import fs from 'node:fs';
import path from 'node:path';

// ── 参数解析 ──────────────────────────────────────────
const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const m = a.match(/^--([^=]+)(?:=(.*))?$/);
    return m ? [m[1], m[2] ?? true] : [a, true];
  }),
);

const DIR = args.dir || null;
const OUTPUT_PREFIX = args.output || 'gpu-probe-report';

if (!DIR) {
  console.error('✗ 缺少参数: --dir <临时目录>');
  console.error('用法:');
  console.error('  node collect-probe-results.mjs --dir /path/to/temp --output gpu-probe-report');
  process.exit(1);
}

if (!fs.existsSync(DIR)) {
  console.error(`✗ 目录不存在: ${DIR}`);
  process.exit(1);
}

console.log(`收集结果目录: ${DIR}\n`);

// ── 读取所有结果文件 ─────────────────────────────────
const files = fs.readdirSync(DIR).filter((f) => f.startsWith('result-') && f.endsWith('.json'));

if (!files.length) {
  console.error('✗ 未找到任何结果文件 (result-*.json)');
  console.error('请确认 worker 已执行完成');
  process.exit(1);
}

console.log(`找到 ${files.length} 个结果文件\n`);

const results = [];

for (const file of files) {
  try {
    const raw = fs.readFileSync(path.join(DIR, file), 'utf8');
    const data = JSON.parse(raw);
    results.push(data);
    console.log(`✓ ${file}`);
  } catch (e) {
    console.error(`✗ 读取失败: ${file} - ${e.message}`);
  }
}

if (!results.length) {
  console.error('\n✗ 没有有效的结果数据');
  process.exit(1);
}

console.log(`\n成功读取 ${results.length} 个结果\n`);

// ── 分类统计 ──────────────────────────────────────────
const usable = results.filter((r) => r.cuda === true);
const noGpu = results.filter((r) => r.cuda === false);
const forbidden = results.filter((r) => r.push === '403');
const pushFail = results.filter((r) => r.push !== 'ok' && r.push !== 'ok?' && r.push !== '403');
const unknown = results.filter((r) => r.cuda === null && r.push !== '403' && (r.push === 'ok' || r.push === 'ok?'));

// ── 读取元信息 ────────────────────────────────────────
let meta = null;
const metaPath = path.join(DIR, 'probe-meta.json');
if (fs.existsSync(metaPath)) {
  try {
    meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
  } catch {
    // 忽略
  }
}

// ── 显示汇总 ──────────────────────────────────────────
console.log('═══════════════════════════════════════════');
console.log('            GPU 探测结果');
console.log('═══════════════════════════════════════════\n');
console.log(`总计: ${results.length}`);
console.log(`✅ GPU 可用: ${usable.length}`);
console.log(`❌ 有 token 但无 GPU (未手机验证): ${noGpu.length}`);
console.log(`🚫 push 403 (public 被拒/更严): ${forbidden.length}`);
console.log(`💥 push 失败: ${pushFail.length}`);
console.log(`❔ 未知 (超时/无日志): ${unknown.length}`);

if (usable.length) {
  console.log('\n可用 GPU 账号:');
  for (const r of usable) {
    console.log(`  ${r.username.padEnd(25)} ${r.gpu}${r.count ? ' x' + r.count : ''}${r.cap ? ' (sm_' + r.cap.replace('.', '') + ')' : ''}`);
  }
}

if (noGpu.length) {
  console.log('\n无 GPU 账号 (需手机验证):');
  for (const r of noGpu.slice(0, 10)) {
    console.log(`  ${r.username.padEnd(25)} ${r.note || '-'}`);
  }
  if (noGpu.length > 10) {
    console.log(`  ... 还有 ${noGpu.length - 10} 个`);
  }
}

if (forbidden.length) {
  console.log('\n403 账号:');
  for (const r of forbidden.slice(0, 10)) {
    console.log(`  ${r.username.padEnd(25)} ${r.note || '-'}`);
  }
  if (forbidden.length > 10) {
    console.log(`  ... 还有 ${forbidden.length - 10} 个`);
  }
}

// ── 输出报告文件 ──────────────────────────────────────
const reportSuffix = meta?.accelerator ? '-' + meta.accelerator.replace(/^NvidiaTesla/i, '').toLowerCase() : '';
const outputDir = process.cwd();
const jsonPath = path.join(outputDir, `${OUTPUT_PREFIX}${reportSuffix}.json`);
const csvPath = path.join(outputDir, `${OUTPUT_PREFIX}${reportSuffix}.csv`);

const report = {
  accelerator: meta?.accelerator || null,
  collected_at: new Date().toISOString(),
  probe_started_at: meta?.created_at || null,
  total: results.length,
  summary: {
    usable: usable.length,
    no_gpu: noGpu.length,
    forbidden: forbidden.length,
    push_fail: pushFail.length,
    unknown: unknown.length,
  },
  results: results.sort((a, b) => {
    // 排序: GPU可用 > 无GPU > 403 > 失败 > 未知
    const priority = (r) => {
      if (r.cuda === true) return 0;
      if (r.cuda === false) return 1;
      if (r.push === '403') return 2;
      if (r.push !== 'ok' && r.push !== 'ok?') return 3;
      return 4;
    };
    return priority(a) - priority(b);
  }),
};

fs.writeFileSync(jsonPath, JSON.stringify(report, null, 2));
console.log(`\n报告已保存:`);
console.log(`  JSON: ${jsonPath}`);

// CSV 格式
const csvHeader = 'username,push,status,cuda,gpu,cap,count,note\n';
const csvRows = results.map((r) => {
  return [
    r.username,
    r.push,
    r.status,
    r.cuda,
    r.gpu,
    r.cap,
    r.count,
    (r.note || '').replace(/,/g, ';'),
  ].join(',');
}).join('\n');

fs.writeFileSync(csvPath, csvHeader + csvRows);
console.log(`  CSV:  ${csvPath}`);

// ── 清理提示 ──────────────────────────────────────────
console.log('\n提示: 可以删除临时目录');
console.log(`  rm -rf ${DIR}`);

console.log('\n═══════════════════════════════════════════\n');
