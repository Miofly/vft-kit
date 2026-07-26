#!/usr/bin/env node
/**
 * probe-gpu-worker.mjs — 单账号 GPU 探测 Worker
 *
 * 由 probe-gpu-agent.mjs 调用，每个 Worker 负责一个账号的探测
 * 输出结果到 JSON 文件，供后续汇总
 */

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const execFileP = promisify(execFile);

// ── 参数解析 ──────────────────────────────────────────
const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const m = a.match(/^--([^=]+)(?:=(.*))?$/);
    return m ? [m[1], m[2] ?? true] : [a, true];
  }),
);

const ACCOUNT_FILE = args['account-file'] || null;
const USERNAME = args.username || process.env.KAGGLE_USERNAME || null;
const TOKEN = args.token || process.env.KAGGLE_API_TOKEN || null;
const POLL_MAX_SEC = Math.max(120, parseInt(args['poll-max'] || '300', 10));
const POLL_INTERVAL = 15;
const KAGGLE_BIN = process.env.KAGGLE_BIN || 'kaggle';
const ACCELERATOR = args.accelerator || null;

// ── 读取账号 ─────────────────────────────────────────
let account = null;

if (ACCOUNT_FILE) {
  try {
    const raw = fs.readFileSync(ACCOUNT_FILE, 'utf8');
    account = JSON.parse(raw);
    if (!account.username || !account.token) {
      throw new Error('账号格式错误: 缺少 username 或 token');
    }
  } catch (e) {
    console.error(`✗ 读取账号文件失败: ${e.message}`);
    process.exit(1);
  }
} else if (USERNAME && TOKEN) {
  account = { username: USERNAME, token: TOKEN };
} else {
  console.error('✗ 缺少账号输入');
  console.error('用法:');
  console.error('  --account-file account.json');
  console.error('  或 --username xxx --token KGAT_xxx');
  process.exit(1);
}

console.log(`[Worker] 探测账号: ${account.username}`);

// ── 隔离环境 ──────────────────────────────────────────
const PROBE_HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'kprobe-home-'));
function kaggleEnv(token) {
  const e = { ...process.env, KAGGLE_API_TOKEN: token, HOME: PROBE_HOME };
  delete e.KAGGLE_CONFIG_DIR;
  return e;
}

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

// ── 探测流程 ──────────────────────────────────────────
async function probeAccount(acc) {
  const rec = {
    username: acc.username,
    push: '?',
    status: '?',
    cuda: null,
    gpu: '',
    cap: '',
    count: 0,
    note: '',
    started_at: new Date().toISOString(),
  };

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), `kprobe-${acc.username}-`));
  const slug = `gpuprobe-${Date.now().toString().slice(-7)}`;
  const kernelId = `${acc.username}/${slug}`;
  let pushedKernelId = kernelId;

  try {
    // 准备 kernel 文件
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

    console.log(`[${acc.username}] 开始 push kernel...`);

    // Push kernel（带重试）
    let pushed = false;
    for (let attempt = 1; attempt <= 3 && !pushed; attempt++) {
      try {
        const pushArgs = ['kernels', 'push'];
        if (ACCELERATOR) pushArgs.push('--accelerator', ACCELERATOR);
        pushArgs.push('-p', dir);

        const { stdout } = await execFileP(KAGGLE_BIN, pushArgs, { env, timeout: 60000 });
        rec.push = /successfully pushed/i.test(stdout) ? 'ok' : 'ok?';

        // 提取实际的 kernel ID
        const pushedUrl = stdout.match(/https:\/\/www\.kaggle\.com\/code\/([^/\s]+)\/([^?\s]+)/i);
        if (pushedUrl) {
          pushedKernelId = `${decodeURIComponent(pushedUrl[1])}/${decodeURIComponent(pushedUrl[2])}`;
        }

        console.log(`[${acc.username}] ✓ Push 成功: ${pushedKernelId}`);
        pushed = true;
      } catch (e) {
        const msg = (e.stdout || '') + (e.stderr || '') + (e.message || '');

        if (/403|Forbidden/i.test(msg)) {
          rec.push = '403';
          rec.note = 'public/未验证被拒';
          console.log(`[${acc.username}] ✗ Push 403 (未验证)`);
          return rec;
        }

        if (attempt === 3) {
          rec.push = 'fail';
          rec.note = msg.split('\n').find((l) => l.trim())?.slice(0, 80) || 'push失败';
          console.log(`[${acc.username}] ✗ Push 失败: ${rec.note}`);
          return rec;
        }

        console.log(`[${acc.username}] Push 重试 ${attempt}/3...`);
        await new Promise((r) => setTimeout(r, 3000 * attempt));
      }
    }

    // Poll status
    console.log(`[${acc.username}] 轮询状态 (最长 ${POLL_MAX_SEC}s)...`);
    const t0 = Date.now();
    let term = null;

    while ((Date.now() - t0) / 1000 < POLL_MAX_SEC) {
      await new Promise((r) => setTimeout(r, POLL_INTERVAL * 1000));

      try {
        const { stdout } = await execFileP(KAGGLE_BIN, ['kernels', 'status', pushedKernelId], { env, timeout: 30000 });
        const m = stdout.match(/KernelWorkerStatus\.([A-Z_]+)/);
        const st = m ? m[1] : '';

        if (['COMPLETE', 'ERROR', 'CANCEL_ACKNOWLEDGED', 'CANCEL_REQUESTED'].includes(st)) {
          term = st;
          console.log(`[${acc.username}] 状态: ${term}`);
          break;
        }
      } catch {
        // 忽略瞬时错误
      }
    }

    rec.status = term || 'TIMEOUT';
    if (rec.status === 'TIMEOUT') {
      console.log(`[${acc.username}] ⏱ 超时`);
    }

    // Download logs
    console.log(`[${acc.username}] 下载日志...`);
    try {
      const { stdout } = await execFileP(KAGGLE_BIN, ['kernels', 'output', pushedKernelId, '-p', dir], { env, timeout: 60000 });
      void stdout;

      const logFile = fs.readdirSync(dir).find((f) => f.endsWith('.log'));
      if (logFile) {
        const raw = fs.readFileSync(path.join(dir, logFile), 'utf8');
        let log = raw;

        // 尝试解析 JSON 数组格式的日志
        try {
          const arr = JSON.parse(raw);
          if (Array.isArray(arr)) log = arr.map((e) => e.data || '').join('');
        } catch {
          // 非标准 JSON 数组格式
        }

        // 解析 PROBE_RESULT
        const pm = log.match(/PROBE_RESULT (\{[^\n]*\})/);
        if (pm) {
          const r = JSON.parse(pm[1]);
          rec.cuda = !!r.cuda;
          rec.gpu = r.gpu || '';
          rec.cap = r.cap || '';
          rec.count = Number(r.count || 0);
          if (r.err) rec.note = String(r.err).slice(0, 60);

          console.log(`[${acc.username}] ${rec.cuda ? '✅ GPU 可用' : '❌ GPU 不可用'}: ${rec.gpu}`);
        } else if (/CUDA 不可用|is_available\(\)|no CUDA|CUDA unavailable/i.test(log)) {
          rec.cuda = false;
          console.log(`[${acc.username}] ❌ GPU 不可用 (日志匹配)`);
        } else {
          rec.note = rec.note || '日志无 PROBE_RESULT';
          console.log(`[${acc.username}] ❔ 无法解析结果`);
        }
      } else {
        rec.note = rec.note || '无日志文件';
        console.log(`[${acc.username}] ✗ 无日志文件`);
      }
    } catch (e) {
      rec.note = rec.note || ('拉日志失败:' + (e.message || '').slice(0, 40));
      console.log(`[${acc.username}] ✗ 拉日志失败: ${e.message}`);
    }
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }

  rec.finished_at = new Date().toISOString();
  return rec;
}

// ── 执行探测 ──────────────────────────────────────────
const result = await probeAccount(account);

// ── 输出结果 ──────────────────────────────────────────
// 输出到同目录下，以账号名命名
const resultDir = ACCOUNT_FILE ? path.dirname(ACCOUNT_FILE) : process.cwd();
const resultFile = path.join(resultDir, `result-${account.username}.json`);

fs.writeFileSync(resultFile, JSON.stringify(result, null, 2));
console.log(`[${account.username}] 结果已保存: ${resultFile}`);

// 清理
fs.rmSync(PROBE_HOME, { recursive: true, force: true });

// 输出简化结果到 stdout（方便 agent 返回）
const summary = {
  username: result.username,
  cuda: result.cuda,
  gpu: result.gpu,
  status: result.status,
  note: result.note,
};
console.log('\n=== RESULT ===');
console.log(JSON.stringify(summary, null, 2));
