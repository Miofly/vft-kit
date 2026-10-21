#!/usr/bin/env node
// ModelScope free Notebook (PAI-DSW) runtime helpers: gateway bridge, Jupyter kernel exec, contents transfer.
//
// The functions named page* are serialized with Function.prototype.toString() and run inside an
// authenticated browser page (for example via ego-browser page.evaluate). They must stay self-contained:
// no closures, no imports. Session cookies and the gateway token never leave the page.
//
// Flow (reverse-engineered from the ModelScope Code Workspace frontend, 2026-10-13):
//   1. On a modelscope.cn page: GET /api/v1/notebooks/token?InstanceId=<dsw-id>
//      -> Data.Result.{Token, InstanceInfo.WebIDEUrl}
//   2. base = WebIDEUrl without "/ide", with trailing "/"; GET base + "gateway-login?token=<Token>"
//      with credentials: "include" (sets the gateway cookie for this instance only).
//   3. Navigate a second page to base + "api/status" (same origin as Jupyter) and use the Jupyter REST
//      API (/api/kernels, /api/contents) plus the kernel WebSocket from that page.
//
// Usage: node dsw-jupyter.mjs --selftest

import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

/** Jupyter base URL ("https://host/dsw-123/") from the instance WebIDEUrl. */
export function instanceBaseFromWebIDEUrl(webIdeUrl) {
  const u = new URL(String(webIdeUrl).replace("/ide", ""));
  if (u.protocol !== "https:") throw Error("WebIDEUrl must be https");
  u.search = "";
  u.hash = "";
  if (!u.pathname.endsWith("/")) u.pathname += "/";
  if (!/^\/dsw-[\w-]+\/$/.test(u.pathname)) throw Error("Unexpected WebIDEUrl path");
  return u.toString();
}

/** Jupyter contents path relative to /mnt/workspace; rejects traversal and absolute paths. */
export function contentsPath(rel) {
  if (!rel || rel.startsWith("/") || rel.split("/").some((p) => !p || p === "." || p === "..")) {
    throw Error(`Invalid relative path: ${rel}`);
  }
  return rel.split("/").map(encodeURIComponent).join("/");
}

/** Python source that runs a shell command and prints a parseable footer. */
export function shellToPython(cmd, timeoutSec = 600) {
  return [
    "import subprocess, sys",
    `_r = subprocess.run(${JSON.stringify(cmd)}, shell=True, executable="/bin/bash", capture_output=True, text=True, timeout=${Number(timeoutSec)})`,
    "sys.stdout.write(_r.stdout[-200000:])",
    "sys.stderr.write(_r.stderr[-50000:])",
    'print("\\n__NBAPI_EXIT__=%d" % _r.returncode)',
  ].join("\n");
}

/** Split a byte length into Jupyter chunked-upload pieces (chunk numbers 1..n-1, last is -1). */
export function chunkPlan(size, chunkBytes = 4 * 1024 * 1024) {
  if (size <= chunkBytes) return [{ start: 0, end: size, chunk: null }];
  const out = [];
  for (let start = 0, n = 1; start < size; start += chunkBytes, n++) {
    const end = Math.min(size, start + chunkBytes);
    out.push({ start, end, chunk: end === size ? -1 : n });
  }
  return out;
}

// ---------------- page-side functions (serialized) ----------------

/** Run on a modelscope.cn page. Returns { base } or { error }. Token stays in the page. */
export async function pageBridge({ instanceId }) {
  const r = await fetch("/api/v1/notebooks/token?InstanceId=" + encodeURIComponent(instanceId), { credentials: "include" });
  const j = await r.json().catch(() => null);
  const res = j && j.Data && j.Data.Result;
  const web = res && res.InstanceInfo && res.InstanceInfo.WebIDEUrl;
  if (!res || !res.Token || !web) return { error: "token API returned no Token/WebIDEUrl (instance not Running?)", status: r.status };
  let base = web.replace("/ide", "");
  if (!base.endsWith("/")) base += "/";
  const g = await fetch(base + "gateway-login?token=" + encodeURIComponent(res.Token), { credentials: "include" });
  return { base: base.split("?")[0], gatewayStatus: g.status };
}

/** Run on the gateway-origin page. Starts a kernel execution in the background; returns { key }. */
export async function pageExecStart({ code, kernelName }) {
  const xsrf = (document.cookie.match(/(?:^|;\s*)_xsrf=([^;]+)/) || [])[1];
  const H = { "Content-Type": "application/json" };
  if (xsrf) H["X-XSRFToken"] = decodeURIComponent(xsrf);
  const root = location.pathname.replace(/api\/.*$/, "");
  const kr = await fetch(root + "api/kernels", { method: "POST", headers: H, body: JSON.stringify({ name: kernelName || "python3" }) });
  if (!kr.ok) return { error: "create kernel failed", status: kr.status };
  const kid = (await kr.json()).id;
  const key = "x" + Math.random().toString(36).slice(2);
  const st = { kernelId: kid, out: "", err: "", done: false, status: null, error: null };
  (window.__nbapi = window.__nbapi || {})[key] = st;
  const session = crypto.randomUUID();
  const msgId = crypto.randomUUID();
  const ws = new WebSocket((location.protocol === "https:" ? "wss://" : "ws://") + location.host + root + "api/kernels/" + kid + "/channels?session_id=" + session);
  st.ws = ws;
  ws.onopen = () => ws.send(JSON.stringify({
    header: { msg_id: msgId, username: "", session, msg_type: "execute_request", version: "5.3", date: new Date().toISOString() },
    parent_header: {}, metadata: {}, channel: "shell", buffers: [],
    content: { code, silent: false, store_history: false, user_expressions: {}, allow_stdin: false, stop_on_error: true },
  }));
  ws.onmessage = (ev) => {
    if (typeof ev.data !== "string") return;
    const m = JSON.parse(ev.data);
    if (!m.parent_header || m.parent_header.msg_id !== msgId) return;
    const t = m.msg_type || (m.header && m.header.msg_type);
    if (t === "stream") { if (m.content.name === "stderr") st.err += m.content.text; else st.out += m.content.text; }
    else if (t === "execute_result" || t === "display_data") st.out += (m.content.data && m.content.data["text/plain"]) || "";
    else if (t === "error") st.err += m.content.ename + ": " + m.content.evalue + "\n";
    else if (t === "execute_reply") st.status = m.content.status;
    else if (t === "status" && m.content.execution_state === "idle" && st.status !== null) st.done = true;
    if (t === "execute_reply") setTimeout(() => { st.done = true; }, 1500);
  };
  ws.onerror = () => { st.error = "websocket error"; st.done = true; };
  ws.onclose = () => { if (!st.done) { st.error = st.error || "websocket closed"; st.done = true; } };
  return { key };
}

/** Run on the gateway-origin page. Returns { done, out, err, status, error } and cleans up when done. */
export async function pageExecPoll({ key }) {
  const st = (window.__nbapi || {})[key];
  if (!st) return { done: true, error: "unknown exec key (page reloaded?)" };
  if (!st.done) return { done: false, outLen: st.out.length };
  try { st.ws.close(); } catch {}
  const xsrf = (document.cookie.match(/(?:^|;\s*)_xsrf=([^;]+)/) || [])[1];
  const root = location.pathname.replace(/api\/.*$/, "");
  await fetch(root + "api/kernels/" + st.kernelId, { method: "DELETE", headers: xsrf ? { "X-XSRFToken": decodeURIComponent(xsrf) } : {} }).catch(() => {});
  delete window.__nbapi[key];
  return { done: true, out: st.out, err: st.err, status: st.status, error: st.error };
}

/** Run on the gateway-origin page. PUT one base64 piece via the Jupyter contents API. */
export async function pageContentsPut({ path, b64, chunk, name }) {
  const xsrf = (document.cookie.match(/(?:^|;\s*)_xsrf=([^;]+)/) || [])[1];
  const H = { "Content-Type": "application/json" };
  if (xsrf) H["X-XSRFToken"] = decodeURIComponent(xsrf);
  const root = location.pathname.replace(/api\/.*$/, "");
  const body = { type: "file", format: "base64", content: b64, name, path };
  if (chunk !== null && chunk !== undefined) body.chunk = chunk;
  const r = await fetch(root + "api/contents/" + path, { method: "PUT", headers: H, body: JSON.stringify(body) });
  const j = await r.json().catch(() => ({}));
  return { status: r.status, size: j.size, error: r.ok ? null : (j.message || "put failed") };
}

/** Run on the gateway-origin page. GET a file as base64 (small/medium files). */
export async function pageContentsGet({ path }) {
  const root = location.pathname.replace(/api\/.*$/, "");
  const r = await fetch(root + "api/contents/" + path + "?type=file&format=base64&content=1");
  if (!r.ok) return { status: r.status, error: "get failed" };
  const j = await r.json();
  return { status: r.status, size: j.size, b64: j.content };
}

/** Build a page.evaluate() string for one of the page* functions. */
export function evalSource(fn, arg) {
  return `(${fn.toString()})(${JSON.stringify(arg)})`;
}

if (process.argv[1] === fileURLToPath(import.meta.url) && process.argv.includes("--selftest")) {
  assert.equal(instanceBaseFromWebIDEUrl("https://dsw-gateway-cn-hangzhou.data.aliyun.com/dsw-123/ide/"), "https://dsw-gateway-cn-hangzhou.data.aliyun.com/dsw-123/");
  assert.equal(instanceBaseFromWebIDEUrl("https://h.example.com/dsw-9/ide?x=1"), "https://h.example.com/dsw-9/");
  assert.throws(() => instanceBaseFromWebIDEUrl("http://h/dsw-1/ide"));
  assert.throws(() => instanceBaseFromWebIDEUrl("https://h/other/ide"));
  assert.equal(contentsPath("a b/c.txt"), "a%20b/c.txt");
  for (const p of ["../a", "/a", "a//b", "a/./b", ""]) assert.throws(() => contentsPath(p));
  const py = shellToPython('echo "hi"; exit 3', 5);
  assert.match(py, /subprocess\.run\("echo \\"hi\\"; exit 3"/);
  assert.match(py, /timeout=5\)/);
  assert.deepEqual(chunkPlan(10, 4), [{ start: 0, end: 4, chunk: 1 }, { start: 4, end: 8, chunk: 2 }, { start: 8, end: 10, chunk: -1 }]);
  assert.deepEqual(chunkPlan(3, 4), [{ start: 0, end: 3, chunk: null }]);
  for (const fn of [pageBridge, pageExecStart, pageExecPoll, pageContentsPut, pageContentsGet]) {
    const src = evalSource(fn, { a: 1 });
    new Function(`return async () => ${src}`); // must parse as standalone source
    assert.ok(!/\bimport\b|\brequire\(/.test(fn.toString()), `${fn.name} must be self-contained`);
  }
  console.log("dsw-jupyter selftest OK");
}
