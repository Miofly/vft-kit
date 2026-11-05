// Drive an Electron app started with --inspect=<port> (see references/background-gui.md).
// usage: ELECTRON_INSPECT_PORT=9339 node insp.mjs '<main-process JS expr>'
//        ELECTRON_INSPECT_PORT=9339 node insp.mjs -r '<renderer JS expr>'
// Main globals come from main-setup.js, renderer globals ($t, clk, txt) from helpers.js; both are injected on each call.
// Run with NO_PROXY='*' when an HTTP proxy is exported, or the localhost fetch goes through it.
import fs from 'node:fs';

const dir = new URL('.', import.meta.url).pathname;
const port = process.env.ELECTRON_INSPECT_PORT || 9339;
const [target] = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const ws = new WebSocket(target.webSocketDebuggerUrl);
const setup = fs.readFileSync(dir + 'main-setup.js', 'utf8');
const helpers = JSON.stringify(fs.readFileSync(dir + 'helpers.js', 'utf8'));
const body = process.argv[2] === '-r' ? `run(${JSON.stringify(process.argv[3])})` : process.argv[2];
const expr = `(async()=>{${setup};await run('window.$t?1:0').then(v=>v||run(${helpers}));return await (async()=>(${body}))()})()`;

ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression: expr, awaitPromise: true, returnByValue: true } }));
ws.onmessage = (m) => {
  const d = JSON.parse(m.data);
  if (d.id !== 1) return;
  const r = d.result;
  if (r?.exceptionDetails) console.log('ERR ' + (r.exceptionDetails.exception?.description || r.exceptionDetails.text));
  else console.log(typeof r?.result?.value === 'string' ? r.result.value : JSON.stringify(r?.result?.value, null, 1));
  process.exit(r?.exceptionDetails ? 1 : 0);
};
