# 微信公众平台后台（mp.weixin.qq.com）

## 会话与账号

- 首页 `/cgi-bin/home?t=home/index&token=<tk>&lang=zh_CN`。`token` 每次登录都变，**从当前 URL 现取**：`(await pageInfo()).url.match(/token=(\d+)/)[1]`。
- 当前登录的公众号名在 `.weui-desktop-account__info`（右上角也有）。一个微信号下常挂多个公众号 + 小程序，动手写内容前先确认账号对不对。
- 后台会弹「未授权使用切换账号能力」的提示：那是切号需要在扫码登录时勾选授权项，不影响当前号的操作，忽略即可。
- 需要用户扫码时用 `handOffTaskSpace(id)` 交还控制权并说清楚三步：微信快捷登录 → 微信客户端点「允许」→ 在账号列表里选目标公众号。

## 页面清单

| 功能 | 路径（补 `&token=<tk>&lang=zh_CN`） |
|---|---|
| 草稿箱 | `/cgi-bin/appmsg?begin=0&count=10&type=77&action=list_card` |
| 新建图文编辑器 | `/cgi-bin/appmsg?t=media/appmsg_edit_v2&action=edit&isNew=1&type=77&createType=0` |
| 编辑已有草稿 | `/cgi-bin/appmsg?t=media/appmsg_edit&action=edit&type=77&appmsgid=<id>` |
| 素材库（图片） | `/cgi-bin/filepage?type=2&begin=0&count=12` |
| 发表记录 | `/cgi-bin/appmsgpublish?sub=list&begin=0&count=10` |
| 原创管理 | `/cgi-bin/appmsgcopyright?action=orignal&type=1` |
| 合集 | `/cgi-bin/appmsgalbummgr?action=list` |
| 私信 | `/cgi-bin/message?t=message/list&count=20&day=7` |
| 用户管理 | `/cgi-bin/contactmanage?t=user/index&pageidx=0&type=0` |
| 投票 | `/cgi-bin/newoperatevote?action=list` |
| 违规记录 | `/cgi-bin/illegalrecord?count=10` |
| 账号设置 | `/cgi-bin/settingpage?t=setting/index&action=index` |
| 人员设置 | `/cgi-bin/safecenterstatus?action=admins&t=setting/safe-admins` |
| 开发接口管理（已迁移，只剩公告） | `/cgi-bin/frame?t=pages/developsetting/page/developsetting_frame&nav=10141` |

列表类页面用 `begin` / `count` 翻页，直接改 URL 比点分页器稳。

## 图文编辑器 DOM

编辑器是 ProseMirror（新版 `appmsg_edit_v2`，不是老的 UEditor iframe）：

| 目标 | 定位方式 |
|---|---|
| 标题 | `.ProseMirror`，父元素 class 含 `title-editor__input`（另有一个隐藏的 `#title` input，别用） |
| 正文 | `.ProseMirror`，父元素 class 含 `rich_media_content` |
| 作者 | `#author`（普通 input，赋值后要 `dispatchEvent(new Event('input', { bubbles: true }))`） |
| 底部按钮 | 文本匹配 `发表` / `预览` / `保存为草稿` |

写入规则：

- **标题**用 `document.execCommand('insertText', false, title)`（先 `focus()`）。
- **正文**用合成 paste 事件喂 `text/html`，ProseMirror 会解析成公众号的 `<span leaf>` 结构，`h2` / `strong` / 列表 / 表格都能保住。直接改 `innerHTML` 会被 PM 的 state 覆盖，白写。
- 粘贴是**追加**语义。`selectAll + delete` 再粘不可靠（试过会残留、也会叠加），正确做法是每次开一张 `isNew=1` 的新编辑器页。
- 编辑器初始化要几秒，`await wait(7)` 之后再取 `.ProseMirror`；页面上应当**恰好两个** PM 节点（标题 + 正文），少于两个就是还没好。
- 保存成功的判据：URL 变成 `action=edit` 且带 `appmsgid=<数字>`；草稿箱列表首条出现该标题。
- 新功能介绍弹窗（如「支持添加话题卡片」）会盖住底部按钮，点按钮前先关：`.weui-desktop-dialog__close-btn` 或文本含「我知道了」的按钮。

## 排版

正文 HTML 必须自带 inline style——公众号不加载外部 CSS，也会丢掉 class。用 `scripts/md-to-mp-html.mjs` 转，别手写。

链接：非 `mp.weixin.qq.com` 域名的 `<a href>` 会被公众号剥掉，转换脚本已经把这类链接降级成「文字（URL）」的形式，读者至少能复制。想让外链可点只有两条路：放到「阅读原文」，或走已认证账号的图文内跳转能力。

## 发表相关的红线

- `发表` 是不可逆的对外动作，且未认证账号群发次数有限。**没有用户明确指令就停在草稿**，把草稿链接交给用户。
- 通过 API 发文章（`draft/add` → `freepublish/submit`）需要账号已认证，未认证个人号在开发者平台的「发布能力」分类里全部显示无权限——这时候后台编辑器写草稿是唯一可行路径。
- 素材上传（封面图）在编辑器内完成，或走素材库页；文章要正式发表必须有封面。
