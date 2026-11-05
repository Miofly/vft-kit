// Injected into the Electron main process by insp.mjs on every call; the guard makes it run once per app process.
// Globals: W (largest app window), run(code) renderer eval, NET captured renderer requests (method/path/query keys/body keys/status only),
// stealth() invisible-but-rendering window, tap(text, exact, i) / tapSel(css) trusted clicks, type(s), key(k).
if (!globalThis.__softOpsSetup || !globalThis.W || W.isDestroyed()) {
  const { BrowserWindow, app } = process.mainModule.require('electron');
  globalThis.app = app;
  const wins = BrowserWindow.getAllWindows();
  const appWins = wins.filter((w) => w.webContents.getURL().includes('app.asar'));
  globalThis.W = (appWins.length ? appWins : wins).sort((a, b) => b.getBounds().width - a.getBounds().width)[0];
  if (!W) throw new Error('no BrowserWindow yet; wait for the app window and retry');
  globalThis.__softOpsSetup = 1;
  globalThis.run = (c) => W.webContents.executeJavaScript(c);
  globalThis.NET = [];
  const d = W.webContents.debugger;
  try { d.attach('1.3'); } catch (e) {}
  d.sendCommand('Network.enable');
  // Without focus emulation an unfocusable window makes Radix menus close the moment they open.
  d.sendCommand('Emulation.setFocusEmulationEnabled', { enabled: true });
  const req = {};
  const keys = (b) => { try { return Object.keys(JSON.parse(b)).join(','); } catch { return b ? 'non-json' : ''; } };
  d.on('message', (e, m, p) => {
    if (m === 'Network.requestWillBeSent' && /^https?:/.test(p.request.url)) {
      const [u, q = ''] = p.request.url.split('?');
      req[p.requestId] = { m: p.request.method, u, q: q.replace(/=[^&]*/g, ''), b: keys(p.request.postData) };
    }
    if (m === 'Network.responseReceived' && req[p.requestId]) { NET.push({ ...req[p.requestId], s: p.response.status }); delete req[p.requestId]; }
  });
  // hide() stops frame rendering, so CSS exit animations never fire animationend and dialogs stay mounted.
  globalThis.stealth = () => {
    W.setOpacity(0); W.setIgnoreMouseEvents(true); W.setFocusable(false); W.webContents.setBackgroundThrottling(false);
    W.showInactive(); app.dock?.hide();
    return 'stealth ' + W.isVisible() + ' opacity=' + W.getOpacity();
  };
  const click = async (r) => {
    for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) {
      await d.sendCommand('Input.dispatchMouseEvent', { type, x: r[0], y: r[1], button: type === 'mouseMoved' ? 'none' : 'left', clickCount: 1 });
    }
  };
  const centerOf = (finder) => run('(()=>{const e=' + finder + ';if(!e)return null;e.scrollIntoView({block:"center"});const b=e.getBoundingClientRect();return [b.x+b.width/2,b.y+b.height/2]})()');
  globalThis.tap = async (t, exact = true, i = 0) => {
    const r = await centerOf('$t(' + JSON.stringify(t) + ',' + exact + ')[' + i + ']');
    if (!r) return 'NOTFOUND ' + t;
    await click(r);
    return 'tapped ' + t + ' @' + r.map(Math.round);
  };
  globalThis.tapSel = async (sel) => {
    const r = await centerOf('document.querySelector(' + JSON.stringify(sel) + ')');
    if (!r) return 'NOTFOUND ' + sel;
    await click(r);
    return 'tapped ' + sel + ' @' + r.map(Math.round);
  };
  globalThis.type = async (s) => { await d.sendCommand('Input.insertText', { text: s }); return 'typed'; };
  const VK = { Enter: 13, Escape: 27, Tab: 9, Backspace: 8, ' ': 32 };
  globalThis.key = async (k) => {
    for (const type of ['keyDown', 'keyUp']) await d.sendCommand('Input.dispatchKeyEvent', { type, key: k, code: k === ' ' ? 'Space' : k, windowsVirtualKeyCode: VK[k] || 0 });
    return 'key ' + JSON.stringify(k);
  };
}
