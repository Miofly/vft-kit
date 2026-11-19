# 个人微信主动发消息：第三方方案选型

依据公开文档和脚本，未安装、未真发；以下不是本机兼容性验收。

- **现有 Mac 微信、接受短暂切窗时，优先验证 [BiboyQG/WeChat-MCP](https://github.com/BiboyQG/WeChat-MCP)。** [工具文档](https://github.com/BiboyQG/WeChat-MCP/blob/master/docs/detailed-guide.md)列出 `reply_to_messages_by_chat(chat_name, reply_message)`：打开指定好友或群，传入正文时发送。走 macOS 辅助功能和合成按键；支持按名称精确搜索不等于能消歧同名。当前微信 4.2.x 兼容性、不抢焦点与送达未验证。
- **不直接装 [wechat-macos-proxy](https://github.com/chairmanmiao/wechat-macos-proxy) 发主号。** [导航脚本](https://github.com/chairmanmiao/wechat-macos-proxy/blob/main/scripts/wechat_proxy.sh)聚焦微信，搜索后连按回车选中结果；导航本身没有精确身份确认。可研究界面路径，不照搬盲发。
- **必须完全后台时，[wechat-use](https://github.com/leeguooooo/wechat-use) 文档声明可点名发送。** 限 Apple Silicon 与微信 4.1.9 专用独立副本（build 268596 / 268602），需申请激活码并独立登录；不能算主微信现装现用。
- **腾讯 [openclaw-weixin](https://github.com/Tencent/openclaw-weixin) 是绑定 ClawBot 的频道插件，不是代个人号发给任意好友的接口。** [渠道文档](https://docs.openclaw.ai/zh-CN/channels/wechat)只声明私信能力，未声明群聊支持。不要用机器人会话的出站能力推断能给既有好友主动发消息。

界面路线的验收应分别证明：选中唯一的目标会话，发送侧出现本条正文；只有接收端核验后才称独立确认送达。需要切到前台时先取得许可；重名或结果不明时停止，不盲发、不补发。

## 文件传输助手发图：优先绕开桌面窗口

- **首选验证 [微信文件传输助手网页版](https://filehelper.weixin.qq.com/)**：在后台浏览器复用登录态，通过页面文件输入控件上传，不依赖桌面微信 AX 窗口或系统剪贴板。扫码或登录失效由用户处理。尚未在本机实发或计时。
- **需要 CLI/HTTP 时，可评估 [wx-filehelper-api](https://github.com/CJackHwang/wx-filehelper-api)**：README 提供 `sendPhoto/upload`、`sendDocument/upload` 和扫码登录。它是第三方、非腾讯官方 API，持有网页会话且带历史与下载功能；验证前审查会话存储及监听地址，不直接把主号交给它。仅目标为文件传输助手，不替代好友或群聊发送。
- **必须保留 Mac 客户端时，评估 [wechat-use](https://github.com/leeguooooo/wechat-use/blob/main/docs/capabilities.md)**：v1.19 能力表列出原生 `send --image/--file`，项目说该原生后台路径不依赖辅助功能。仍需专用微信 4.1.9 副本、登录和激活。不能据此保证当前 4.2.0 副本可用，或窗口隐藏时一定可发。

同一批文件、同一目标下分开计量提交、发送侧记录与接收端可打开；比较照片压缩前后内容时，不能拿照片路由冒充原文件传输。
