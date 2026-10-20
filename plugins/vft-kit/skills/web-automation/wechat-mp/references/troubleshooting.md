# 常见报错对照

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

上表「上文」指 [publish-article.md](publish-article.md) 的「从草稿箱走发表流程」。
