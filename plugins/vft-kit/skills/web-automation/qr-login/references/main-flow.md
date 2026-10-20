# 主流程（逐步细则）

## 主流程

```js
const task = await useOrCreateTaskSpace('qr-login-<平台>')
```

1. 只接受矩阵中的十个平台；用一个 `ego-browser nodejs` heredoc 完成整个浏览器阶段，不逐步探测已记录选择器。SegmentFault 走 OAuth iframe 分支，博客园/51CTO 走公众号二维码分支，CSDN 走小程序码分支，小红书走站内二维码分支，今日头条走 App 二维码分支，其余四站走标准 OAuth 分支。
2. `gotoAndWait(<登录页>)` 强制刷新首页；按「登录成功判定」检查。未登录时按站点表打开登录弹窗。需要微信 OAuth 的站点记录微信点击前的 `Target.getTargets`，并取可见入口中心点后调用 ego `click({ x, y })` 真实鼠标点击；DOM `el.click()` 没有用户激活，Chromium 会拦截 popup，造成空等。今日头条打开弹窗后直接走 App 二维码分支。
3. 标准 OAuth 站点按矩阵进入真实 OAuth：掘金/知乎从 targetId 差集取新 popup；简书在当前 task tab 打开 `a#weixin` 的官方站内 href。最终 target 都必须匹配 `open.weixin.qq.com/connect/qrconnect`。今日头条不执行本步，直接走下方 App 二维码分支。
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
