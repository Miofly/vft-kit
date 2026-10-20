# 发一篇文章：草稿、封面、发表

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

### 图片只走本地上传（不给编辑器外链图）

正文贴外链 `<img>` 编辑器会自己转存成 mmbiz，但用户要求像人一样传本地文件（2026-10-14 实测）：

- 正文插图：光标放到正文末尾 → 点工具栏 `#js_editor_insertimage` → 菜单 `li.js_img_from_local`（文字是「从图片库选择」）→ 对话框里 `.js_upload_btn_container input[type=file]` 选文件（ego 用 `waitForFileChooser` 点「上传文件」，Selenium 直接 `sendKeys` 路径）→ 上传完自动选中，计数变成 `1 / 100 项` → 点「确定」，图插在光标处。
- 封面：先悬停再点 `.js_cover_btn_area` → 弹出菜单在 `.pop-opr__group-select-cover` 里（不在封面区内，靠 `visibility` 显隐）→ 点其中的 `.js_imagedialog` → 同一个图片库上传 → 封面对话框没有计数，上传后「下一步」由灰变可点 → 「下一步」→ 裁剪页「确认」→ `.js_cover_preview_new` 背景图含 `mmbiz` 即成功。
- 多篇：悬停 `.preview_media_add_word`（「新建内容」）→ 点 `li.js_create_article`（「写新文章」），`.js_appmsg_item` 数加一。摘要 `#js_description`，作者 `#author`。
- 草稿保存后历史版本来源显示「网页版 / 手动保存」。

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
