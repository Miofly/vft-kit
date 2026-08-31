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

两个站都优先靠 ego-lite 复用用户已登录的浏览器态，**不要去 `.secrets` 找密码**。开工第一步固定是复用同一个 task space：

```bash
ego-browser nodejs <<'EOF'
const task = await useOrCreateTaskSpace('wechat mp <做什么>')
cliLog('task id: ' + task.id)   // 后续 heredoc 用 useOrCreateTaskSpace(<id>) 续用
EOF
```

如果打开后落在登录页，先由 agent 自动点击「登录」/「微信快捷登录」，等待页面推进到二维码、微信客户端确认或账号选择等真人步骤；**只有实际出现这些步骤时**才调用 `handOffTaskSpace(id)` 交还控制权，并明确告诉用户操作内容。用户完成后回复继续，再用同一个 id 调 `takeOverTaskSpace(id)`，核对右上角公众号名称和当前 URL token。若点击后已自动恢复登录，则直接继续，不要提前 handoff，也不要反复重试。

### 远程扫码时的二维码交付

用户无法看到本机页面时，优先把**只含二维码的截图**作为当前对话附件发送；不要上传公网、写入仓库或放进群聊。保持原 task space 和登录页不关闭，二维码过期后重新生成，登录成功或过期后删除 `other/temp/wechat-mp/login-qr.png`。

若必须发到微信或 QQ，这是桌面客户端 GUI 转发，不是公众号 API：

- 微信：Mac 微信必须已登录，目标优先选「文件传输助手」或用户指定的私聊；QQ：QQ 客户端必须已登录，目标优先选「我的电脑」或用户指定的私聊。
- macOS 需要给实际执行自动化的终端/脚本授予“辅助功能”权限，并预先明确收件目标；不读取或索要客户端密码。
- 用户在手机端打开图片，保存后用“扫一扫/从相册识别”，或用另一块屏幕直接扫码。二维码是短时登录凭证，发送后立即扫码。
- 如果桌面客户端本身未登录，先停下让用户完成客户端登录；不要试图用公众号登录二维码反向引导桌面客户端登录。

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

## 封面是发表的硬前置

没有封面时点「发表」**不会弹确认框**，微信只在页面上挂一条内联 tips：`必须插入一张图片`。自动化里表现为"点了发表什么都没发生"，很容易误判成点击失败或弹窗识别有问题。发表前先确认封面已设。

**读封面状态不能数 `<img>`** —— 编辑器用 CSS 背景图显示封面，节点是 `.js_cover_preview_new`，判据是它的 `background-image` 含 `mmbiz`；外层容器 class 也会变成 `has_first_cover`。草稿数据侧看 `multi_item[0].cover` 或 `item.img_url` 非空。

可靠的设封面路径（每一步都用真实鼠标点击，并先把视口调到 1100 高）：

1. 点 `.js_cover_btn_area` 展开菜单（**不是** hover——hover 触发不稳定）
2. 点「从图片库选择」
3. 素材库右侧的缩略图是 `.weui-desktop-img-picker__img-thumb`，点第一张（最近上传的排在最前）。左侧 `.weui-desktop-grid__item` 是分类菜单，点它没用
4. 「下一步」→ 裁剪页「确认」

正文首图有时会被自动取作封面，但**不保证**：同一套流程下有的草稿自动带上了、有的没有，别依赖它。

## 封面：别跟悬停菜单较劲

封面区 `.js_cover_btn_area` 的选项菜单（`从图片库选择` / `微信扫码上传` / `AI配图` / `.js_selectCoverFromContent`）默认是 `visibility: hidden`，靠 hover 显形。**用 `offsetParent` 判可见会误判**——这些节点 `offsetParent` 非空、`getBoundingClientRect()` 有尺寸，但 `document.elementFromPoint()` 命中的是它们背后的元素，点击全部落空。判可见必须同时看 `getComputedStyle(el).visibility`。

更省事的办法是**不碰封面控件**：往正文顶部粘一张图，编辑器会自动把 data URI 上传成 `mmbiz.qpic.cn` 素材，保存草稿后微信会把正文首图取作封面（草稿数据里 `cover` / `img_url` 非空即成功）。

```js
const dt = new DataTransfer()
dt.setData('text/html', '<img src="data:image/jpeg;base64,...' + '" width="900">')
body.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }))
```

一次 paste 常会插入**两张**相同图片，粘完数一下 `img[width>10]`，多的选中后按 Backspace 删掉。

## 视口高度会吃掉点击

ego/CDP 默认视口可能只有 700 多像素高，而编辑器的「保存为草稿」「发表」和弹窗按钮经常在 y > 750 的位置——真实鼠标点击直接落到屏幕外，静默失败。动手前先 `Emulation.setDeviceMetricsOverride({ width: 1512, height: 1100, deviceScaleFactor: 1, mobile: false })`，或每次点击前用 `document.elementFromPoint(cx, cy)` 确认命中目标本身。

## 从草稿箱走发表流程

草稿卡片上的「发表」按钮是 `<a href="javascript:;">`，处理函数走 `window.open`，**会被弹窗拦截**：真实鼠标点击和 DOM `.click()` 都表现为完全没反应——不跳转、不弹窗、不开新标签。无头/自动化环境尤其容易踩，且没有任何报错。

绕过办法是在当前标签直接打开它要开的编辑器发表态 URL：

```
/cgi-bin/appmsg?t=media/appmsg_edit&action=edit&type=77&appmsgid=<app_id>&isMul=1&replaceScene=0&isSend=1&isFreePublish=0&token=<tk>&lang=zh_CN
```

`<app_id>` 从草稿列表取：草稿页的 `window.wx.cgiData` 键是 **`item`**（不是 `app_msg_list`），`item[].app_id` 是 appmsgid，`item[].multi_item[].title` 是各子图文标题。

进去后按钮链是：`button.mass_send`（发表）→ 弹窗内 primary「发表」→ 二次弹窗「继续发表」。第一个弹窗会显示**今天还有几次群发通知次数**，这是决定开不开群发通知的唯一权威来源。

### 最终发表要管理员扫码验证

点完「继续发表」后请求链：`/cgi-bin/masssend` → `/misc/safeassistant`（拿 ticket）→ `/safe/safeqrconnect`（拿 uuid）→ 轮询 `/safe/safeuuid`。`errcode: 401` = 等待扫码。

二维码是 `img.qrcode.js_qrcode`（300×300），外层容器 `.safe_check` / `.qrcode_scan`，**不在 `.weui-desktop-dialog` 内**——只查 dialog 会完全漏掉它，然后无人扫码、二维码超时、文章静默地没发出去。

**成功判据只有一个**：发表记录 `/cgi-bin/appmsgpublish?sub=list` 的 `window.wx.cgiData.publish_list[].appmsg_info[]` 里按完整标题精确命中，并拿到 `content_url`。二维码消失、弹窗关闭、页面跳回 `/cgi-bin/home` 都不能算成功。

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
| 点「发表」完全没反应 | 按钮走 `window.open`，被弹窗拦截 | 直接在当前标签打开 `isSend=1` 的编辑器 URL，见上文「从草稿箱走发表流程」 |
| 点完「继续发表」文章却没发出去 | 漏了 `/safe/safeqrconnect` 的管理员验证二维码 | 找 `img.qrcode.js_qrcode`（不在 dialog 里），扫码后再查发表记录确认 |

## 参考文件

- `references/console.md` — 开发者平台控制台：tab URL 规则、AppSecret/IP 白名单位置、接口权限与额度的抓取脚本
- `references/mp-backend.md` — 公众平台后台：页面清单、素材库/发表记录/用户管理的读取方式、编辑器 DOM 结构备忘
- `scripts/md-to-mp-html.mjs` — Markdown → 公众号 inline-style HTML（带 `--selftest`）

## 边界

- **凭据不进这个 skill**：AppID 由调用方传入或从页面读；AppSecret、账号密码一律不写进仓库。需要长期保存走各自的凭据管理流程。
- **只做用户要求的那一步**：解除第三方授权、重置密钥、发表、删除文章都是不可逆或对外可见的操作，动手前先确认。
- 涉及多个公众号时，先在页面右上角确认当前登录的是哪个账号（`.weui-desktop-account__info` 的文本），别在错的号上写东西。
