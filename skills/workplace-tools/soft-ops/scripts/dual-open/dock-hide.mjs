// One-shot: hide the Dock icon of an Electron app started with --inspect=127.0.0.1:<port>, then close its inspector
// so the debug port does not stay open. usage: node dock-hide.mjs <port>
// The window stays usable; it no longer shows in the Dock or Cmd+Tab (reach it through the launcher app).
const port = process.argv[2];
const deadline = Date.now() + 60_000;
let target;
while (!target && Date.now() < deadline) {
  try { [target] = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); } catch { await new Promise((r) => setTimeout(r, 300)); }
}
if (!target) { console.error('inspector not reachable on ' + port); process.exit(1); }
const ws = new WebSocket(target.webSocketDebuggerUrl);
// Apps may run a Dock keepalive (Loomy: dock-controller.js polls app.dock.isVisible() every second and reasserts
// setActivationPolicy('regular') + dock.show()), so report the Dock as visible and swallow both calls.
const expr = `(()=>{const r=process.mainModule.require;const {app}=r('electron');
  const setPolicy=app.setActivationPolicy?.bind(app);
  app.setActivationPolicy=()=>{};
  if(app.dock){app.dock.show=()=>Promise.resolve();app.dock.isVisible=()=>true;}
  const hide=()=>setPolicy?setPolicy('accessory'):app.dock?.hide();
  app.isReady()?hide():app.once('ready',hide);
  setTimeout(()=>r('inspector').close(),300);return 'ok'})()`;
ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression: expr, returnByValue: true } }));
ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id === 1) { console.log(d.result?.result?.value ?? JSON.stringify(d).slice(0, 200)); process.exit(0); } };
setTimeout(() => process.exit(2), 15_000);
