# 个人微信主动发消息：第三方方案选型

依据公开文档和脚本，未安装、未真发；以下不是本机兼容性验收。

- **现有 Mac 微信、接受短暂切窗时，优先验证 [BiboyQG/WeChat-MCP](https://github.com/BiboyQG/WeChat-MCP)。** [工具文档](https://github.com/BiboyQG/WeChat-MCP/blob/master/docs/detailed-guide.md)列出 `reply_to_messages_by_chat(chat_name, reply_message)`：打开指定好友或群，传入正文时发送。走 macOS 辅助功能和合成按键；支持按名称精确搜索不等于能消歧同名。当前微信 4.2.x 兼容性、不抢焦点与送达未验证。
- **不直接装 [wechat-macos-proxy](https://github.com/chairmanmiao/wechat-macos-proxy) 发主号。** [导航脚本](https://github.com/chairmanmiao/wechat-macos-proxy/blob/main/scripts/wechat_proxy.sh)聚焦微信，搜索后连按回车选中结果；导航本身没有精确身份确认。可研究界面路径，不照搬盲发。
- **必须完全后台时，[wechat-use](https://github.com/leeguooooo/wechat-use) 文档声明可点名发送。** 限 Apple Silicon 与微信 4.1.9 专用独立副本（build 268596 / 268602），需申请激活码并独立登录；不能算主微信现装现用。
- **腾讯 [openclaw-weixin](https://github.com/Tencent/openclaw-weixin) 是绑定 ClawBot 的频道插件，不是代个人号发给任意好友的接口。** [渠道文档](https://docs.openclaw.ai/zh-CN/channels/wechat)只声明私信能力，未声明群聊支持。不要用机器人会话的出站能力推断能给既有好友主动发消息。

界面路线的验收应分别证明：选中唯一的目标会话，发送侧出现本条正文；只有接收端核验后才称独立确认送达。需要切到前台时先取得许可；重名或结果不明时停止，不盲发、不补发。

## 文件传输助手发送原文件：按客户端与接收会话筛选

- **必须用主微信时，先验证自带的 macOS 分享扩展，不换客户端。** 本机主微信 4.1.10（268851）内置 `WeChatMacShare.appex`，声明 `com.apple.share-services`，支持文件和视频；未发现 AppleScript 脚本字典。安装包内存在不等于系统会调用该份扩展：`pluginkit -m -A -D -v -i com.tencent.xinWeChat.WeChatMacShare` 本机只列出三个测试副本的扩展路径，未列出主微信的扩展路径。调用前须核验系统实际选中的扩展归属，不按显示名或共用 bundle ID 推断，也不自动改注册。对实际 MP4 调用 AppKit `NSSharingService.sharingServices(forItems:)`，匹配到 0 个微信服务；新版 `standardShareMenuItem` 是打开选择器的菜单项，不提供直接指定微信会话的接口。`WeChatFileProviderExtension` 声明 `com.apple.fileprovider-nonui`，未找到将文件发送到聊天的公开入口。未改注册、未触发分享。离屏选中「文件传输助手」、无界面提交及原文件字节一致均未验证。
- **不抢焦点与窗口离屏是两个条件。** 本机主微信 `isHidden=false`、`isActive=false`，两个窗口都在当前 Space 但均离屏，逐窗返回 `ax_window_unresolved`。不能据此认定是「隐藏应用」或换 Space。界面路线须先取得可绑定的主微信窗口。主窗恢复在屏后，主微信真机验证 `open_filehelper` 能从未打开文件助手的状态后台打开新的独立窗，前台应用未变。若会话行没有令牌，必须用实时 AX 侧栏边界过滤本机 OCR 命中；不要沿用固定截图区域。文件助手内的「发送文件」按钮只有无令牌的标签，后台像素点按后未出现可核验的文件选择器。用可恢复剪贴板粘贴实际 MP4 后，草稿只暴露一个 `U+FFFC`，未读到文件名或可用的发送控件；已撤回并确认草稿为空。不要按占位符数量推断原文件类型或提交。
- **[WeClawSend](https://github.com/double2tea/WeClawSend) 不依赖桌面微信窗口，但接收会话是 ClawBot。** 项目提供 CLI 和本机 HTTP；不替代文件传输助手。HTTP 默认关闭，启用时仅监听回环但无鉴权，不对外暴露；机器人会话过期时可能需要先发消息更新上下文。未在本机安装或实发。

- **首选验证 [微信文件传输助手网页版](https://filehelper.weixin.qq.com/)**：登录后验证文件输入控件，不依赖桌面微信 AX 窗口或系统剪贴板。2026-11-20 本机复验仍停在扫码页，无文件输入或消息编辑控件；桌面副本已登录不代表网页已登录。用独立浏览器任务空间打开官方地址，把扫码交给用户，收到确认后复用同一空间核对登录态和上传控件。未上传、未实发；不能按登录页推断登录后接口或性能。该路线只验文件助手，不作为通用会话采集或实时收发的数据源。
- **需要 CLI/HTTP 时，可评估 [wx-filehelper-api](https://github.com/CJackHwang/wx-filehelper-api)**：README 提供 `sendPhoto/upload`、`sendDocument/upload` 和扫码登录。它是第三方、非腾讯官方 API，持有网页会话且带历史与下载功能；验证前审查会话存储及监听地址，不直接把主号交给它。仅目标为文件传输助手，不替代好友或群聊发送。
- **必须保留 Mac 客户端时，评估 [wechat-use](https://github.com/leeguooooo/wechat-use/blob/main/docs/capabilities.md)**：v1.19 能力表列出原生 `send --image/--file`，项目说该原生后台路径不依赖辅助功能。仍需专用微信 4.1.9 副本、登录和激活。不能据此保证当前 4.2.0 副本可用，或窗口隐藏时一定可发。

同一批文件、同一目标下分开计量提交、发送侧记录与接收端可打开；比较照片压缩前后内容时，不能拿照片路由冒充原文件传输。
