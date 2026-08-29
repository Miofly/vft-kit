---
name: qr-login
description: 用 ego-lite 在隔离空间完成第三方网站的微信扫码登录，并把二维码经 PushPlus/ntfy 推送给用户。内置掘金、知乎、简书、今日头条、博客园、51CTO 等实测流程，以及 V2EX、阿里云开发者社区、百度百家号等不支持/受阻判定。用户要求登录这些平台、微信扫码登录网站或推送登录二维码时使用。
---

# 第三方平台微信扫码登录

用 ego-lite 打开目标站登录页，点微信登录入口，把 open.weixin.qq.com 的扫码二维码抓下来推送给用户，用户手机扫码确认后接管验证登录结果。

全程在 ego 隔离空间后台完成：不 `open_application`、不激活窗口、不弹桌面通知。微信 OAuth 以 popup target 打开；保留原 target，通过 CDP session 在后台完成切换与抓码，不能关闭后复制 URL。

## 站点矩阵（2026-08-29 实测）

“二维码确认”只表示已真实点击并看到可扫描微信码；只有掘金、知乎完成过用户扫码后的登录态复核。

| 平台 | 结果 | 登录页与微信入口 | 二维码形态 / 限制 |
|---|---|---|---|
| 掘金 juejin | 完整登录确认 | `https://juejin.cn/`；可见 `.login-button` → `.oauth-box .oauth-bg` 第 2 个 | `open.weixin.qq.com` 标准图片；首页 `.login-button` 消失才算成功 |
| 知乎 zhihu | 完整登录确认 | `https://www.zhihu.com/signin`；`.Login-socialButton` 或 `button[class*="socialButton"]` 第 1 个 | `open.weixin.qq.com` 标准图片；访问 `/signin` 自动跳走、头像可见、登录控件消失才算成功 |
| 简书 jianshu | 二维码确认 | `https://www.jianshu.com/sign_in`；`a#weixin.weixin` | `_blank` 在 ego 可能被抑制；改在同 task tab 打开该元素的官方 `href=/users/auth/wechat`，随后进入 `open.weixin.qq.com` |
| CSDN | 受阻，不能下结论 | `https://passport.csdn.net/login` | ego 已有 SSO 会立即回首页；不得为探测退出用户账号。本轮未取得退出态微信入口或二维码 |
| OSChina 开源中国 | 有入口，二维码未确认 | `https://www.oschina.net/home/login`；勾选页面协议后点 `.social-login-buttons > .social-btn:nth-child(1)` | SVG `#icon-wx` 已确认；本轮自动化未稳定进入二维码页，不得声称已支持 |
| 今日头条 | 二维码确认 | `https://www.toutiao.com/`；`a.login-button` → 勾 `.web-login-confirm-info__checkbox` → `.web-login-other-login-method__list__item:nth-child(3)` | 默认码是头条 App；微信入口进入 `open.weixin.qq.com` 标准图片 |
| 博客园 | 二维码确认 | `https://account.cnblogs.com/signin`；`app-external-sign-in-providers .providers button:first-of-type`（子图 `WeChat.png`） | 站内 popup 的 `app-wechat-mp-qr img[alt="微信二维码"]`；图片来自 `mp.weixin.qq.com/cgi-bin/showqrcode`，要求关注服务号 |
| V2EX | 当前不支持 | `https://www.v2ex.com/signin` | `.sign_in_methods .sign_in_with` 只有 Google、Solana，无微信入口或二维码 |
| 阿里云开发者社区 | 当前不支持 | 阿里云账号登录页 | 第三方方式只有支付宝、淘宝、1688、微博、友盟；默认码是阿里云 App/支付宝/钉钉 |
| 51CTO | 二维码确认 | `https://home.51cto.com/index?reback=https%3A%2F%2Fwww.51cto.com%2F`；`.login-type-switch:nth-child(1)` | 站内 `#login-wechat img.qr-img`，图片来自 `mp.weixin.qq.com/cgi-bin/showqrcode` |
| 开发者头条 | 受阻，不能下结论 | `https://toutiao.io/` | 首页及常见登录路径均返回 `Too many requests`，无可测 DOM |
| 百度百家号 | 当前不支持 | `https://baijiahao.baidu.com/builder/theme/bjh/login` | 当前 bundle 明确要求百度 App/百家号 App 扫码，无微信入口或 `open.weixin.qq.com` |

站点自己的默认二维码常常不是微信（掘金/知乎/头条/百家号/阿里云均如此），必须依据矩阵进入微信入口，不能看到二维码就抓。

其他站点先实测登录页、微信入口、二维码类型和成功判定，再套用通用流程；只有用户明确要求维护本 skill 时才把验证结果补进矩阵。

## 主流程

```js
const task = await useOrCreateTaskSpace('qr-login-<平台>')
```

1. 先按矩阵路由：`完整登录确认/二维码确认` 才继续；`当前不支持` 直接报告；`受阻/二维码未确认` 说明实测边界并停止，不能猜选择器或 OAuth URL。内置支持站点用一个 `ego-browser nodejs` heredoc 完成整个浏览器阶段，不逐步探测已记录选择器。
2. `gotoAndWait(<登录页>)` 强制刷新首页；按「登录成功判定」检查。未登录时按站点表打开登录弹窗，记录微信点击前的 `Target.getTargets`。微信入口必须取可见元素中心点后调用 ego `click({ x, y })` 真实鼠标点击；DOM `el.click()` 没有用户激活，Chromium 会拦截 popup，造成空等。
3. 从点击后的 targetId 差集选出 URL 匹配 `open.weixin.qq.com/connect/qrconnect` 的新 page target；`openerId` 存在时再用主页 targetId 交叉校验，但不能依赖它（实测 ego 中可能为 null）。失败重试前只清理由本流程留下的旧 qrconnect popup。找不到就停下，不能猜 OAuth URL。
4. **保留原始 popup，禁止关闭后复制 URL 到新 tab。** 微信 OAuth 的 state 与 opener 上下文有关，复制 URL 会在掘金回调时报 `error_code: 4 / 参数错误`。用 `Target.attachToTarget({ targetId, flatten: false })` 附着 popup，并通过 `Target.sendMessageToTarget` + `Target.receivedMessageFromTarget` 在原 target 执行 CDP 命令。
5. 在 popup 的 `Runtime.evaluate` 中只读取 `.js_switchToNormal`（文案「使用其他头像、昵称或账号」）的可见 rect，再通过同一 session 连续发送 `Input.dispatchMouseEvent` 的 `mouseMoved`、`mousePressed`、`mouseReleased`。禁止调用元素 `.click()`：实测它可能不切视图，却让预置二维码节点通过弱校验。点击后必须同时确认 `.js_switchToNormal` 已不可见，且 `img.js_qrcode_img` 的 `offsetParent` 存在、可见宽高都不少于 100px；两项缺一即失败。然后仍在原 popup 内抓二维码：

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
7. 告诉用户去微信扫码/确认后停止浏览器操作，不轮询，也不 `handOffTaskSpace`（用户无需碰浏览器窗口）。用户回复「继续」后复用同一 task space；只有用户明确要求在浏览器内接管时才 handoff。
8. 验证成功：用户回复后直接重新接管同一 task space，检查原 popup target 是否离开 `open.weixin.qq.com` 并跳到平台回调，再刷新首页按站点表复核登录态；两者都满足才报告成功。二维码过期时刷新平台首页并重新点击登录、微信入口以取得新的 popup/state，不能刷新或复制旧 OAuth URL。
9. 结束删除 `imageFile`，`completeTaskSpace(task.id, { keep: false })`。

## 站内公众号二维码分支

博客园、51CTO 不走 `open.weixin.qq.com/connect/qrconnect`，因此不执行 popup 快捷登录切换：

1. 按矩阵真实点击微信入口，等待对应站内二维码 `<img>` 可见且宽高不少于 100px。
2. 图片来自跨域 `mp.weixin.qq.com/cgi-bin/showqrcode`；不要依赖页面 `fetch` 或 canvas `toDataURL`。读取元素 rect 后用该 page target 的 `Page.captureScreenshot({ clip })` 截取二维码区域。
3. 博客园扫码含“关注服务号”效果，推送前必须在 `effect` 中明确说明；51CTO只描述为登录，不能扩大效果。
4. 用户扫码后按平台页面跳转/头像/登录控件复核；尚未做过真实扫码的平台不得只凭二维码消失宣称成功。

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
