// 小程序提交审核（接口版，2026-10-06 实测成功；页面版 wxamp-submit-audit.mjs 留作兜底）
// 运行（ego-browser 的 nodejs 运行时不继承环境变量，参数写在脚本前面）：
//   { printf 'globalThis.ARGS=%s;\n' "$(node -p 'JSON.stringify({version:process.argv[1],desc:process.argv[2],privacy:"none"})' 4.0.6 '本版说明')"; cat wxamp-submit-audit-api.mjs; } | ego-browser nodejs
//   privacy：none = 未采集用户隐私；collect = 采集（需先在后台配好隐私保护指引）
// 流程：登录态 token → getcodepage 找到该版本的开发版（取 open_id、上传者昵称）→ get_class 取 auto_id
//      → updatePrivacyCollectMgr → submit_check → 再读 getcodepage，experience_info.audit_status=1 即审核中。
// 只在已登录的 mp.weixin.qq.com 页面里用 page.fetch 调用（带 cookie），不打印 token、openid。
const { version, desc, privacy = 'none' } = globalThis.ARGS || {};
if (!version || !desc) { console.log('缺少 ARGS.version / ARGS.desc'); process.exit(2); }

const task = await taskSpace("小程序提审");
const page = task.page("p1");
const hasToken = u => /\/wxamp\/[^?]*\?.*token=\d+/.test(u);
await page.goto("https://mp.weixin.qq.com/wxamp/wacodepage/getcodepage");
await page.waitForTimeout(2500);
if (!hasToken(await page.url())) {
  // 已登录时直接打开 /wxamp/... 可能不带 token；登录页会自动跳回带 token 的地址
  await page.goto("https://mp.weixin.qq.com/cgi-bin/loginpage?url=%2Fwxamp%2Fwacodepage%2Fgetcodepage");
  await page.waitForTimeout(2500);
  if (!hasToken(await page.url())) {
    console.log(JSON.stringify({ spaceId: task.spaceId, needLogin: true }));
    await task.handOff();
    process.exit(0);
  }
}
const token = (await page.url()).match(/token=(\d+)/)[1];
const route = p => `/wxamp/cgi/route?path=${encodeURIComponent(p)}&token=${token}&lang=zh_CN&random=${Math.random()}`;
const json = r => (typeof r.body === 'string' ? JSON.parse(r.body) : r.body);
const codePage = async () => {
  const outer = json(await page.fetch(route(`/wxopen/wacodepage?action=getcodepage&f=json&token=${token}&lang=zh_CN`), { timeout: 15000 }));
  return { outer, data: JSON.parse(outer.code_data || '{}') };
};

// 1. 找开发版：同一版本号可能有多个上传者（开发者工具、ci 机器人各占一条），取最新的一条
const { outer, data } = await codePage();
if (!outer.can_submit_check) { console.log(JSON.stringify({ error: '当前不能提审（可能已有版本在审核中）' })); process.exit(1); }
const dev = (data.develop_info?.info_list || [])
  .filter(i => i.basic_info?.version === version)
  .sort((a, b) => b.basic_info.time - a.basic_info.time)[0];
if (!dev) { console.log(JSON.stringify({ error: `开发版 ${version} 不存在` })); process.exit(1); }
const b = dev.basic_info;
const openid = b.open_id || b.openid;
const nick = b.nick_name || b.nickname || '';
if (!openid) { console.log(JSON.stringify({ error: '开发版里没找到 open_id 字段', keys: Object.keys(b) })); process.exit(1); }

// 2. 表单初始化：auto_id 在 public_key_info（JSON 字符串）里；class_info 带备注、加急类型
const gc = json(await page.fetch(route(`/wxopen/wadevelopcode?action=get_class&openid=${openid}&user_name=${encodeURIComponent(nick)}`), { timeout: 15000 }));
if (gc.ret !== 0) { console.log(JSON.stringify({ error: 'get_class 失败', ret: gc.ret })); process.exit(1); }
const autoId = gc.public_key_info ? JSON.parse(gc.public_key_info).auto_id : 0;
const ci = typeof gc.class_info === 'string' ? JSON.parse(gc.class_info) : (gc.class_info || {});

// 3. 隐私声明
const pr = json(await page.fetch(`/wxamp/cgi/version/updatePrivacyCollectMgr?is_not_collect=${privacy === 'collect' ? 0 : 1}&version_openid=${openid}&token=${token}&lang=zh_CN&random=${Math.random()}`, { timeout: 15000 }));

// 4. 提交（字段与页面 finalSubmit 一致；无需登录时测试账号留空）
const body = new URLSearchParams({
  ticket: 'qrcheckTicket', openid, auto_id: String(autoId || 0),
  version_desc: desc.slice(0, 200), speedup_audit: '0', speedup_type: ci.speedup_type || '修复漏洞', speedup_desc: '',
  encrypted_username: '', encrypted_password: '', remark: ci.remark || '', order_path: gc.online_order_path || '',
  feedback_info: '', feedback_status: '1', only_run_wxwork: '0', argue_item: '',
  preview_info: JSON.stringify({ pic_id_list: [], video_id_list: [] }), feedback_stuff: '',
});
const sr = json(await page.fetch(route('/wxopen/wadevelopcode?action=submit_check'), {
  method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded; charset=UTF-8' }, body: body.toString(), timeout: 20000,
}));

// 5. 回读
await page.waitForTimeout(2000);
const after = (await codePage()).data.experience_info?.basic_info;
console.log(JSON.stringify({
  spaceId: task.spaceId, privacyRet: pr.ret, submitRet: sr.ret, submitErr: sr.base_resp?.err_msg,
  audit: after && { version: after.version, auditStatus: after.audit_status },
}, null, 1));
await task.finish({ keep: [] });
