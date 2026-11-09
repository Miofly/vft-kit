// One-shot, run by a clone-app.sh copy at start: route that copy's shell.openExternal(http/https) to an ego lite task
// space on one profile, then close the inspector so the debug port does not stay open.
// usage: node ego-external.mjs <port> <ego-browser path> <ego profile id> <space name>
// The page is handed to the user (task.handOff()), since a web sign-in needs them; other schemes keep the original call.
// Failures go to <copy HOME>/ego-external.log.
const [port, egoBin, profileId, space] = process.argv.slice(2);
const deadline = Date.now() + 90_000;
let target;
while (!target && Date.now() < deadline) {
  try { [target] = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); } catch { await new Promise((r) => setTimeout(r, 300)); }
}
if (!target) { console.error('inspector not reachable on ' + port); process.exit(1); }
const cfg = JSON.stringify({ egoBin, profileId, space: `${space} web`, home: process.env.HOME });
// Runs inside the app's main process. ego-browser finds its browser service under the real HOME, not the copy's.
// Connecting early lands before the app's main module exists (WorkBuddy AI: process.mainModule undefined), so the
// script answers 'wait' and is retried until it installs.
const expr = `(()=>{if(!process.mainModule)return 'wait';const r=process.mainModule.require;const {shell}=r('electron');const c=${cfg};
  const orig=shell.openExternal.bind(shell);
  shell.openExternal=async(url,opts)=>{
    if(!/^https?:/i.test(String(url)))return orig(url,opts);
    // profileId only applies to a new space, so each page gets its own; no profile-less or default-browser fallback,
    // which would open the page on another account's session.
    const name=c.space+' '+new Date().toTimeString().slice(0,8);
    const js='const t=await taskSpace('+JSON.stringify(name)+',{profileId:'+JSON.stringify(c.profileId)+'});'
      +'await t.page("p1").goto('+JSON.stringify(String(url))+').catch(()=>{});await t.handOff();';
    r('child_process').execFile(c.egoBin,['nodejs','-e',js],{env:{...process.env,HOME:c.home},timeout:90000},
      (e,o,er)=>{if(e)r('fs').appendFileSync(process.env.HOME+'/ego-external.log',new Date().toISOString()+' '+url+String.fromCharCode(10)+er+String.fromCharCode(10))});
  };
  setTimeout(()=>r('inspector').close(),300);return 'ok'})()`;
const ws = new WebSocket(target.webSocketDebuggerUrl);
let n = 0;
const send = () => ws.send(JSON.stringify({ id: ++n, method: 'Runtime.evaluate', params: { expression: expr, returnByValue: true } }));
ws.onopen = send;
ws.onmessage = (m) => {
  const d = JSON.parse(m.data);
  if (d.id !== n) return;
  const v = d.result?.result?.value;
  if (v === 'ok') { console.log('ok'); process.exit(0); }
  if (d.result?.exceptionDetails) { console.error(JSON.stringify(d).slice(0, 300)); process.exit(1); }
  if (Date.now() > deadline) { console.error(JSON.stringify(d).slice(0, 300)); process.exit(1); }
  setTimeout(send, 500);
};
ws.onerror = () => process.exit(1);
