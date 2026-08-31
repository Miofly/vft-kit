---
name: qr-login
description: 用 ego-lite 在隔离空间完成掘金、知乎、简书、今日头条、博客园、51CTO、CSDN、SegmentFault、小红书、少数派的扫码登录，并把二维码经 PushPlus/ntfy 推送给用户。支持标准微信 OAuth、嵌入式 OAuth iframe、公众号二维码、CSDN 微信小程序码、小红书主站/创作平台站内二维码与少数派微信 OAuth。用户要求登录这些平台、微信扫码登录或推送登录二维码时使用。
---

# 第三方平台扫码登录

用 ego-lite 打开目标站登录页，抓取标准微信 OAuth 码、公众号二维码、微信小程序码或站内二维码并推送给用户，用户手机扫码确认后接管验证登录结果。

全程在 ego 隔离空间后台完成：不 `open_application`、不激活窗口、不弹桌面通知。OAuth 可能使用 popup 或当前 tab，公众号码在站内页面，CSDN 使用站内 iframe；始终保留平台创建的真实上下文，不能猜或复制 OAuth URL。

## 站点矩阵（2026-08-29 实测）

“二维码确认”只表示已真实点击并看到可扫描二维码；“完整登录确认”表示已经完成用户扫码和站内登录态复核。

| 平台 | 结果 | 登录页与微信入口 | 二维码形态 / 限制 |
|---|---|---|---|
| 掘金 juejin | 完整登录确认 | `https://juejin.cn/`；可见 `.login-button` → `.oauth-box .oauth-bg` 第 2 个 | `open.weixin.qq.com` 标准图片；首页 `.login-button` 消失才算成功 |
| 知乎 zhihu | 完整登录确认 | `https://www.zhihu.com/signin`；`.Login-socialButton` 或 `button[class*="socialButton"]` 第 1 个 | `open.weixin.qq.com` 标准图片；访问 `/signin` 自动跳走、头像可见、登录控件消失才算成功 |
| 简书 jianshu | 完整登录确认 | `https://www.jianshu.com/sign_in`；`a#weixin.weixin` | ego 可能抑制 `_blank`；在同 task tab 打开该元素的官方 `href=/users/auth/wechat`，随后进入标准微信 OAuth |
| 今日头条 | 完整登录确认 | `https://www.toutiao.com/`；`a.login-button` → 真实点击 `span.web-login-confirm-info__checkbox[role="checkbox"]` → 严格确认 `aria-checked="true"` → `.web-login-other-login-method__list__item:nth-child(3)` | 默认码是头条 App；协议控件不是原生 `input`，微信入口创建标准微信 OAuth popup |
| 博客园 | 完整登录确认 | `https://account.cnblogs.com/signin`；`app-external-sign-in-providers .providers button:first-of-type`（子图 `WeChat.png`） | 站内 popup 的 `app-wechat-mp-qr img[alt="微信二维码"]`，扫码会关注博客园服务号并登录 |
| 51CTO | 完整登录确认 | `https://home.51cto.com/index?reback=https%3A%2F%2Fwww.51cto.com%2F`；`.login-type-switch:nth-child(1)` | 站内 `#login-wechat img.qr-img`，图片来自 `mp.weixin.qq.com/cgi-bin/showqrcode` |
| CSDN | 完整登录确认 | `https://www.csdn.net/`；`a.toolbar-btn-loginfun` → iframe `#passportbox iframe[name="passport_iframe"]` → “微信登录” tab | `https://passport.csdn.net/login?code=applets` 内 `.login-code-wechat .public-code img`；280×280 JPEG data URI 微信小程序码 |
| SegmentFault 思否 | 完整登录确认 | `https://segmentfault.com/user/login`；`button.login-mode[data-mode="weixin"]` | `#weixinQrCode iframe` 内嵌标准微信 OAuth；iframe target 类型为 `iframe`、回调 `/user/oauth/weixin` |
| 小红书 xiaohongshu | 主站、创作平台完整登录确认 | 主站 `https://www.xiaohongshu.com/explore`；创作平台 `https://creator.xiaohongshu.com/publish/publish?from=menu&target=article` 被 401 重定向后，真实点击短信登录卡右上角 64×64 模式图标 | 主站 `.login-modal img.qrcode-img`，小红书 App 或微信可扫；创作平台为 160×160 PNG data URI，页面要求小红书 App 扫码 |
| 少数派 sspai | 完整登录确认 | `https://sspai.com/write` → `/login`；`.ssCommunityIcon__weixin` | 当前 tab 进入 `open.weixin.qq.com/connect/qrconnect`；切换后 `img.js_qrcode_img.web_qrcode_img` 160×160 标准图片；扫码后回调 `/callback/weixin` |

掘金、知乎、今日头条默认码不是微信；必须依据矩阵进入微信入口，不能看到二维码就抓。当前 skill 只支持表中十个平台，其余平台不要自动套用。

## 与文章发布扩展的边界

- 本 skill 的登录态只保存在 `qr-login-<平台>` 对应的 ego task space；不会自动写入 Chrome 扩展所在的用户目录，也不会向业务后端同步 Cookie。
- 用户要求“给 ArtiPub/文章发布助手登录”时，先确认目标是 ego 中继续操作，还是给 Chrome 扩展准备登录态。后者必须在扩展所在的 Chrome 用户目录完成官方登录并由扩展同步 Cookie；不得因 ego 登录成功就宣称发布助手已经可用。
- 两者仅复用平台入口、人工扫码和成功判定知识，不复制二维码、OAuth URL、Cookie 或账号密码；除非已验证为同一浏览器用户目录，否则一律按两套独立登录态处理。

## 主流程

```js
const task = await useOrCreateTaskSpace('qr-login-<平台>')
```

1. 只接受矩阵中的十个平台；用一个 `ego-browser nodejs` heredoc 完成整个浏览器阶段，不逐步探测已记录选择器。SegmentFault 走 OAuth iframe 分支，博客园/51CTO 走公众号二维码分支，CSDN 走小程序码分支，小红书走站内二维码分支，少数派走标准 OAuth 分支，其余四站走标准 OAuth 分支。
2. `gotoAndWait(<登录页>)` 强制刷新首页；按「登录成功判定」检查。未登录时按站点表打开登录弹窗，记录微信点击前的 `Target.getTargets`。微信入口必须取可见元素中心点后调用 ego `click({ x, y })` 真实鼠标点击；DOM `el.click()` 没有用户激活，Chromium 会拦截 popup，造成空等。
3. 按站点进入真实 OAuth：掘金/知乎从 targetId 差集取新 popup；简书在当前 task tab 打开 `a#weixin` 的官方站内 href；今日头条必须真实点击可见 `span.web-login-confirm-info__checkbox[role="checkbox"]` 中心点，并在点击微信入口前严格确认该节点 `aria-checked === "true"`。它不是原生 `input`，禁止用 `input.checked`、类名或点击结果推断状态；校验失败立即停止。确认后点“其他登录”第 3 项并取新 popup。最终 target 都必须匹配 `open.weixin.qq.com/connect/qrconnect`。
4. **保留原始 OAuth target，禁止关闭后复制 URL 到新 tab。** 微信 OAuth 的 state 与 opener 上下文有关，复制 URL 会让掘金回调报 `error_code: 4 / 参数错误`。popup 用 `Target.attachToTarget({ targetId, flatten: false })` 附着；简书直接使用当前 tab。
5. 在 OAuth target 中只读取 `.js_switchToNormal` 的可见 rect，再连续发送真实 `Input.dispatchMouseEvent`。禁止元素 `.click()`。点击后必须同时确认切换按钮不可见，且 `img.js_qrcode_img` 的 `offsetParent` 存在、可见宽高都不少于 100px；两项缺一即失败。然后在同一 target 抓二维码：

   ```js
   const { mkdir, writeFile } = await import('node:fs/promises')
   const { tmpdir } = await import('node:os')
   const { join } = await import('node:path')
   // 若当前工作区规定了任务产物根目录，优先把 qrDir 指向其中的 qr-login/；无规定才用系统临时目录。
   const qrDir = join(tmpdir(), 'vft-kit', 'qr-login')
   await mkdir(qrDir, { recursive: true })
   const imageFile = join(qrDir, '<平台>-qr.jpg')
   // sendPopup(method, params) 封装 Target.sendMessageToTarget，并按 id 等待
   // Target.receivedMessageFromTarget；不要改用当前 tab 的 js()。
   const result = await sendPopup('Runtime.evaluate', { awaitPromise: true, returnByValue: true, expression: String.raw`(async () => {
     const visibleQr = el => {
       const r = el.getBoundingClientRect()
       return el.offsetParent && r.width >= 100 && r.height >= 100 && /connect\/qrcode/.test(el.currentSrc || el.src)
     }
     const img = [...document.querySelectorAll('img.js_qrcode_img')].find(visibleQr) || [...document.images].find(visibleQr)
     const src = img?.currentSrc || img?.src
     if (!src) throw new Error('找不到微信二维码')
     const response = await fetch(src, { credentials: 'include' })
     if (!response.ok) throw new Error('二维码请求失败: ' + response.status)
     const bytes = new Uint8Array(await response.arrayBuffer())
     let binary = ''
     for (const byte of bytes) binary += String.fromCharCode(byte)
     return btoa(binary)
   })()` })
   const b64 = result.result.value
   await writeFile(imageFile, Buffer.from(b64, 'base64'))
   ```

   不要输出二维码内容、OAuth URL 或图床链接。个别站点二维码是 canvas 且被污染时，用 `cdp('Page.captureScreenshot', { clip })` 按元素 rect 截区域图兜底。
6. 推送前先在当前对话说明三项：正在执行的动作、操作对象、扫码后的实际效果（例：「扫码后登录掘金账号，不会发布任何内容」），格式 `正在执行：{action}；对象：{subject}；扫码后：{effect}`。然后调用本 skill 的脚本（secrets 由调用方按供给桥注入 env，见下）：

   ```bash
   python3 "<本 SKILL.md 所在目录的绝对路径>/scripts/notify-qr.py" \
     --image-file "<本地二维码绝对路径>" --action '登录' --subject '掘金'
   ```

   脚本要求 `PUSHPLUS_TOKEN` 环境变量；缺失时不上传公网，改为把本地二维码作为当前对话附件交给用户。只有输出同时含 `upload: ok` 与 PushPlus `code: 200` 才算交付成功；`ntfy` 字段 `ok/failed/skipped` 为附加提醒，failed 只报告不阻塞。
7. 告诉用户按平台提示使用微信或对应 App 扫码/确认后停止浏览器操作，不轮询，也不 `handOffTaskSpace`（用户无需碰浏览器窗口）。用户回复「继续」后复用同一 task space；只有用户明确要求在浏览器内接管时才 handoff。
8. 验证成功：用户回复后直接重新接管同一 task space。OAuth 分支检查原 target 已离开微信域名并跳到平台回调，再刷新首页按矩阵复核登录态；站内二维码分支按各自章节复核。二维码过期时从平台登录页重新取得新 state，不能刷新或复制旧 OAuth URL。
9. 结束删除 `imageFile`，`completeTaskSpace(task.id, { keep: false })`。

## SegmentFault 微信 OAuth iframe 分支

1. 打开 `https://segmentfault.com/user/login`，真实点击 `button.login-mode[data-mode="weixin"]`；等待 `#weixinQrCode iframe` 可见。它不会创建 page popup，而会创建 URL 为 `open.weixin.qq.com/connect/qrconnect`、type 为 `iframe` 的 OOPIF target。
2. 通过 `Target.attachToTarget({ targetId, flatten: false })` 附着该 iframe。微信记忆账号时，iframe 内可见 `.js_switchToNormal` 位于内部 y≈160，但站点 iframe 默认只有 160px 高，会把按钮裁掉。先把父页 iframe、`#weixinQrCode` 和最近的 `.qrCode` 高度临时扩至 204px，再把 iframe 内按钮中心按父 iframe rect 映射到根页面坐标，用 ego 真实鼠标点击。
3. 切换可能延迟数秒；最多等待 5 秒，必须确认所有可见 `.js_switchToNormal` 消失，并且 iframe 内可见 `img.js_qrcode_img` 宽高不少于 100px。页面含多个隐藏同名节点，禁止用 `querySelector` 单节点判断。
4. 从父页读取 iframe rect，仅截取顶部 160×160 二维码区域。实测 iframe session 内 `fetch(img.currentSrc)` 可能被跨域策略拒绝；失败后直接用父 page target 的 `Page.captureScreenshot({ clip })` 截图，不重复请求。如果出现模糊二维码和刷新图标，说明已过期，重新加载 SegmentFault 登录页生成新 iframe，不能推送过期截图。
5. 用户扫码后验证时，把导航和 DOM 检查拆成两个 heredoc：第一个只接管并 `gotoAndWait('/user/login')`，等待已登录重定向完成；第二个重新选择稳定 tab 后检查。实测在导航完成的同一 heredoc 立即 `js()`，ego 可能因 target 切换瞬间误报用户控制。最终必须同时满足 `/user/login` 跳到首页、登录入口消失、实际 `/u/<账号>` 链接和头像出现；不能只凭 iframe 内容变化判定。

## 站内公众号二维码分支

博客园、51CTO 不走 `open.weixin.qq.com/connect/qrconnect`：

1. 按矩阵真实点击微信入口。博客园会创建站内 popup；51CTO 在当前登录页切换。
2. 等待对应 `<img>` 可见、宽高不少于 100px且完成加载。图片来自跨域 `mp.weixin.qq.com/cgi-bin/showqrcode`，不要依赖页面 `fetch` 或 canvas `toDataURL`。
3. 读取二维码元素 rect，用其 page target 的 `Page.captureScreenshot({ clip })` 截取区域；不要截整个登录页。
4. 博客园推送前必须说明“扫码会关注博客园服务号并登录”；51CTO只说明登录，不能扩大效果。
5. 用户回复后按平台页面跳转、登录入口消失、头像或昵称出现复核；未实扫的平台不得只凭二维码消失宣称成功。

## CSDN 微信小程序码分支

1. 打开 CSDN 首页；若 `a.toolbar-btn-loginfun` 已不可见且头像/昵称可见，直接报告已登录。否则真实点击登录按钮，等待 `#passportbox iframe[name="passport_iframe"]`。
2. 读取 iframe 的官方 `src`，在同一 task space 自有 tab 打开；最终页应为 `https://passport.csdn.net/login?code=applets`。点击文案为“微信登录”的 `.login-box-tabs-items span`，确认其含 `tabs-active`。
3. 等待 `.login-code-wechat .public-code img` 同时满足 `complete`、`naturalWidth > 0`、`currentSrc.startsWith('data:image/jpeg;base64,')`；不要用容器的 `loading` class 判定，它在二维码已出现时仍可能保留。
4. 从 `currentSrc` 取逗号后的 base64，直接解码写 JPEG；图片原始尺寸 280×280。若跨域 iframe 无法读取，才按可见 rect 用 CDP 区域截图兜底：

   ```js
   const dataUri = await js(`(() => {
     const img = document.querySelector('.login-code-wechat .public-code img')
     if (!img?.complete || !img.naturalWidth || !img.currentSrc.startsWith('data:image/jpeg;base64,')) {
       throw new Error('CSDN 微信小程序码尚未就绪')
     }
     return img.currentSrc
   })()`)
   await writeFile(imageFile, Buffer.from(dataUri.slice(dataUri.indexOf(',') + 1), 'base64'))
   ```
5. 推送前说明“扫码后通过 CSDN 微信小程序登录或注册 CSDN”；这不是开放平台二维码，不要等待 `open.weixin.qq.com` target。
6. 用户回复后回到原 CSDN 页刷新：登录 iframe/遮罩关闭、`a.toolbar-btn-loginfun` 消失、顶部出现实际头像或昵称，三项满足才算成功。

## 小红书站内二维码分支

先按用户目标选择分支，两套登录态不互相证明：主站已登录仍可能被创作平台以 `redirectReason=401` 拒绝。

### 主站

1. 复用 `qr-login-xiaohongshu` task space，打开 `https://www.xiaohongshu.com/explore`，先按第 5 项检查已有登录态，成立就直接报告已登录。未登录时登录弹窗通常自动出现；若已关闭，读取可见 `button#login-btn.login-btn` 中心点并用 ego 真实鼠标点击重开。
2. 等待 `.login-modal.reds-modal-open img.qrcode-img` 同时满足 `complete`、`naturalWidth >= 100`、可见宽高均不少于 100px、`currentSrc.startsWith('data:image/png;base64,')`，并严格确认 `window.__INITIAL_STATE__.login.qrData.status === 'un_scanned'`。它是小红书站内码，无 popup、iframe 或 `open.weixin.qq.com` target。
3. 从 `currentSrc` 取逗号后的 base64 直接解码写 PNG；不要输出二维码内容。推送前说明“小红书 App 或微信均可扫码，扫码后登录小红书主站账号，不会发布内容”。
4. 页面通过 `/api/sns/web/v1/login/qrcode/create` 创建二维码并轮询 `/api/qrcode/userinfo`；`un_scanned` 表示等待扫码，`invalid` 表示过期。过期后重新打开登录弹窗取得新码，不推送旧 data URI。
5. 用户回复后复用同一 task space，刷新首页并同时确认 `window.__INITIAL_STATE__.user.loggedIn.value === true`、`user.userInfo.value` 非空、`.login-modal.reds-modal-open` 消失、可见 `button#login-btn` 消失、`li.user.side-bar-component a.link-wrapper` 中可见文案“我”出现；五项满足才报告完整登录成功。刷新后 `login.qrData.status` 可能重新变成 `un_scanned`，不得用它推翻已成立的页面登录态。

### 创作服务平台

1. 在同一 `qr-login-xiaohongshu` task space 打开用户要访问的创作页。若跳到 `creator.xiaohongshu.com/login?...redirectReason=401`，不要停在短信验证码：查找登录卡内可见、`cursor: pointer`、显示尺寸 64×64 的 `<img>`，取中心点用 ego 真实鼠标点击。不要依赖构建生成的 CSS 类名。
2. 必须回读到文案“APP扫一扫登录”，再选择可见宽高均不少于 150px、`naturalWidth >= 100`、`currentSrc.startsWith('data:image/png;base64,')` 的二维码 `<img>`。从 data URI 解码写 PNG；64×64 的模式图标不是二维码，禁止误抓。
3. 推送前说明“请用小红书 App 扫码；扫码后登录小红书创作服务平台，不会发布内容”。页面出现过期提示或大图消失时，重新加载创作页并重新切换扫码模式，不推送旧码。
4. 用户回复后复用同一 task space，重新打开原创作页；必须确认 URL 不在 `/login`、未再次出现 `redirectReason=401`，且目标编辑器或创作后台可访问，才报告创作平台登录成功。主站五项登录态不能替代这项验证。

未实扫的分支只能写“二维码确认”。

## 少数派微信 OAuth 分支

1. 复用 `qr-login-sspai` task space，从 `https://sspai.com/write` 开始；未登录时页面会跳到 `/login`。先检查登录态，不能把写作页跳转本身当作失败。
2. 在 `/login` 读取可见 `.ssCommunityIcon__weixin` 中心点并用 ego 真实鼠标点击；不要调用 DOM `.click()`。该入口在当前 tab 导航到官方 `open.weixin.qq.com/connect/qrconnect`，不创建 popup，必须保留原始 OAuth target 和 state。
3. 在原 OAuth target 中按通用规则真实点击可见 `.js_switchToNormal`；确认该按钮消失后，等待可见且已加载的 `img.js_qrcode_img.web_qrcode_img`（宽高均不少于 100px，`currentSrc` 匹配 `open.weixin.qq.com/connect/qrcode`），从图片响应抓取二维码，不输出 OAuth URL 或二维码内容。
4. 推送前说明“扫码后登录少数派账号，不会发布文章”。二维码过期时从 `https://sspai.com/write` 重新进入登录并取得新 state，不能刷新或复制旧 OAuth URL。
5. 用户回复后复用同一 task space，等待原 tab 离开微信域名并回调到 `sspai.com/callback/weixin`，再回到 `https://sspai.com/write` 复核：登录入口消失、账号信息/头像出现且写作编辑器可访问；三项满足才报告完整登录成功。

## notify-qr.py 的 env 供给桥

脚本本身不读任何密钥文件；调用方负责 export：

| 环境变量 | 含义 | 默认 |
|---|---|---|
| `PUSHPLUS_TOKEN` | PushPlus 消息 token（必需） | 无 |
| `PUSHPLUS_TOPIC` | 群组编码 | `me` |
| `PUSHPLUS_SEND_URL` | 发送接口 | `https://www.pushplus.plus/send` |
| `BEEIMG_TOKEN` / `BEEIMG_UPLOAD_URL` / `BEEIMG_STORAGE_ID` | 主图床 | 无 token 时回退 Uguu |
| `UGUU_UPLOAD_URL` | 匿名兜底图床 | `https://uguu.se/upload` |
| `NTFY_BASE_URL` / `NTFY_TOPIC` / `NTFY_TOKEN` / `NTFY_ALLOW_SHORT_TOPIC` | 附加提醒，可全缺 | 缺则 skipped |

`--title-prefix 公众号` 可复用公众号流程的标题格式。调用方负责从自己的凭据存储导出这些 env；公共脚本不读取仓库内的凭据文件。

ntfy 的通用发送、macOS 接收端、自启和订阅看门狗由 `vft-kit:notify` 维护；本 skill 只保留“PushPlus 成功后发送二维码附件、ntfy 失败不阻塞”的扫码业务语义。
