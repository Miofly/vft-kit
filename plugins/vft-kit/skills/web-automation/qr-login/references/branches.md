# 各平台取码分支

## 今日头条 App 二维码分支

1. 打开首页并真实点击 `.toutiao-header .header-right a.login-button`，等待 `.web-login-union__login__scan-code` 可见。不要勾协议、不要点击“微信登录”；目标就是弹窗默认展示的头条 App 码。
2. 在该容器内同时确认标题文本为“扫码登录”、说明含“今日头条App”，`img.web-login-scan-code__content__qrcode-wrapper__qrcode` 可见宽高都不少于 100px，且 `.web-login-scan-code__content__qrcode-wrapper__mask` 不可见。若遮罩显示“点击刷新”，必须点击刷新并等待二维码源变化；不发送空白、旧码或刷新遮罩状态。
3. 用 `Page.captureScreenshot` 按 `.web-login-union__login__scan-code` 的可见 rect 截取完整卡片并写入 `imageFile`。必须包含“扫码登录”标题、二维码和“请使用今日头条App扫码登录”说明；禁止只下载或截取内部 `img`。
4. 回到主流程第 6 步推送。用户扫码确认后复用原 task space，刷新首页；顶部 `a.login-button` 和侧栏“立即登录”入口消失、已登录头像/账号入口可见才算成功。

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
