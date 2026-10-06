// 只读：查小程序线上 / 审核中 / 开发版本状态（mp.weixin.qq.com/wxamp 版本管理的数据接口，已实测）
// 运行：ego-browser nodejs < wxamp-version-status.mjs
// 未登录时会 handOff 让用户扫码，并选「小程序」账号（同一微信号下的公众号进不了 /wxamp），扫完再跑一次。
const task = await taskSpace("小程序版本状态");
const page = task.page("p1");
await page.goto("https://mp.weixin.qq.com/wxamp/wacodepage/getcodepage");
await page.waitForTimeout(2500);
let url = await page.url();
// 注意：登录页的 url 参数里也含 wxamp，必须看路径而不是整串
if (!/\/wxamp\/[^?]*\?.*token=\d+/.test(url)) {
  await page.goto("https://mp.weixin.qq.com/cgi-bin/loginpage?url=%2Fwxamp%2Fwacodepage%2Fgetcodepage");
  await page.waitForTimeout(2500);
  url = await page.url();
  if (!/token=\d+/.test(url)) {
    console.log(JSON.stringify({ spaceId: task.spaceId, needLogin: true }));
    await task.handOff();
    process.exit(0);
  }
}
const token = url.match(/token=(\d+)/)[1];
const path = encodeURIComponent(`/wxopen/wacodepage?action=getcodepage&f=json&token=${token}&lang=zh_CN`);
const r = await page.fetch(`/wxamp/cgi/route?path=${path}&token=${token}&lang=zh_CN&random=${Math.random()}`, { timeout: 15000 });
const outer = typeof r.body === 'string' ? JSON.parse(r.body) : r.body;
const data = JSON.parse(outer.code_data || '{}');
const brief = info => info && info.basic_info && {
  version: info.basic_info.version,
  describe: info.basic_info.describe,
  time: new Date(info.basic_info.time * 1000).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' }),
  status: info.basic_info.status,
  auditStatus: info.basic_info.audit_status,
  failReason: info.basic_info.fail_reason || undefined,
};
console.log(JSON.stringify({
  spaceId: task.spaceId,
  canSubmit: outer.can_submit_check,
  online: brief(data.online_info),
  // experience_info 在提审后承载「审核版本」：audit_status=1 审核中（其余取值待观察后补充）
  audit: brief(data.experience_info),
  develop: (data.develop_info?.info_list || []).map(i => ({ ...brief(i), isExperience: i.is_exper })),
}, null, 1));
await task.finish({ keep: [] });
