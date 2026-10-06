// Shared helpers for miniprogram-automator tests against WeChat DevTools (`cli auto --auto-port 9420`).
// Usage:
//   const h = require('<skill>/scripts/miniprogram-automator-helpers.cjs');
//   const mp = await h.connect();
//   await h.mockRequests(mp, [{ match: '/rank', data: {...} }, { match: '/sync', hang: true }]);
//   await h.stubInterstitial(mp);           // before reLaunch
//   ... h.check('name', ok) ...
//   await h.restore(mp); h.summary(); mp.disconnect();
// Self-test (no DevTools needed): node miniprogram-automator-helpers.cjs --selftest
const sleep = ms => new Promise(r => setTimeout(r, ms));

let failed = 0;
function check(name, ok, extra = '') {
  if (!ok) failed++;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${extra}`.trimEnd());
  return ok;
}
function summary() {
  console.log(failed ? `${failed} FAILED` : 'ALL PASS');
  return failed;
}

/** miniprogram-automator lives in the caller's project (cwd), not next to this skill file. */
function loadAutomator() {
  const { createRequire } = require('module');
  const path = require('path');
  try {
    return createRequire(path.join(process.cwd(), 'index.js'))('miniprogram-automator');
  } catch {
    return require('miniprogram-automator');
  }
}

async function connect(port = 9420) {
  const automator = loadAutomator();
  return automator.connect({ wsEndpoint: `ws://localhost:${port}` });
}

/**
 * Replace wx.request inside the simulator.
 * rules: [{ match: 'url substring', data?: any, code?: number, fail?: boolean, hang?: boolean, delay?: number }]
 * Unmatched requests go to the real network.
 */
async function mockRequests(mp, rules) {
  await mp.evaluate(list => {
    if (!wx.__origRequest) wx.__origRequest = wx.request;
    const orig = wx.__origRequest;
    wx.request = function (o) {
      const url = o.url || '';
      const rule = list.find(r => url.includes(r.match));
      if (!rule) return orig(o);
      if (!rule.hang) {
        setTimeout(() => {
          if (rule.fail) {
            const err = { errMsg: 'request:fail mock' };
            o.fail && o.fail(err);
            o.complete && o.complete(err);
            return;
          }
          const res = { statusCode: 200, header: {}, data: { code: rule.code ?? 0, data: rule.data } };
          o.success && o.success(res);
          o.complete && o.complete(res);
        }, rule.delay ?? 50);
      }
      return { abort() {} };
    };
  }, rules);
}

/** Count interstitial show() calls in wx.__adShows. Call before reLaunch: pages cache the ad instance. */
async function stubInterstitial(mp) {
  await mp.evaluate(() => {
    wx.__adShows = 0;
    wx.createInterstitialAd = () => ({
      onLoad() {}, onError() {}, onClose() {}, destroy() {},
      show() { wx.__adShows++; return Promise.resolve(); },
    });
  });
}

async function adShows(mp) {
  return mp.evaluate(() => wx.__adShows || 0);
}

async function restore(mp) {
  await mp.evaluate(() => {
    if (wx.__origRequest) { wx.request = wx.__origRequest; delete wx.__origRequest; }
  }).catch(() => {});
}

/** Collapse whitespace of an element's text. */
async function textOf(el) {
  return el ? (await el.text()).replace(/\s+/g, ' ').trim() : '';
}

module.exports = { sleep, check, summary, connect, mockRequests, stubInterstitial, adShows, restore, textOf };

if (require.main === module && process.argv.includes('--selftest')) {
  const assert = require('assert');
  failed = 0;
  assert.strictEqual(check('selftest pass', true), true);
  assert.strictEqual(check('selftest fail', false), false);
  assert.strictEqual(summary(), 1);
  (async () => {
    assert.strictEqual(await textOf({ text: async () => '  a \n b ' }), 'a b');
    console.log('selftest ok');
  })();
}
