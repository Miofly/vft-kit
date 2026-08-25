# 微信开发者平台控制台（developers.weixin.qq.com）

公众号控制台入口：`https://developers.weixin.qq.com/console/product/mp/<AppID>`，页面用 `tab1` / `tab2` 两级参数直达，不带 token，登录态由 ego-lite 复用。

## tab 参数对照（实测）

| 左侧导航 | tab1 | 二级 tab2 | 里面有什么 |
|---|---|---|---|
| 基础信息 | `basicInfo` | — | AppID、原始 ID、邮箱、管理员、主体与认证状态；**开发密钥**（AppSecret 重置/冻结）、**API IP白名单**、域名与消息推送配置 |
| 开放能力 | `openAbility` | — | 各项开放能力的开通状态 |
| 接口管理 | `apiManager` | `apiMonitoring`（默认）/ `apiAlerts` / `apiPermissionsAndQuota` | 接口监控、接口告警、**接口权限与额度** |
| 绑定关系 | `bindingInfo` | `wxAccount` | 绑定的小程序、开放平台等 |
| 授权关系 | `authInfo` | `wxAccount` | 已授权的第三方平台列表（可解除授权） |

`tab2` 只认真实存在的值，传错会静默回落到该 tab1 的默认二级页——所以拼 URL 后**要用 `pageInfo().url` 核对一次实际落在哪个 tab**，不要假设跳成功了。

页面是 WeUI Desktop，导航项类名稳定：`.weui-desktop-tab__nav`（当前项多一个 `.weui-desktop-tab__nav_current`），可以直接按文本点：

```js
await js(`(() => { const li = [...document.querySelectorAll('.weui-desktop-tab__nav')].find(e => e.textContent.trim() === '接口管理'); li && li.click() })()`)
```

## 基础信息页要点

- **AppSecret**：只有「重置 / 冻结」两个动作，看不到当前值。重置需要管理员在微信里确认，新值**只显示一次**，且旧值立即失效——线上在用的话，先确认能同步更新配置再点。
- **API IP白名单**：「设置名单」入口在 AppSecret 下方。不设白名单调不了 `access_token`（报 40164）。40164 的错误信息里会直接给出被拒的 IP，照抄进去即可。注意本机公网 IP 与服务器出口 IP 是两个，两边都要调接口就都得加；家宽 IP 会漂移。
- **认证状态**：`个人` + `暂未认证` 意味着发布类接口全无权限，这是很多「接口调不通」问题的真实根因，先看这里能省半天。

## 抓「接口权限与额度」

URL：`?tab1=apiManager&tab2=apiPermissionsAndQuota`

页面按大类分面板（`.api-permissions-and-quota__api-panel`，标题在 `__title` 里）：**服务端接口**、**网页应用接口**。每个面板顶部有一个级联下拉切分类，表格是 div 模拟的，行类名 `.api-permissions-and-quota__api-panel__table__row`（第一行是表头）。

服务端接口的 15 个分类：基础接口、openApi管理、自定义菜单、基础消息、素材管理、草稿管理与商品卡片、留言管理、发布能力、用户管理、客服消息、数据统计、网页开发、智能接口、微信门店、微信就医助手。

**坑：切分类后表格内容滞后。** 点完下拉项立刻读表，读到的还是上一个分类的行——连读三个分类会得到三份一样的数据，看起来像「所有分类权限都相同」的假结论。必须轮询到内容真的变了再读：

```js
const readRows = async (panelTitle = '服务端接口') => await js(`(() => {
  const panel = [...document.querySelectorAll('.api-permissions-and-quota__api-panel')]
    .find(p => p.querySelector('.api-permissions-and-quota__api-panel__title')?.textContent.trim() === ${JSON.stringify(panelTitle)})
  return [...panel.querySelectorAll('.api-permissions-and-quota__api-panel__table__row')].slice(1).map(r => {
    const c = [...r.children].map(x => (x.textContent || '').replace(/\\s+/g, ' ').trim())
    return { api: c[0], perm: c[1].split('完成账号')[0].trim(), quotaPerDay: c[2], usedToday: c[3], ratePerMin: c[4] }
  })
})()`)

async function dumpCategory(cat) {
  const before = JSON.stringify(await readRows())
  await js(`(() => {
    const panel = [...document.querySelectorAll('.api-permissions-and-quota__api-panel')]
      .find(p => p.querySelector('.api-permissions-and-quota__api-panel__title')?.textContent.trim() === '服务端接口')
    const li = [...panel.querySelectorAll('.weui-desktop-form__dropdowncascade li')].find(l => (l.textContent || '').includes(${JSON.stringify(cat)}))
    li && li.click()
  })()`)
  let rows = []
  for (let i = 0; i < 10; i++) { await wait(1); rows = await readRows(); if (JSON.stringify(rows) !== before) break }
  return rows
}
```

`perm` 的取值是 `有权限` / `无权限`；无权限那格后面常跟一句「完成账号主体认证后，可获得权限」，上面的 `split('完成账号')` 就是把这句剪掉只留状态。

个人主体未认证账号的实测结果（可作为对照基线）：

- 基础接口：获取接口调用凭据（2000 次/日）、获取稳定版接口调用凭据（50 万/日）、网络通信检测、获取微信 API/推送服务器 IP —— 均**有权限**
- 发布能力：发布草稿、发布状态查询、获取已发布图文信息、获取已发布的消息列表、删除发布文章 —— 均**无权限**

也就是说未认证个人号走不通 `draft → freepublish` 这条发文章的 API 链路，只能用公众平台后台的编辑器手动/自动化写草稿再人工发表。
