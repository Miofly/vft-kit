// AI Studio Notebook runtime + Jupyter API over an authenticated browser Page.
//
// Everything runs inside the logged-in Page (ego-lite `page.evaluate` / `page.fetch`), so cookies and the
// in-page `window.aiStudio.bdToken` never leave the browser and are never printed.
//
// Usage inside `ego-browser nodejs` (ESM):
//   const nb = await import('file:///<skill-dir>/scripts/notebook_api.mjs');
//   await nb.ensureStudioPage(page);
//   const st = await nb.startRuntime(page, { projectId: '123', log: console.log }); // free CPU only by default
//   if (st.blocked) { await task.handOff(); ... }                                       // captcha => user
//   const jp = nb.jupyter(page, st.base);
//   console.log(await jp.exec('print(1+1)'));            // { rc, output, seconds }
//   console.log(await jp.sh('nproc && df -h /home/aistudio'));
//   await nb.stopRuntime(page, { projectId: '123' });
// Offline check: node notebook_api.mjs --self-test
//
// Endpoints (read from the project bundle `project/2117.js` and verified live, see references/notebook.md):
//   POST /studio/project/detail                      form projectId            -> running, projectState, versionList
//   POST /studio/project/cluster/allList             form projectId,startMode  -> tiers / prices
//   POST /studio/user/start/notebook/require/graphic -                        -> result true = captcha needed
//   POST /studio/project/running   form projectId,versionId,scheduleName,startMode=0[,tk,ds after captcha]
//        result.code 201 = launching (call again every 3 s), 200 = up (result.jumpUrl = Codelab URL)
//   POST /studio/project/stop      form projectId,startMode=0                  -> poll detail until running=false
import { fileURLToPath } from 'node:url';

export const SITE = 'https://aistudio.baidu.com';
export const FREE_SCHEDULE = 'normalSchedule'; // 基础版 CPU, 0 点/小时
export const STATE = { running: 300204, running2: 300202, launching: 300200, stopRunning: 300201, stopped: 300400 };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export class CaptchaRequired extends Error {
  constructor(msg) { super(msg); this.name = 'CaptchaRequired'; }
}

export function isCaptchaMessage(s) {
  return /人机验证|验证码|captcha|passMkd/i.test(String(s || ''));
}

// Jupyter server base (".../<region>/user/<owner>/<projectId>/") from a Codelab/jump URL.
export function baseFromJumpUrl(url) {
  const m = String(url || '').match(/^(https:\/\/aistudio\.baidu\.com)?(\/[a-z0-9-]+\/(?:hub\/)?user\/\d+\/\d+\/)/i);
  if (!m) return null;
  return SITE + m[2].replace('/hub/user/', '/user/');
}

// Call a site API inside the page with the in-page studio token. Returns the parsed JSON body.
export async function studio(page, path, { method = 'POST', form, json } = {}) {
  const text = await page.evaluate(async ({ path, method, form, json }) => {
    const h = { 'x-requested-with': 'XMLHttpRequest', 'x-studio-token': (window.aiStudio && window.aiStudio.bdToken) || '' };
    let body;
    if (form) { h['Content-Type'] = 'application/x-www-form-urlencoded'; body = new URLSearchParams(form).toString(); }
    if (json) { h['Content-Type'] = 'application/json'; body = JSON.stringify(json); }
    const r = await fetch(path, { method, credentials: 'include', headers: h, body, cache: 'no-store' });
    return await r.text();
  }, { path, method, form, json });
  let j;
  try { j = JSON.parse(text); } catch { throw new Error(`${path} 非 JSON 响应：${String(text).slice(0, 120)}`); }
  return j;
}

function unpack(path, j) {
  if (j.errorCode !== 0) throw new Error(`${path} errorCode=${j.errorCode} ${j.errorMsg || ''}`);
  return j.result;
}

// Make sure the page is on the site origin and logged in (window.aiStudio.bdToken present).
export async function ensureStudioPage(page) {
  let u = '';
  try { u = String(await page.url()); } catch {}
  const ok = async () => page.evaluate(() => !!(window.aiStudio && window.aiStudio.bdToken));
  // A project edit page re-calls /running by itself while launching; keep API work on a neutral page.
  if (!u.startsWith(SITE) || /\/project\/edit\//.test(u) || !(await ok().catch(() => false))) {
    await page.goto(SITE + '/my/project');
    for (let i = 0; i < 15 && !(await ok().catch(() => false)); i++) await sleep(1000);
  }
  if (!(await ok().catch(() => false))) throw new CaptchaRequired('未登录 AI Studio（页面没有 bdToken），需要用户在浏览器里登录');
}

export async function projectDetail(page, projectId) {
  return unpack('detail', await studio(page, '/studio/project/detail', { form: { projectId } }));
}

export async function clusterList(page, projectId, startMode = 0) {
  return unpack('cluster/allList', await studio(page, '/studio/project/cluster/allList', { form: { projectId, startMode } }));
}

export async function captchaRequired(page) {
  return !!unpack('require/graphic', await studio(page, '/studio/user/start/notebook/require/graphic'));
}

export function summarizeDetail(d) {
  return { projectId: d.projectId, name: d.projectName, running: !!d.running, projectState: d.projectState, cluster: d.runningClusterInfo || null };
}

// Pure decision for one /studio/project/running response. Exported for the self-test.
export function classifyRunResponse(j) {
  if (!j || typeof j !== 'object') return { kind: 'error', msg: 'empty response' };
  const r = j.result || {};
  if (j.errorCode === 8307) return { kind: 'error', msg: `8307 ${j.errorMsg || ''}` };
  if (j.errorCode !== 0) return { kind: isCaptchaMessage(j.errorMsg) ? 'captcha' : 'error', msg: `errorCode=${j.errorCode} ${j.errorMsg || ''}` };
  if (isCaptchaMessage(r.msg)) return { kind: 'captcha', msg: `code=${r.code} ${r.msg}` };
  if (r.code === 201) return { kind: 'launching', msg: r.msg || '' };
  if (r.code === 200) return { kind: 'up', jumpUrl: r.jumpUrl || '', startMode: r.startMode };
  return { kind: 'error', msg: `code=${r.code} ${r.msg || ''}` };
}

// Captured from the UI (2026-10-13): projectId,versionId,scheduleName,startMode=0; tk/ds only after a passport
// captcha. Sending startMode='notebook' or empty tk/ds returns errorCode 500 参数错误.
export function runForm({ projectId, versionId = 0, scheduleName = FREE_SCHEDULE, startMode = 0, tk, ds }) {
  const f = { projectId: String(projectId), versionId: String(versionId), scheduleName, startMode };
  if (tk) f.tk = tk;
  if (ds) f.ds = ds;
  return f;
}

// Start (or attach to) a Notebook runtime. Refuses any tier other than the free CPU unless allowPaid is set
// by a caller that already obtained explicit cost confirmation. Returns { base, jumpUrl, detail } or
// { blocked: 'captcha', reason } when the site wants a human verification (never auto-solved here).
export async function startRuntime(page, { projectId, scheduleName = FREE_SCHEDULE, allowPaid = false, versionId, startMode = 0, timeoutMs = 10 * 60_000, log = () => {} } = {}) {
  if (!/^\d+$/.test(String(projectId || ''))) throw new Error('projectId 必须是数字');
  if (scheduleName !== FREE_SCHEDULE && !allowPaid) throw new Error(`拒绝启动 ${scheduleName}：非免费档需调用方先确认费用并传 allowPaid`);
  await ensureStudioPage(page);
  const d0 = await projectDetail(page, projectId);
  if (d0.running && d0.runningClusterInfo && scheduleName === FREE_SCHEDULE && /GPU|V100|A100/i.test(JSON.stringify(d0.runningClusterInfo))) {
    throw new Error(`项目已在 GPU 上运行 ${JSON.stringify(d0.runningClusterInfo)}，不接管`);
  }
  const vid = versionId ?? (d0.versionList && d0.versionList[0] ? d0.versionList[0].versionId : 0);
  if (!d0.running && (await captchaRequired(page))) return { blocked: 'captcha', reason: 'require/graphic=true，启动需要人机验证' };
  const deadline = Date.now() + timeoutMs;
  let n = 0;
  while (Date.now() < deadline) {
    const j = await studio(page, '/studio/project/running', { form: runForm({ projectId, versionId: vid, scheduleName, startMode }) });
    const c = classifyRunResponse(j);
    n++;
    if (c.kind === 'captcha') return { blocked: 'captcha', reason: c.msg };
    if (c.kind === 'error') throw new Error(`启动失败：${c.msg}`);
    if (c.kind === 'up') {
      const base = baseFromJumpUrl(c.jumpUrl);
      const detail = summarizeDetail(await projectDetail(page, projectId));
      const cost = detail.cluster && detail.cluster.costPerHour;
      if (!allowPaid && cost != null && Number(cost) !== 0) {
        await stopRuntime(page, { projectId });
        throw new Error(`运行档位 ${detail.cluster.displayName} costPerHour=${cost} 非免费，已立即停止`);
      }
      log(`RUNNING after ${n} calls`);
      return { base, jumpUrl: c.jumpUrl ? c.jumpUrl.replace(/[?#].*$/, '') : '', detail, calls: n };
    }
    if (n % 10 === 1) log(`launching (${n})`);
    await sleep(3000);
  }
  throw new Error(`启动超时 ${timeoutMs} ms，仍在 launching；请用 status 复查，必要时 stop`);
}

export async function stopRuntime(page, { projectId, startMode = 0, timeoutMs = 3 * 60_000, log = () => {} } = {}) {
  await ensureStudioPage(page);
  let d = await projectDetail(page, projectId);
  if (!d.running && d.projectState === STATE.stopped) return { stopped: true, already: true, detail: summarizeDetail(d) };
  const deadline = Date.now() + timeoutMs;
  let calls = 0;
  while (Date.now() < deadline) {
    if (calls < 20) {
      const j = await studio(page, '/studio/project/stop', { form: { projectId, startMode } });
      calls++;
      if (j.errorCode !== 0) log(`stop errorCode=${j.errorCode} ${j.errorMsg || ''}`);
    }
    await sleep(4000);
    d = await projectDetail(page, projectId);
    if (!d.running && d.projectState === STATE.stopped) return { stopped: true, calls, detail: summarizeDetail(d) };
  }
  return { stopped: false, calls, detail: summarizeDetail(d) };
}

// ---------- Jupyter server (Contents / Terminals / Files) ----------
// Measured on AI Studio (2026-10-13, bj-cpu-01): GET/PUT/DELETE api/contents, GET files/, POST/DELETE api/terminals
// and the terminal WebSocket work with the page cookies alone. POST api/kernels returns 404 and POST api/sessions
// returns 490 through the AI Studio proxy, so commands run through a disposable terminal: the command is written to
// a script under JOB_DIR, started detached with setsid (survives terminal deletion), and its log/rc files are polled
// through the Contents API. No kernel and no long-held socket are needed.

export const JOB_DIR = 'nbapi-jobs'; // relative to /home/aistudio (Contents API rejects hidden dirs with 400); files removed after collection

export function contentPath(p) {
  let value = String(p || '');
  if (value === '/home/aistudio') return '';
  if (value.startsWith('/home/aistudio/')) value = value.slice('/home/aistudio/'.length);
  if (value.startsWith('/') || value.split('/').includes('..')) throw new Error('Contents path must be relative to /home/aistudio');
  return value;
}
function enc(p) { return contentPath(p).split('/').filter(Boolean).map(encodeURIComponent).join('/'); }
const shq = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'";

// Shell line typed into the terminal. Exported for the self-test.
export function launchLine(id, dir = JOB_DIR) {
  const d = '/home/aistudio/' + dir;
  return `setsid nohup bash -c ${shq(`cd /home/aistudio; bash ${d}/${id}.sh > ${d}/${id}.log 2>&1; echo $? > ${d}/${id}.rc`)} > /dev/null 2>&1 < /dev/null & echo NBAPI_LAUNCHED_${id}`;
}

export function newJobId() { return 'j' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6); }

export function jupyter(page, base) {
  if (!base || !/\/user\/\d+\/\d+\/$/.test(base)) throw new Error(`无效 Jupyter base：${base}`);
  const req = async (path, { method = 'GET', json, timeout = 300000 } = {}) => page.fetch(base + path + (method === 'GET' ? (path.includes('?') ? '&' : '?') + '_=' + Date.now() : ''), {
    method, timeout, cache: 'no-store',
    headers: json === undefined ? {} : { 'Content-Type': 'application/json' },
    body: json === undefined ? undefined : JSON.stringify(json),
  });
  const api = {
    base,
    async kernelState(id) {
      if (!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(id)) throw new Error('Invalid kernel id');
      const r = await req('api/kernels/' + id);
      if (!r.ok) throw new Error(`kernel state HTTP ${r.status}`);
      const k = JSON.parse(r.body);
      return { id: k.id, name: k.name, state: k.execution_state };
    },
    async restartKernel(id) {
      if (!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(id)) throw new Error('Invalid kernel id');
      const r = await req('api/kernels/' + id + '/restart', { method: 'POST' });
      if (!r.ok) throw new Error(`kernel restart HTTP ${r.status}`);
      return api.kernelState(id);
    },
    async ls(path = '') {
      const r = await req('api/contents/' + enc(path));
      if (!r.ok) throw new Error(`ls ${path} HTTP ${r.status}`);
      return (JSON.parse(r.body).content || []).map((x) => ({ type: x.type, name: x.name, size: x.size ?? null }));
    },
    async stat(path) {
      const r = await req('api/contents/' + enc(path) + '?content=0');
      if (r.status === 404) return null;
      if (!r.ok) throw new Error(`stat ${path} HTTP ${r.status}`);
      const j = JSON.parse(r.body);
      return { type: j.type, size: j.size ?? null, last_modified: j.last_modified };
    },
    async readText(path, { tailLines = 0 } = {}) {
      const r = await req('api/contents/' + enc(path) + '?content=1&type=file');
      if (r.status === 404) return null;
      if (!r.ok) throw new Error(`read ${path} HTTP ${r.status}`);
      const j = JSON.parse(r.body);
      let t = j.format === 'base64' ? Buffer.from(j.content, 'base64').toString('utf8') : String(j.content ?? '');
      if (tailLines) t = t.split('\n').slice(-tailLines).join('\n');
      return t;
    },
    async mkdirs(path) {
      let cur = '';
      for (const p of contentPath(path).split('/').filter(Boolean)) {
        cur = cur ? cur + '/' + p : p;
        if (await api.stat(cur)) continue;
        const r = await req('api/contents/' + enc(cur), { method: 'PUT', json: { type: 'directory' } });
        if (!r.ok) throw new Error(`mkdir ${cur} HTTP ${r.status}`);
      }
    },
    async putBuffer(remote, buf) {
      remote = contentPath(remote);
      const dir = String(remote).split('/').slice(0, -1).join('/');
      if (dir) await api.mkdirs(dir);
      const r = await req('api/contents/' + enc(remote), { method: 'PUT', json: { type: 'file', format: 'base64', content: Buffer.from(buf).toString('base64') } });
      if (!r.ok) throw new Error(`put ${remote} HTTP ${r.status}`);
      const s = await api.stat(remote);
      if (!s || s.size !== buf.length) throw new Error(`put ${remote} 回读大小不符 ${s && s.size} != ${buf.length}`);
      return { path: remote, size: buf.length };
    },
    async putText(remote, text) { return api.putBuffer(remote, Buffer.from(String(text), 'utf8')); },
    // Raw download via the Jupyter `files/` handler, saved straight to an absolute local path.
    async download(remote, localAbs) {
      const r = await page.fetch(base + 'files/' + enc(remote) + '?_=' + Date.now(), { saveAs: localAbs, timeout: 1800000 });
      if (r && r.ok === false) throw new Error(`download ${remote} HTTP ${r.status}`);
      return r;
    },
    async rm(path) {
      const r = await req('api/contents/' + enc(path), { method: 'DELETE' });
      if (!r.ok && r.status !== 404) throw new Error(`rm ${path} HTTP ${r.status}`);
    },
    // Type one line into a fresh terminal, wait for a line equal to `marker` (or timeout), then delete the terminal.
    async typeInTerminal(line, marker, { waitMs = 15000 } = {}) {
      const t = await req('api/terminals', { method: 'POST', json: {} });
      if (!t.ok) throw new Error(`create terminal HTTP ${t.status}`);
      const name = JSON.parse(t.body).name;
      try {
        return await page.evaluate(async ({ base, name, line, marker, waitMs }) => {
          const ws = new WebSocket(base.replace(/^http/, 'ws') + 'terminals/websocket/' + name);
          await new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error('terminal ws error')); setTimeout(() => rej(new Error('terminal ws open timeout')), 15000); });
          let buf = '';
          ws.onmessage = (m) => { try { const d = JSON.parse(m.data); if (d[0] === 'stdout') buf += d[1]; } catch {} };
          const seen = () => new RegExp('(^|\\n)' + marker + '\\r?(\\n|$)').test(buf.replace(/\x1b\[[0-9;?]*[a-zA-Z]/g, '').replace(/\r\n/g, '\n'));
          await new Promise((r) => setTimeout(r, 800));
          ws.send(JSON.stringify(['stdin', line + '\r']));
          const t0 = Date.now();
          while (Date.now() - t0 < waitMs && !seen()) await new Promise((r) => setTimeout(r, 300));
          ws.close();
          return seen();
        }, { base, name, line, marker, waitMs });
      } finally {
        await req('api/terminals/' + name, { method: 'DELETE' }).catch(() => {});
      }
    },
    // Start a shell script detached. Returns { id, log, rc } (paths relative to /home/aistudio).
    async spawn(script, { id = newJobId() } = {}) {
      await api.putText(`${JOB_DIR}/${id}.sh`, script);
      const ok = await api.typeInTerminal(launchLine(id), `NBAPI_LAUNCHED_${id}`);
      if (!ok) throw new Error('终端未回显启动标记，命令可能未执行');
      return { id, log: `${JOB_DIR}/${id}.log`, rc: `${JOB_DIR}/${id}.rc`, script: `${JOB_DIR}/${id}.sh` };
    },
    async jobStatus(id) {
      const rcText = await api.readText(`${JOB_DIR}/${id}.rc`);
      const done = rcText != null && rcText.trim() !== '';
      return { done, rc: done ? Number(rcText.trim()) : null };
    },
    async jobCleanup(id) { for (const ext of ['sh', 'log', 'rc']) await api.rm(`${JOB_DIR}/${id}.${ext}`).catch(() => {}); },
    // Run a shell script to completion (poll every pollMs). Returns { id, rc, done, output, seconds }.
    async sh(script, { timeoutMs = 10 * 60_000, pollMs = 2000, tailLines = 200, keepFiles = false } = {}) {
      const t0 = Date.now();
      const job = await api.spawn(script);
      let st = { done: false, rc: null };
      while (Date.now() - t0 < timeoutMs) {
        await sleep(pollMs);
        st = await api.jobStatus(job.id);
        if (st.done) break;
      }
      const output = (await api.readText(job.log, { tailLines })) ?? '';
      if (st.done && !keepFiles) await api.jobCleanup(job.id);
      return { id: job.id, rc: st.rc, done: st.done, output, seconds: Math.round((Date.now() - t0) / 1000) };
    },
    // Run Python source with the container's default python (same env as the notebook kernel).
    async exec(code, opts = {}) {
      const id = newJobId();
      await api.putText(`${JOB_DIR}/${id}.py`, code);
      try { return await api.sh(`python /home/aistudio/${JOB_DIR}/${id}.py`, opts); }
      finally { await api.rm(`${JOB_DIR}/${id}.py`).catch(() => {}); }
    },
    // Upload any size: single PUT up to chunkBytes, otherwise parts + in-box concat + sha256 check.
    async put(localBuf, remote, { chunkBytes = 12 * 1024 * 1024, crypto } = {}) {
      if (localBuf.length <= chunkBytes) return api.putBuffer(remote, localBuf);
      const sha = crypto.createHash('sha256').update(localBuf).digest('hex');
      const partsDir = remote + '.nbparts';
      const n = Math.ceil(localBuf.length / chunkBytes);
      for (let i = 0; i < n; i++) {
        const part = localBuf.subarray(i * chunkBytes, Math.min(localBuf.length, (i + 1) * chunkBytes));
        for (let a = 0; a < 3; a++) { try { await api.putBuffer(`${partsDir}/${String(i).padStart(5, '0')}`, part); break; } catch (e) { if (a === 2) throw e; } }
      }
      const P = shq(partsDir), R = shq(remote);
      const r = await api.sh(`cd /home/aistudio && cat ${P}/* > ${R} && find ${P} -mindepth 1 -delete && rmdir ${P} && sha256sum ${R} | cut -c1-64`);
      const got = (r.output.trim().split('\n').pop() || '').trim();
      if (r.rc !== 0 || got !== sha) throw new Error(`分块上传校验失败 rc=${r.rc} sha=${got.slice(0, 12)} != ${sha.slice(0, 12)}`);
      return { path: remote, size: localBuf.length, parts: n, sha256: sha };
    },
  };
  return api;
}

// ---------- offline self-test ----------
const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain && process.argv.includes('--self-test')) {
  const assert = (await import('node:assert/strict')).default;
  assert.equal(contentPath('/home/aistudio/h3v/a.py'), 'h3v/a.py');
  assert.equal(contentPath('h3v/a.py'), 'h3v/a.py');
  assert.equal(contentPath('/home/aistudio'), '');
  assert.throws(() => contentPath('/tmp/a.py'), /relative/);
  assert.throws(() => contentPath('../a.py'), /relative/);
  assert.equal(baseFromJumpUrl('https://aistudio.baidu.com/bj-cpu-01/user/123/456/home#codelab'), 'https://aistudio.baidu.com/bj-cpu-01/user/123/456/');
  assert.equal(baseFromJumpUrl('/bj-gpu-03/user/1/2/lab?userType=1'), 'https://aistudio.baidu.com/bj-gpu-03/user/1/2/');
  assert.equal(baseFromJumpUrl('https://aistudio.baidu.com/bj-cpu-01/hub/user/1/2/'), 'https://aistudio.baidu.com/bj-cpu-01/user/1/2/');
  assert.equal(baseFromJumpUrl('https://evil.example/x'), null);
  assert.equal(classifyRunResponse({ errorCode: 0, result: { code: 201 } }).kind, 'launching');
  assert.deepEqual(classifyRunResponse({ errorCode: 0, result: { code: 200, jumpUrl: 'u' } }).kind, 'up');
  assert.equal(classifyRunResponse({ errorCode: 0, errorMsg: '成功', result: { code: 500, msg: '人机验证失败' } }).kind, 'captcha');
  assert.equal(classifyRunResponse({ errorCode: 0, result: { code: 500, msg: '资源不足' } }).kind, 'error');
  assert.equal(classifyRunResponse({ errorCode: 8307, errorMsg: 'x' }).kind, 'error');
  const ll = launchLine('j1');
  assert.match(ll, /^setsid nohup bash -c '/);
  assert.ok(ll.endsWith('& echo NBAPI_LAUNCHED_j1'));
  assert.ok(ll.includes('/home/aistudio/nbapi-jobs/j1.rc'));
  assert.match(newJobId(), /^j[a-z0-9]+$/);

  // Mock page: start guard, captcha short-circuit, launching -> up, stop polling.
  const calls = [];
  let runs = 0, running = false, graphic = false;
  const page = {
    url: async () => SITE + '/my/project',
    goto: async () => {},
    evaluate: async (fn, arg) => {
      if (!arg) return true; // bdToken probe
      calls.push(arg.path);
      const ok = (result) => JSON.stringify({ errorCode: 0, errorMsg: '成功', result });
      if (arg.path === '/studio/project/detail') return ok({ projectId: 9, running, projectState: running ? 300204 : 300400, versionList: [{ versionId: 0 }], runningClusterInfo: { scheduleName: 'normalSchedule', costPerHour: '0', cores: '2', memory: '8GB' } });
      if (arg.path.endsWith('require/graphic')) return ok(graphic);
      if (arg.path === '/studio/project/running') { assert.equal(arg.form.scheduleName, FREE_SCHEDULE); runs++; if (runs < 2) return ok({ code: 201 }); running = true; return ok({ code: 200, jumpUrl: 'https://aistudio.baidu.com/bj-cpu-01/user/1/9/home?userType=1' }); }
      if (arg.path === '/studio/project/stop') { running = false; return ok({ code: 200 }); }
      throw new Error('unexpected ' + arg.path);
    },
  };
  await assert.rejects(startRuntime(page, { projectId: 9, scheduleName: 'resourceCardSchedule' }), /拒绝启动/);
  graphic = true;
  assert.equal((await startRuntime(page, { projectId: 9 })).blocked, 'captcha');
  assert.equal(runs, 0);
  graphic = false;
  const origSet = globalThis.setTimeout; globalThis.setTimeout = (f) => origSet(f, 0);
  const st = await startRuntime(page, { projectId: 9 });
  assert.equal(st.base, 'https://aistudio.baidu.com/bj-cpu-01/user/1/9/');
  assert.equal(st.detail.running, true);
  const sp = await stopRuntime(page, { projectId: 9 });
  globalThis.setTimeout = origSet;
  assert.equal(sp.stopped, true);
  assert.throws(() => jupyter(page, 'https://aistudio.baidu.com/x/'), /无效/);
  const kernelCalls = [];
  const kernelId = 'f164b1a0-fe03-457d-88e5-341c7772ccb9';
  const kernelApi = jupyter({ fetch: async (url, opts) => {
    kernelCalls.push({ url, method: opts.method });
    return { ok: true, status: 200, body: JSON.stringify({ id: kernelId, name: 'python3', execution_state: 'idle' }) };
  } }, 'https://aistudio.baidu.com/bj-gpu-03/user/1/9/');
  await assert.rejects(kernelApi.restartKernel('../stop'), /Invalid/);
  assert.equal((await kernelApi.restartKernel(kernelId)).state, 'idle');
  assert.equal(kernelCalls[0].method, 'POST');
  assert.ok(kernelCalls[0].url.endsWith(`/api/kernels/${kernelId}/restart`));
  assert.ok(kernelCalls.every(c => !c.url.includes('/studio/project/stop')));
  console.log('notebook_api self-test OK (base parse, run classify, captcha short-circuit, paid guard, launching->up, stop)');
}
