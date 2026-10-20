# 站点矩阵与登录成功判定

## 站点矩阵（2026-08-29 实测）

“二维码确认”只表示已真实点击并看到可扫描二维码；“完整登录确认”表示已经完成用户扫码和站内登录态复核。

| 平台 | 结果 | 登录页与微信入口 | 二维码形态 / 限制 |
|---|---|---|---|
| 掘金 juejin | 完整登录确认 | `https://juejin.cn/`；可见 `.login-button` → `.oauth-box .oauth-bg` 第 2 个 | `open.weixin.qq.com` 标准图片；首页 `.login-button` 消失才算成功 |
| 知乎 zhihu | 完整登录确认 | `https://www.zhihu.com/signin`；`.Login-socialButton` 或 `button[class*="socialButton"]` 第 1 个 | `open.weixin.qq.com` 标准图片；访问 `/signin` 自动跳走、头像可见、登录控件消失才算成功 |
| 简书 jianshu | 完整登录确认 | `https://www.jianshu.com/sign_in`；`a#weixin.weixin` | ego 可能抑制 `_blank`；在同 task tab 打开该元素的官方 `href=/users/auth/wechat`，随后进入标准微信 OAuth |
| 今日头条 | 完整登录确认 | `https://www.toutiao.com/`；`.toutiao-header .header-right a.login-button` | 保留默认头条 App 二维码；确认刷新遮罩隐藏后截取并发送完整 `.web-login-union__login__scan-code` 卡片，不切换微信、不只抓内部二维码图片；使用今日头条 App 扫码 |
| 博客园 | 完整登录确认 | `https://account.cnblogs.com/signin`；`app-external-sign-in-providers .providers button:first-of-type`（子图 `WeChat.png`） | 站内 popup 的 `app-wechat-mp-qr img[alt="微信二维码"]`，扫码会关注博客园服务号并登录 |
| 51CTO | 完整登录确认 | `https://home.51cto.com/index?reback=https%3A%2F%2Fwww.51cto.com%2F`；`.login-type-switch:nth-child(1)` | 站内 `#login-wechat img.qr-img`，图片来自 `mp.weixin.qq.com/cgi-bin/showqrcode` |
| CSDN | 完整登录确认 | `https://www.csdn.net/`；`a.toolbar-btn-loginfun` → iframe `#passportbox iframe[name="passport_iframe"]` → “微信登录” tab | `https://passport.csdn.net/login?code=applets` 内 `.login-code-wechat .public-code img`；280×280 JPEG data URI 微信小程序码 |
| SegmentFault 思否 | 完整登录确认 | `https://segmentfault.com/user/login`；`button.login-mode[data-mode="weixin"]` | `#weixinQrCode iframe` 内嵌标准微信 OAuth；iframe target 类型为 `iframe`、回调 `/user/oauth/weixin` |
| 小红书 xiaohongshu | 主站、创作平台完整登录确认 | 主站 `https://www.xiaohongshu.com/explore`；创作平台 `https://creator.xiaohongshu.com/publish/publish?from=menu&target=article` 被 401 重定向后，真实点击短信登录卡右上角 64×64 模式图标 | 主站 `.login-modal img.qrcode-img`，小红书 App 或微信可扫；创作平台为 160×160 PNG data URI，页面要求小红书 App 扫码 |
| 少数派 sspai | 完整登录确认 | `https://sspai.com/write` → `/login`；`.ssCommunityIcon__weixin` | 当前 tab 进入 `open.weixin.qq.com/connect/qrconnect`；切换后 `img.js_qrcode_img.web_qrcode_img` 160×160 标准图片；扫码后回调 `/callback/weixin` |

掘金、知乎默认码不是微信，必须依据矩阵进入微信入口，不能看到二维码就抓。今日头条例外：保留默认 App 码并发送完整扫码卡片。当前 skill 只支持表中十个平台，其余平台不要自动套用。
