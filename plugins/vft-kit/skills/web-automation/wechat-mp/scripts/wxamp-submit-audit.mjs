// 小程序提交审核（页面流程兜底；提交接口已抓到但还没用 API 独立复现，见 references/miniprogram-release.md）
// 运行：VERSION_DESC="本版说明" PRIVACY=none|collect ego-browser nodejs < wxamp-submit-audit.mjs
//   注意：ego-browser 的 nodejs 运行时不继承调用方的环境变量。环境变量没传进去时，在脚本前拼两行 process.env.X = "…" 再管道给 ego-browser：
//   { printf 'process.env.VERSION_DESC=%s;process.env.PRIVACY="none";\n' "$(node -p 'JSON.stringify(process.argv[1])' "$DESC")"; cat wxamp-submit-audit.mjs; } | ego-browser nodejs
// 前提：开发版已用 CLI 上传；写后用 wxamp-version-status.mjs 回读 audit.auditStatus=1。
// 关键坑：后台在「继续提交」后用 window.open 打开提审表单，必须用真实鼠标点击（page.mouse.click），
//        element.click() 不算用户手势会被弹窗拦截，表现为点了没反应。
// 闸门：提审已有接口版（wxamp-submit-audit-api.mjs，已实测）。页面版只在接口版失败时兜底，
// 必须显式写 globalThis.FORCE_PAGE = true 才继续，并在回复里说明接口版为什么失败。
if (!globalThis.FORCE_PAGE) {
  console.log(JSON.stringify({ blocked: true, reason: '提审请用接口版 wxamp-submit-audit-api.mjs；接口版失败时才在脚本前加 globalThis.FORCE_PAGE=true 走页面兜底' }));
  process.exit(3);
}
const desc = process.env.VERSION_DESC;
const privacy = process.env.PRIVACY || 'none';
if (!desc) { console.log('缺少 VERSION_DESC'); process.exit(2); }

const task = await taskSpace("小程序提审");
const page = task.page("p1");
await page.goto("https://mp.weixin.qq.com/wxamp/wacodepage/getcodepage");
await page.waitForTimeout(2500);
// 已登录时直接打开 /wxamp/... 可能不带 token；走一次登录页，已登录会自动跳回带 token 的地址
if (!/\/wxamp\/[^?]*\?.*token=\d+/.test(await page.url())) {
  await page.goto("https://mp.weixin.qq.com/cgi-bin/loginpage?url=%2Fwxamp%2Fwacodepage%2Fgetcodepage");
  await page.waitForTimeout(2500);
  if (!/\/wxamp\/[^?]*\?.*token=\d+/.test(await page.url())) {
    console.log(JSON.stringify({ spaceId: task.spaceId, needLogin: true }));
    await task.handOff();
    process.exit(0);
  }
  // 登录页跳回的可能是首页 /wxamp/index/index?token=…，带上 token 回到版本管理页
  const tk = (await page.url()).match(/token=(\d+)/)[1];
  await page.goto(`https://mp.weixin.qq.com/wxamp/wacodepage/getcodepage?token=${tk}&lang=zh_CN`);
  await page.waitForTimeout(2500);
}

const center = el => page.evaluate(sel => {
  const [needle, label] = sel;
  const scope = needle ? [...document.querySelectorAll('.weui-desktop-dialog')].find(x => x.offsetParent && x.innerText.includes(needle)) : document;
  if (!scope) return null;
  const btn = [...scope.querySelectorAll('button, a')].filter(b => b.offsetParent && b.innerText.trim().includes(label)).pop();
  if (!btn) return null;
  btn.scrollIntoView({ block: 'center' });
  const r = btn.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
}, el);
const waitDialog = needle => page.waitForFunction(n => [...document.querySelectorAll('.weui-desktop-dialog')].some(x => x.offsetParent && x.innerText.includes(n)), needle, { timeout: 30000 });

// 1. 开发版本的「提交审核」（会先跑 selfCheck / check_domain / check_plugin_version 等预检，再弹须知）
let p = await center([null, '提交审核']);
await page.mouse.click(p.x, p.y, { label: '提交审核' });
await waitDialog('已阅读并了解');
const ticked = await page.evaluate(() => { const d = [...document.querySelectorAll('.weui-desktop-dialog')].find(x => x.offsetParent && x.innerText.includes('已阅读并了解')); return d.querySelector('input[type=checkbox]').checked; });
if (!ticked) await page.click('text=已阅读并了解平台审核规则', { label: '勾选审核规则' });
p = await center(['已阅读并了解', '下一步']);
await page.mouse.click(p.x, p.y, { label: '下一步' });

// 2. 安全测试提醒 → 继续提交（CheckPrivacyApiAuth 后 window.open 提审表单）
await waitDialog('安全测试');
const popupPromise = page.waitForEvent('popup', { timeout: 20000 });
p = await center(['安全测试', '继续提交']);
await page.mouse.click(p.x, p.y, { label: '继续提交' });
const form = await popupPromise;
await form.waitForLoadState().catch(() => {});
await form.waitForTimeout(2500);

// 3. 填表：版本描述、隐私（collect=采集用户隐私 / none=未采集，默认 none）
await form.click(privacy === 'collect' ? 'text="采集用户隐私"' : 'text="未采集用户隐私"', { label: '隐私选项' });
await form.fill('textarea', desc.slice(0, 200));
await form.cdp('Network.enable', {});
await form.events();
const fp = await form.evaluate(() => { const a = [...document.querySelectorAll('a')].filter(a => a.innerText.trim() === '提交审核' && a.offsetParent).pop(); a.scrollIntoView({ block: 'center' }); const r = a.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
await form.mouse.click(fp.x, fp.y, { label: '提交审核' });
// 选「未采集」时还有一层确认（隐私接口权限会被回收的提示）
await form.waitForTimeout(2500);
const confirm = await form.evaluate(() => { const d = [...document.querySelectorAll('.weui-desktop-dialog')].find(x => x.offsetParent && x.innerText.includes('确认提交审核')); if (!d) return null; const b = [...d.querySelectorAll('button')].find(b => b.innerText.includes('继续提交')); const r = b.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
if (confirm) await form.mouse.click(confirm.x, confirm.y, { label: '确定，继续提交' });
await form.waitForTimeout(5000);

// 4. 记录提交接口（只记 method/path/body 字段名，不记 token/openid）
const ev = await form.events();
const submit = ev.filter(e => e.method === 'Network.requestWillBeSent').map(e => e.params.request).filter(r => /submit_check|updatePrivacyCollectMgr/.test(r.url))
  .map(r => ({ method: r.method, path: decodeURIComponent((r.url.match(/path=([^&]+)/) || [, new URL(r.url).pathname])[1]), bodyKeys: r.postData ? [...new URLSearchParams(r.postData).keys()] : [] }));
const done = (await form.evaluate(() => document.body.innerText)).includes('已提交审核');
console.log(JSON.stringify({ spaceId: task.spaceId, submitted: done, submitRequests: submit }, null, 1));
// 回验请跑 wxamp-version-status.mjs（audit.auditStatus=1 即审核中）
await task.finish({ keep: [] });
