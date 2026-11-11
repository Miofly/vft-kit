// Run through ego-browser nodejs, preceded by absolute FRONTEND_DESIGN_DIR and OUTPUT_DIR constants.
const { readFile, writeFile, mkdir } = await import('node:fs/promises');
const assert = (await import('node:assert/strict')).default;
const { pathToFileURL } = await import('node:url');
const source = await readFile(`${FRONTEND_DESIGN_DIR}/scripts/mobile-audit.mjs`, 'utf8');
const module = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const task = await taskSpace('frontend-design mobile audit regression');
console.log({ spaceId: task.spaceId });
const page = task.page('p1');
const results = [];
await mkdir(OUTPUT_DIR, { recursive: true });
await page.goto('about:blank');
try {
  for (const [width, height] of [[320, 844], [390, 844], [430, 844], [768, 900], [1440, 900], [844, 390]]) {
    await page.cdp('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: width < 768 });
    for (const theme of ['light', 'dark']) {
      await page.evaluate(({ theme }) => {
        document.open();
        document.write(`<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1"><title>Mobile audit fixture</title>
          <style>*{box-sizing:border-box}body{margin:0;padding:16px;font:16px/1.6 system-ui;background:${theme === 'dark' ? '#141820' : '#f5f6f8'};color:${theme === 'dark' ? '#f5f6f8' : '#141820'}}main{max-width:720px;margin:auto}button,input{min-width:44px;min-height:44px;font:inherit}input{max-width:100%}.table{overflow-x:auto;max-width:100%}table{width:900px}th,td{text-align:left;padding:12px;border-bottom:1px solid gray}footer{margin-top:32px}</style>
          <main><h1>手机端检查夹具</h1><p>长中文内容自动换行；数据表在自己的容器中横滚。</p><label for="name">名称</label><p><input id="name" autocomplete="name"></p><button>检查状态</button><h2>局部横滚数据</h2><div class="table"><table><tr><th>名称</th><th>数值</th><th>状态</th></tr><tr><td>可保留的完整内容</td><td>123.45</td><td>就绪</td></tr></table></div><footer>页尾：夹具，不是业务页面验收。</footer></main>`);
        document.close();
      }, { theme });
      const result = await page.evaluate(`(${module.collectMobileAudit.toString()})()`);
      assert.equal(result.status, 'clear', JSON.stringify({ width, height, theme, result }));
      // Classic scrollbars reduce clientWidth; verify emulation separately from the usable layout width.
      assert.equal(await page.evaluate(() => window.innerWidth), width);
      assert.ok(result.viewport.width > 0 && result.viewport.width <= width);
      results.push({ width, height, theme, status: result.status });
      if (width === 390) await page.screenshot({ path: `${OUTPUT_DIR}/fixture-${theme}-390.png` });
    }
  }
  await page.cdp('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true });
  await page.evaluate(() => {
    document.querySelector('meta[name="viewport"]').content = 'width=device-width, initial-scale=1, maximum-scale=1';
    document.querySelector('input').style.fontSize = '12px';
    const button = document.querySelector('button');
    button.style.cssText = 'width:20px;min-width:0;height:20px;min-height:0;padding:0;font-size:8px';
    const wide = document.createElement('div');
    // A zero-height box need not contribute scrollable overflow in the browser.
    wide.style.cssText = 'width:900px;height:1px';
    document.body.append(wide);
  });
  const bad = await page.evaluate(`(${module.collectMobileAudit.toString()})()`);
  assert.equal(bad.viewport.zoomRestricted, true);
  assert.equal(bad.pageOverflow, true);
  assert.equal(bad.smallInputs.count, 1);
  assert.equal(bad.smallTargets.candidates.some((item) => item.below24), true);
  results.push({ state: 'four deliberate defects', status: bad.status, checks: 4 });
  await page.screenshot({ path: `${OUTPUT_DIR}/fixture-defects-390.png` });
  await writeFile(`${OUTPUT_DIR}/results.json`, JSON.stringify({ kind: 'Chromium fixture regression, not physical-device evidence', results }, null, 2));
  console.log({ passed: results.length, report: pathToFileURL(`${OUTPUT_DIR}/results.json`).href });
} finally {
  await task.finish({ keep: [] });
}
