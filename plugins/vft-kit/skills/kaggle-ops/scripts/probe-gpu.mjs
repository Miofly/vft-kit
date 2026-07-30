#!/usr/bin/env node
/**
 * probe-gpu.mjs — 探测 Kaggle 账号的真实 GPU 可用性（通用版本）
 *
 * 这是纯工具脚本，不依赖特定的账号来源。账号来源由调用方决定（DB、CSV、配置文件等）。
 *
 * 背景：
 *   - Token 能鉴权 ≠ 账号能用 GPU
 *   - Kaggle GPU 需要手机验证
 *   - `gpu_remaining_seconds` 只是元数据，未验证账号也返回
 *
 * 唯一可靠判定：推送最小 probe kernel，解析 torch.cuda.is_available()
 *
 * 账号输入方式：
 *   1. JSON 文件：--accounts accounts.json
 *      格式：[{"username":"xxx","token":"KGAT_xxx"}, ...]
 *   2. 单个账号：--username xxx --token KGAT_xxx
 *  3. 环境变量：KAGGLE_USERNAME + KAGGLE_API_TOKEN
 *
 * 用法：
 *   node probe-gpu.mjs --accounts accounts.json
 *   node probe-gpu.mjs --accounts accounts.json --limit 5
 *   node probe-gpu.mjs --username xxx --token KGAT_xxx
 *   node probe-gpu.mjs --accounts accounts.json --concurrency 6
 *
 * 输出：gpu-probe-report.json + gpu-probe-report.csv
 */

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const execFileP = promisify(execFile);
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
const CONCURRENCY = Math.max(1, parseInt(args.concurrency || '6', 10));
const POLL_MAX_SEC = Math.max(120, parseInt(args['poll-max'] || '300', 10));
const POLL_INTERVAL = 15;
const KAGGLE_BIN = process.env.KAGGLE_BIN || 'kaggle';
const ACCELERATOR = args.accelerator || null;
const OUTPUT_PREFIX = args.output || 'gpu-probe-report';

// ── 隔离环境 ──────────────────────────────────────────
const PROBE_HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'kprobe-home-'));
function kaggleEnv(token) {
  const e = { ...process.env, KAGGLE_API_TOKEN: token, HOME: PROBE_HOME };
  delete e.KAGGLE_CONFIG_DIR;
  return e;
}

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

console.log(`待探测账号数=${accounts.length}  并发=${CONCURRENCY}  单账号最长等待=${POLL_MAX_SEC}s`);
console.log(`加速器=${ACCELERATOR || '默认 GPU'}\n`);

// ── Probe kernel 脚本 ─────────────────────────────────
const PROBE_PY = `
import json, sys
try:
    import torch
    ok = torch.cuda.is_available()
    name = torch.cuda.get_device_name(0) if ok else ""
    cap = ".".join(map(str, torch.cuda.get_device_capability(0))) if ok else ""
    count = torch.cuda.device_count() if ok else 0
    print("PROBE_RESULT " + json.dumps({"cuda": ok, "gpu": name, "cap": cap, "count": count}))
except Exception as e:
    print("PROBE_RESULT " + json.dumps({"cuda": False, "err": str(e)}))
sys.stdout.flush()
`.trim();

// ── 单账号探测流程 ───────────────────────────────────
async function probeAccount(acc) {
  const rec = { username: acc.username, push: '?', status: '?', cuda: null, gpu: '', cap: '', count: 0, note: '' };
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), `kprobe-${acc.username}-`));
  const slug = `gpuprobe-${Date.now().toString().slice(-7)}`;
  const kernelId = `${acc.username}/${slug}`;
  let pushedKernelId = kernelId;

  try {
    fs.writeFileSync(path.join(dir, 'probe.py'), PROBE_PY);
    fs.writeFileSync(path.join(dir, 'kernel-metadata.json'), JSON.stringify({
      id: kernelId,
      title: slug,
      code_file: 'probe.py',
      language: 'python',
      kernel_type: 'script',
      is_private: true,
      enable_gpu: true,
      enable_internet: false,
      dataset_sources: [],
      competition_sources: [],
      kernel_sources: [],
      model_sources: [],
    }, null, 2));

    const env = kaggleEnv(acc.token);
    
    // Push kernel
    let pushed = false;
    for (let attempt = 1; attempt <= 3 && !pushed; attempt++) {
      try {
        const pushArgs = ['kernels', 'push'];
        if (ACCELERATOR) pushArgs.push('--accelerator', ACCELERATOR);
        pushArgs.push('-p', dir);
        const { stdout } = await execFileP(KAGGLE_BIN, pushArgs, { env, timeout: 60000 });
        rec.push = /successfully pushed/i.test(stdout) ? 'ok' : 'ok?';
        const pushedUrl = stdout.match(/https:\/\/www\.kaggle\.com\/code\/([^/\s]+)\/([^?\s]+)/i);
        if (pushedUrl) pushedKernelId = `${decodeURIComponent(pushedUrl[1])}/${decodeURIComponent(pushedUrl[2])}`;
        pushed = true;
      } catch (e) {
        const msg = (e.stdout || '') + (e.stderr || '') + (e.message || '');
        if (/403|Forbidden/i.test(msg)) { rec.push = '403'; rec.note = 'public/未验证被拒'; return rec; }
        if (attempt === 3) { rec.push = 'fail'; rec.note = msg.split('\n').find((l) => l.trim())?.slice(0, 80) || 'push失败'; return rec; }
        await new Promise((r) => setTimeout(r, 3000 * attempt));
      }
    }

    // Poll status
    const t0 = Date.now();
    let term = null;
    while ((Date.now() - t0) / 1000 < POLL_MAX_SEC) {
      await new Promise((r) => setTimeout(r, POLL_INTERVAL * 1000));
      try {
        const { stdout } = await execFileP(KAGGLE_BIN, ['kernels', 'status', pushedKernelId], { env, timeout: 30000 });
        const m = stdout.match(/KernelWorkerStatus\.([A-Z]+)/);
        const st = m ? m[1] : '';
        if (['COMPLETE', 'ERROR', 'CANCEL_ACKNOWLEDGED', 'CANCEL_REQUESTED'].includes(st)) { term = st; break; }
      } catch { /* 忽略瞬时错误 */ }
    }
    rec.status = term || 'TIMEOUT';

    // Download logs
    try {
      const { stdout } = await execFileP(KAGGLE_BIN, ['kernels', 'output', pushedKernelId, '-p', dir], { env, timeout: 60000 });
      void stdout;
      const logFile = fs.readdirSync(dir).find((f) => f.endsWith('.log'));
      if (logFile) {
        const raw = fs.readFileSync(path.join(dir, logFile), 'utf8');
        let log = raw;
        try {
          const arr = JSON.parse(raw);
          if (Array.isArray(arr)) log = arr.map((e) => e.data || '').join('');
        } catch { /* 非标准 JSON 数组 */ }
        const pm = log.match(/PROBE_RESULT (\{[^\n]*\})/);
        if (pm) {
          const r = JSON.parse(pm[1]);
          rec.cuda = !!r.cuda;
          rec.gpu = r.gpu || '';
          rec.cap = r.cap || '';
          rec.count = Number(r.count || 0);
          if (r.err) rec.note = String(r.err).slice(0, 60);
        } else if (/CUDA 不可用|is_available\(\)|no CUDA|CUDA unavailable/i.test(log)) {
          rec.cuda = false;
        } else {
          rec.note = rec.note || '日志无 PROBE_RESULT';
        }
      } else {
        rec.note = rec.note || '无日志文件';
      }
    } catch (e) {
      rec.note = rec.note || ('拉日志失败:' + (e.message || '').slice(0, 40));
    }
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  return rec;
}

// ── 并发池 ────────────────────────────────────────────
async function runPool(items, worker, concurrency) {
  const out = new Array(items.length);
  let idx = 0;
  async function next() {
    const i = idx++;
    if (i >= items.length) return;
    out[i] = await worker(items[i], i);
    const r = out[i];
    const flag = r.cuda === true ? '✅GPU' : r.push === '403' ? '🚫403' : r.push !== 'ok' && r.push !== 'ok?' ? '💥push' : r.cuda === false ? '❌无GPU' : '❔';
    console.log(`  [${i + 1}/${items.length}] ${r.username.padEnd(22)} ${flag}  status=${r.status} gpu=${r.gpu || '-'}${r.count ? ` x${r.count}` : ''}${r.note ? '  (' + r.note + ')' : ''}`);
    await next();
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, next));
  return out;
}

console.log('开始探测（每个账号 push→poll→log，耐心等）...\n');
const results = await runPool(accounts, probeAccount, CONCURRENCY);

// ── 汇总 ──────────────────────────────────────────────
const usable = results.filter((r) => r.cuda === true);
const noGpu = results.filter((r) => r.cuda === false);
const forbidden = results.filter((r) => r.push === '403');
const pushFail = results.filter((r) => r.push !== 'ok' && r.push !== 'ok?' && r.push !== '403');
const unknown = results.filter((r) => r.cuda === null && r.push !== '403' && (r.push === 'ok' || r.push === 'ok?'));

console.log('\n═══════════════════════════════════════════');
console.log('            GPU 探测结果');
console.log('═══════════════════════════════════════════\n');
console.log(`总计: ${results.length}`);
console.log(`✅ GPU 可用: ${usable.length}`);
console.log(`❌ 有 token 但无 GPU(未手机验证): ${noGpu.length}`);
console.log(`🚫 push 403(public 被拒/更严): ${forbidden.length}`);
console.log(`💥 push 失败: ${pushFail.length}`);
console.log(`❔ 未知(超时/无日志): ${unknown.length}`);
if (usable.length) {
  console.log('\n可用 GPU 账号:');
  for (const r of usable) console.log(`  ${r.username}  ${r.gpu}${r.count ? ' x' + r.count : ''}${r.cap ? ' (sm_' + r.cap.replace('.', '') + ')' : ''}`);
}

// ── 输出报告 ──────────────────────────────────────────
// 输出到 other/temp/kaggle/ 而非脚本目录
const repoRoot = path.resolve(__dirname, '../../../../..');
const tempDir = path.join(repoRoot, 'other/temp/kaggle');
fs.mkdirSync(tempDir, { recursive: true });

const reportSuffix = ACCELERATOR ? '-' + ACCELERATOR.replace(/^NvidiaTesla/i, '').toLowerCase() : '';
const jsonPath = path.join(tempDir, `${OUTPUT_PREFIX}${reportSuffix}.json`);
const csvPath = path.join(tempDir, `${OUTPUT_PREFIX}${reportSuffix}.csv`);
fs.writeFileSync(jsonPath, JSON.stringify({ accelerator: ACCELERATOR, at: new Date().toISOString(), results }, null, 2));
fs.writeFileSync(csvPath, 'username,push,status,cuda,gpu,cap,count,note\n' +
  results.map((r) => [r.username, r.push, r.status, r.cuda, r.gpu, r.cap, r.count, (r.note || '').replace(/,/g, ';')].join(','))).join('\n'));
console.log(`\n报告: ${jsonPath}\n      ${csvPath}`);

fs.rmSync(PROBE_HOME, { recursive: true, force: true });
