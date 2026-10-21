#!/usr/bin/env node
// 容错 / 边界测试：清存储、损坏存储、未登录守卫、Hydration 一致性。
// 用法：node resilience-audit.mjs <baseURL> [--q=?debug=true] [--guard=/system,/user/center]
// 例：node resilience-audit.mjs https://example.com --q='?debug=true' --guard='/system,/user/center'
import { chromium } from './_pw.mjs';

const args = process.argv.slice(2);
const base = (args.find(a => a.startsWith('http')) || '').replace(/\/$/, '');
if (!base) { console.error('需要 baseURL'); process.exit(1); }
const q = (args.find(a => a.startsWith('--q=')) || '--q=').slice(4);
const guard = (args.find(a => a.startsWith('--guard=')) || '--guard=/system,/user').slice(8).split(',').filter(Boolean);
const HOME = base + '/' + q;

const IGNORE = [/play\(\) request was interrupted/i, /ResizeObserver loop/i, /pagead|googlesyndication|adsbygoogle|doubleclick|google-analytics|googletagmanager/i, /Failed to load resource/i];
const benign = m => IGNORE.some(re => re.test(m));
function watch(page){ const errs=[], pe=[]; page.on('console', m => { if (m.type()==='error' && !benign(m.text())) errs.push(m.text().slice(0,120)); }); page.on('pageerror', e => pe.push(String(e).slice(0,150))); return { errs, pe }; }
async function snap(page){ return page.evaluate(() => { const app=document.querySelector('#app'); const ls=[]; for(let i=0;i<localStorage.length;i++) ls.push(localStorage.key(i)); const ss=[]; for(let i=0;i<sessionStorage.length;i++) ss.push(sessionStorage.key(i)); return { lsKeys:ls, ssKeys:ss, cookie:document.cookie.slice(0,120), appChildren:app?app.children.length:-1, bodyLen:(document.body?.innerText||'').trim().length, title:document.title, path:location.pathname }; }).catch(()=>({})); }
const goHome = async (page, wait='domcontentloaded') => { try { await page.goto(HOME, { waitUntil:wait, timeout:30000 }); } catch(e){} };

(async () => {
  const browser = await chromium.launch({ headless:true });

  // 1. 正常首访：存储结构 + 登录态存哪
  console.log('=== 1. 正常首访（未登录）存储结构 ===');
  let ctx = await browser.newContext(); let page = await ctx.newPage(); let w = watch(page);
  await goHome(page); let s = await snap(page);
  console.log('localStorage:', JSON.stringify(s.lsKeys), '\nsessionStorage:', JSON.stringify(s.ssKeys), '\ncookie:', s.cookie || '(none)');
  console.log(`render children=${s.appChildren} body=${s.bodyLen} | 业务err=${w.errs.length} pageerr=${w.pe.length}`);
  await ctx.close();

  // 2. 清 localStorage+sessionStorage+cookie 后 reload（隐身/清缓存等价）
  console.log('\n=== 2. 清空所有存储后 reload（不该白屏）===');
  ctx = await browser.newContext(); page = await ctx.newPage(); w = watch(page);
  await goHome(page);
  await page.evaluate(() => { localStorage.clear(); sessionStorage.clear(); document.cookie.split(';').forEach(c => { document.cookie = c.split('=')[0] + '=;expires=' + new Date(0).toUTCString() + ';path=/'; }); }).catch(()=>{});
  try { await page.reload({ waitUntil:'domcontentloaded', timeout:30000 }); } catch(e){}
  s = await snap(page);
  console.log(`children=${s.appChildren} body=${s.bodyLen} ${s.appChildren<=0?'❌白屏':'✅正常'} | 业务err=${w.errs.length} pageerr=${w.pe.length}`, w.pe.slice(0,2));
  await ctx.close();

  // 3. 注入损坏存储数据后 reload（脏数据容错，不该崩溃）
  console.log('\n=== 3. 注入损坏存储后 reload（容错健壮性）===');
  ctx = await browser.newContext(); page = await ctx.newPage(); w = watch(page);
  await goHome(page);
  await page.evaluate(() => { try { localStorage.setItem('APP-USER','{corrupted'); } catch(e){} document.cookie='APP-USER=%7Bbad;path=/'; localStorage.setItem('theme','__invalid__'); }).catch(()=>{});
  try { await page.reload({ waitUntil:'domcontentloaded', timeout:30000 }); } catch(e){}
  s = await snap(page);
  const hyd = w.errs.filter(e => /hydrat|mismatch/i.test(e));
  console.log(`children=${s.appChildren} body=${s.bodyLen} ${s.appChildren<=0?'❌崩溃':'✅容错OK'} | 业务err=${w.errs.length} hydration=${hyd.length}`, w.errs.slice(0,2));
  await ctx.close();

  // 4. 未登录访问受保护路由（守卫是否重定向 / 是否渲染空壳）
  console.log('\n=== 4. 未登录访问受保护路由（守卫行为）===');
  for (const p of guard) {
    ctx = await browser.newContext(); page = await ctx.newPage(); w = watch(page);
    try { await page.goto(base + p + q, { waitUntil:'domcontentloaded', timeout:25000 }); } catch(e){}
    s = await snap(page);
    const verdict = s.path !== p ? `↪重定向到 ${s.path}` : s.appChildren <= 0 ? '空壳/未渲染' : '停留并渲染（确认是否该拦）';
    console.log(`  ${p} → ${verdict} children=${s.appChildren} err=${w.errs.length}`);
    await ctx.close();
  }

  // 5. 连续两次访问：Hydration mismatch 检测（SSR 站关键）
  console.log('\n=== 5. 连续两次访问首页（Hydration 一致性）===');
  ctx = await browser.newContext();
  for (let i = 1; i <= 2; i++) {
    page = await ctx.newPage(); w = watch(page);
    await goHome(page); s = await snap(page);
    const hyd = w.errs.filter(e => /hydrat|mismatch/i.test(e));
    console.log(`  visit#${i} children=${s.appChildren} hydrationMismatch=${hyd.length}`, hyd.slice(0,1));
    await page.close();
  }
  await ctx.close();

  await browser.close();
  console.log('\n判读：②③ 出现白屏/崩溃=容错缺陷；⑤ hydrationMismatch>0=SSR 与客户端首帧不一致（丢弃 SSR 重渲染，浪费 SSR + 可能闪烁），排查 SSR/client 分支：主题 cookie 读取时机 / Date / Math.random / import.meta.env.SSR 条件渲染。');
})();
