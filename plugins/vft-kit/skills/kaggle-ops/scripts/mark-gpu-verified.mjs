#!/usr/bin/env node
/**
 * mark-gpu-verified.mjs — 解析 GPU probe 报告并生成结果文件（通用版本）
 *
 * 这是纯工具脚本，只处理报告解析，不依赖特定的数据存储。
 * 结果如何使用（回写 DB、更新 CSV、同步到其他系统）由调用方决定。
 *
 * 功能:
 *   1. 读取 GPU probe 报告（probe-gpu.mjs 生成的 JSON）
 *   2. 分类账号（GPU 可用 / 不可用）
 *   3. 生成结构化结果文件（JSON 格式）
 *
 * 用法:
 *   node mark-gpu-verified.mjs --report gpu-probe-report.json
 *   node mark-gpu-verified.mjs --report gpu-probe-report-t4.json --output verified.json
 *
 * 输出格式:
 *   {
 *     "gpu_verified": [
 *       {"username": "xxx", "gpu": "Tesla T4", "cap": "7.5", "count": 1}
 *     ],
 *     "gpu_not_verified": [
 *       {"username": "yyy", "note": "未手机验证"}
 *     ],
 *     "summary": {
 *       "total": 71,
 *       "gpu_ok": 28,
 *       "gpu_no": 43,
 *       "checked_at": "2026-07-26T10:00:00.000Z"
 *     }
 *   }
 *
 * 调用方可以读取这个结果文件，根据自己的需求处理，例如：
 *   - 回写数据库
 *   - 更新 CSV
 *   - 同步到配置管理系统
 *   - 发送通知
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

const REPORT_PATH = args.report || null;
const OUTPUT_PATH = args.output || 'gpu-verified-result.json';

if (!REPORT_PATH) {
  console.error('✗ 缺少 --report 参数');
  console.error('用法: node mark-gpu-verified.mjs --report gpu-probe-report.json');
  process.exit(1);
}

// ── 读取报告 ──────────────────────────────────────────
const reportPath = path.isAbsolute(REPORT_PATH) ? REPORT_PATH : path.resolve(REPORT_PATH);
if (!fs.existsSync(reportPath)) {
  console.error(`✗ 未找到报告文件: ${reportPath}`);
  process.exit(1);
}

let report;
try {
  report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
} catch (e) {
  console.error(`✗ 读取报告文件失败: ${e.message}`);
  process.exit(1);
}

if (!Array.isArray(report.results)) {
  console.error('✗ 报告格式错误: 缺少 results 数组');
  process.exit(1);
}

// ── 分类账号 ──────────────────────────────────────────
const gpuVerified = [];
const gpuNotVerified = [];

for (const r of report.results) {
  if (r.cuda === true) {
    gpuVerified.push({
      username: r.username,
      gpu: r.gpu || '',
      capability: r.cap || '',
      count: r.count || 1,
      accelerator: r.gpu ? r.gpu.replace(/^Tesla\s+/i, '') : '',
    });
  } else {
    gpuNotVerified.push({
      username: r.username,
      note: r.note || (r.push === '403' ? 'push 403' : r.push === 'fail' ? 'push 失败' : '无 GPU'),
    });
  }
}

// ── 生成结果 ──────────────────────────────────────────
const result = {
  gpu_verified: gpuVerified,
  gpu_not_verified: gpuNotVerified,
  summary: {
    total: report.results.length,
    gpu_ok: gpuVerified.length,
    gpu_no: gpuNotVerified.length,
    checked_at: report.at || new Date().toISOString(),
    accelerator: report.accelerator || null,
  },
};

// ── 输出结果 ──────────────────────────────────────────
const outputPath = path.isAbsolute(OUTPUT_PATH) ? OUTPUT_PATH : path.resolve(OUTPUT_PATH);
fs.writeFileSync(outputPath, JSON.stringify(result, null, 2));

console.log('═══════════════════════════════════════════');
console.log('            GPU 验证结果处理完成');
console.log('═══════════════════════════════════════════\n');
console.log(`总计: ${result.summary.total}`);
console.log(`✅ GPU 可用: ${result.summary.gpu_ok}`);
console.log(`❌ GPU 不可用: ${result.summary.gpu_no}`);
console.log(`\n结果文件: ${outputPath}`);
console.log('\n调用方可以读取此文件并根据需求处理（回写 DB / 更新 CSV / 发送通知等）');
