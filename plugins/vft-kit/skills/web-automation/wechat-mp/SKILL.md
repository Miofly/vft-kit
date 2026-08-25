---
name: wechat-mp
description: 用 ego-lite 浏览器登录态操作微信公众号后台（mp.weixin.qq.com）与微信开发者平台控制台（developers.weixin.qq.com/console/product/mp/<AppID>）。当用户说「发公众号」「公众号草稿」「把这篇文章放到公众号」「排版成公众号格式」「公众号素材/发表记录/用户数据」「查公众号接口权限/额度」「设置 IP 白名单」「重置 AppSecret」「40164」「48001」「公众号发不出去」「个人号能调哪些接口」，或提到微信公众平台后台、开发者平台控制台、appmsg 编辑器、草稿箱、freepublish 时使用。也用于判断某个微信接口在当前账号上到底有没有权限——控制台的「接口权限与额度」是唯一权威来源，不要靠记忆回答。
---

# 微信公众号 / 开发者平台自动化

两个后台，职责不同，别搞混：

| 站点 | 管什么 | 入口 |
|---|---|---|
| 微信公众平台 `mp.weixin.qq.com` | 内容侧：草稿箱、图文编辑器、素材库、发表记录、用户管理、数据 | `/cgi-bin/home?t=home/index&token=<token>&lang=zh_CN` |
| 微信开发者平台 `developers.weixin.qq.com` | 开发侧：AppID/AppSecret、IP 白名单、接口权限与额度、域名与消息推送 | `/console/product/mp/<AppID>?tab1=<tab1>&tab2=<tab2>` |

2025-12-01 起公众平台的「设置与开发 → 开发接口管理」已迁到开发者平台，公众平台那页只剩一条迁移通知。要改密钥、白名单、看接口权限，一律去开发者平台。

## 前置：ego-lite 登录态

两个站都靠 ego-lite 复用用户已登录的浏览器态，**不需要重新扫码，也不要去 `.secrets` 找密码**。开工第一步固定是复用同一个 task space：

```bash
ego-browser nodejs <<'EOF'
const task = await useOrCreateTaskSpace('wechat mp <做什么>')
cliLog('task id: ' + task.id)   // 后续 heredoc 用 useOrCreateTaskSpace(<id>) 续用
EOF
```

如果打开后落在登录页（出现「微信快捷登录 / 扫码登录」），说明登录态过期：`handOffTaskSpace(id)` 交还控制权，请用户点「微信快捷登录」→ 在微信客户端点「允许」→ 选择目标公众号，等用户回复继续后再 `takeOverTaskSpace(id)`。**别自己反复重试**，登录必须人来做。

## token：每次登录都变，绝不能硬编码

公众平台所有 `/cgi-bin/*` 页面都带 `?token=<9-10位数字>`，这是会话 token，重新登录就换一个。**永远从当前页面 URL 现取**，不要复用用户消息里贴的旧 token（那个多半已经失效）：

```js
const tk = (await pageInfo()).url.match(/token=(\d+)/)[1]
```

常用页面（把 `<tk>` 换成现取的值）：

| 页面 | 路径 |
|---|---|
| 草稿箱 | `/cgi-bin/appmsg?begin=0&count=10&type=77&action=list_card&token=<tk>&lang=zh_CN` |
| 新建图文 | `/cgi-bin/appmsg?t=media/appmsg_edit_v2&action=edit&isNew=1&type=77&createType=0&token=<tk>&lang=zh_CN` |
| 素材库 | `/cgi-bin/filepage?type=2&begin=0&count=12&token=<tk>&lang=zh_CN` |
| 发表记录 | `/cgi-bin/appmsgpublish?sub=list&begin=0&count=10&token=<tk>&lang=zh_CN` |
| 用户管理 | `/cgi-bin/contactmanage?t=user/index&pageidx=0&type=0&token=<tk>&lang=zh_CN` |
| 账号设置 | `/cgi-bin/settingpage?t=setting/index&action=index&token=<tk>&lang=zh_CN` |

开发者平台控制台不用 token，用 AppID + tab 参数直达，详见 `references/console.md`。

## 发一篇文章（Markdown → 草稿箱）

这是最常见的任务，四步，全部验证过：

**1. Markdown 转公众号 HTML** — 编辑器不认外部 CSS 也会丢 class，排版必须是 inline style：

```bash
node scripts/md-to-mp-html.mjs article.md --json > /tmp/mp.json   # {title, html}
```

一级标题 `#` 会被提成文章标题、不进正文；非微信域名的链接会降级成「文字（URL）」，因为公众号会剥掉这类 `<a href>`，留着就是死链。脚本自检：`node scripts/md-to-mp-html.mjs --selftest`。

**2. 打开一个全新的编辑器页**。编辑器是 ProseMirror，粘贴是追加而不是替换，在已有内容的页面上重复粘会叠成两三份。与其想办法清空，不如每次都 `isNew=1` 开一张干净的：

```js
await gotoAndWait('https://mp.weixin.qq.com/cgi-bin/appmsg?t=media/appmsg_edit_v2&action=edit&isNew=1&type=77&createType=0&token=' + tk + '&lang=zh_CN', { timeout: 40 })
await wait(7)   // 编辑器初始化慢，等不够会拿不到 .ProseMirror
```

**3. 写标题和正文**。页面上有两个 `.ProseMirror`，靠父元素 class 区分：`title-editor__input` 是标题，`rich_media_content` 是正文。标题用 `insertText`（纯文本），正文用**合成 paste 事件**——ProseMirror 会自己解析 `text/html` 并转成公众号的 `<span leaf>` 结构，h2/strong/列表/表格都保得住；直接写 `innerHTML` 则会被 PM 的 state 覆盖掉：

```js
const res = await js(`(() => {
  const pm = [...document.querySelectorAll('.ProseMirror')]
  const body = pm.find(e => e.parentElement.className.includes('rich_media_content'))
  const titleEl = pm.find(e => e.parentElement.className.includes('title-editor__input'))
  titleEl.focus(); document.execCommand('insertText', false, ${JSON.stringify(title)})
  const dt = new DataTransfer(); dt.setData('text/html', ${JSON.stringify(html)}); dt.setData('text/plain', '')
  body.focus()
  body.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }))
  const author = document.querySelector('#author')
  if (author) { author.value = ${JSON.stringify(author)}; author.dispatchEvent(new Event('input', { bubbles: true })) }
  return { title: titleEl.textContent, chars: body.innerText.length, h2: body.querySelectorAll('h2').length }
})()`)
```

`dispatchEvent` 返回 `false` 是正常的——说明 PM 调了 `preventDefault` 接管了粘贴。判断成功要看返回的 `chars` / `h2` 数，不是看返回值。

**4. 存草稿**。点之前先关掉可能盖住按钮的新功能弹窗：

```js
await js(`(() => {
  document.querySelectorAll('.weui-desktop-dialog__close-btn').forEach(b => b.click())
  const know = [...document.querySelectorAll('button, a')].find(b => /我知道了/.test(b.textContent) && b.offsetParent)
  if (know) know.click()
})()`)
await wait(2)
await js(`(() => [...document.querySelectorAll('button, .weui-desktop-btn, a')].find(b => b.textContent.replace(/\\s+/g,'').trim() === '保存为草稿').click())()`)
await wait(5)
cliLog((await pageInfo()).url)   // URL 出现 appmsgid=<数字> 即保存成功
```

保存成功的标志是地址栏多出 `appmsgid=`，同时草稿箱列表首条变成这篇。想二次确认就回草稿箱页读一眼列表。

**发表（`发表` 按钮）要谨慎**：它是不可逆的对外动作，且未认证账号每天只有有限次群发。**除非用户明确说「发布/群发/直接发出去」，一律停在草稿**，把草稿链接给用户让他自己点发表。

## 判断某个接口能不能调（别靠记忆）

开发者平台「接口管理 → 接口权限与额度」按分类列出每个接口的**有权限 / 无权限 + 每日额度 + 当日已用**，是唯一权威来源。个人主体未认证账号的典型结论：基础接口（access_token 等）有权限，**发布能力（发布草稿、发布状态查询、获取已发布列表…）全部无权限**，提示「完成账号主体认证后，可获得权限」。

具体抓取步骤、分类清单、以及切分类时那个「表格内容滞后一拍」的坑，见 `references/console.md`。

## 常见报错对照

| 现象 | 真实原因 | 怎么办 |
|---|---|---|
| `errcode 40164 invalid ip x.x.x.x not in whitelist` | 调用方公网 IP 不在白名单 | 报错信息里就带着那个 IP，去开发者平台「基础信息 → API IP白名单 → 设置名单」加进去。注意家宽 IP 会变，服务器和本机是两个 IP |
| `errcode 48001 api unauthorized` | 该接口当前账号没权限 | 查「接口权限与额度」确认；未认证个人号的发布类接口属于这一类，加白名单也没用 |
| AppSecret 忘了 | 明文只在重置那一刻显示一次 | 只能重置，**重置后旧 secret 立即失效**，线上服务会挂，先确认能同步更新配置再点 |
| 编辑器里粘出来两三份内容 | 在旧页面上重复 paste | 重开 `isNew=1` 的编辑器页，别试图清空 |
| 拿不到 `.ProseMirror` | 编辑器还没初始化完 | `await wait(7)` 之后再取，必要时轮询直到出现两个 PM 节点 |

## 参考文件

- `references/console.md` — 开发者平台控制台：tab URL 规则、AppSecret/IP 白名单位置、接口权限与额度的抓取脚本
- `references/mp-backend.md` — 公众平台后台：页面清单、素材库/发表记录/用户管理的读取方式、编辑器 DOM 结构备忘
- `scripts/md-to-mp-html.mjs` — Markdown → 公众号 inline-style HTML（带 `--selftest`）

## 边界

- **凭据不进这个 skill**：AppID 由调用方传入或从页面读；AppSecret、账号密码一律不写进仓库。需要长期保存走各自的凭据管理流程。
- **只做用户要求的那一步**：解除第三方授权、重置密钥、发表、删除文章都是不可逆或对外可见的操作，动手前先确认。
- 涉及多个公众号时，先在页面右上角确认当前登录的是哪个账号（`.weui-desktop-account__info` 的文本），别在错的号上写东西。
