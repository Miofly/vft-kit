# wechat-use 技术研究（2026-11-10）

研究对象：`https://github.com/leeguooooo/wechat-use`，v1.19.22（release tag）。记录公开文档、SDK 契约，以及二进制内嵌源码 + `strings` 观察。

## 发布形态

- 仓库内容：`SKILL.md`、`install.sh`（79 KB）、`docs/`、SDK 的 `bridge.mjs` / `bridge.d.ts` / 测试、`examples/`、安装与发版脚本。
- **发送实现不在仓库里**。GitHub Release 提供预编译 Mach-O arm64 二进制：`wechat` / `wechatd` / `wechat-bridge` / `wechat-mcp` / `wechat-send-mcp` / `wechat-wechaty-gateway` / `wechat-native-owner` / `wechat-snapshot-validator`，加 `wechat-setup-service` 与 `WechatUseSetup.app`。
- 整包 `wechat-v1.19.22-darwin-arm64.tar.gz` 40,760,430 字节，SHA-256 `9a5af70c764a13f3a0cb79c6be7f5f5830238c36889242c47e747f9ab4a686aa`（本次下载校验通过）。
- 版本适配数据由服务端按 `sdk_abi=wechat-use/native-context/v1` 下发（`target_module_sha256`、`module_size`），不随 release 附带。

## 后台发送机制（反编译二进制内嵌源码后确认）

发送 = 在微信进程内通过 LLDB 表达式求值（后改 `mach_vm_write` 免附着）调用 **Qt 私有接口 `QMetaObject` 的 `qt_metacall`**，纯进程内对象调用：

```
wx_context_ok()      // INPUT/EDITOR 的 vtable 匹配且 *(INPUT+offset) 的 QString == 目标 peer
wx_text_meta(EDITOR, 1, 9, &before)               // 读草稿(PropertyAccess, index 9)，要求为空
wx_text_meta(EDITOR, 0, 16, {nullptr, &desired})  // setText(InvokeMetaMethod, index 16)
wx_text_meta(EDITOR, 1, 9, &actual)               // 回读校验一致
INPUT_META(INPUT, 0, 5, {nullptr, &send_action})  // 触发发送
```

- 执行体不是 shell/AX，是二进制内嵌 Python 拼出的 C++ 表达式模板（`wechat-native-owner` 内嵌，偏移 ~173915）；`TEXT_META`=`base+qtextedit_metacall_rva`，`INPUT_META`=`base+inputview_metacall_rva`。
- 协议标识：`wechat-public-native-send/v1`（schema `wechat-use/public-send-worker/v1`），操作 `send_text` / `send_image` / `send_file`。
- 对象定位：输入视图 `INPUT`（服务端 `identities.input.rva`）`+0x1f8` = `QTextEdit*` EDITOR，`+0x2b0` = recipient `QString`。
- 版本适配 = 一组 RVA：`qtextedit_metacall_rva / inputview_metacall_rva / editor_vtable_rva / message_vtable_rva / qstring_from_utf8_rva / qarray_deallocate_rva / editor_offset / send_action`，按 `target_module_sha256`+`module_size` 校验、服务端下发、逐 build 变。
- 关键**不是** `Contents/Resources/wechat.dylib`——那是微信自带的 306 MB 核心 dylib（本机 4.1.10 实测），只被用来扫 `sqlite3_key` memcpy 点取库密钥。真正注入的是 `@executable_path/../Resources/wechat-use-customizations.dylib`（schema `wechat-managed-customizations/v1`），只管图标/伪装，不含发送。
- 读路径用 `task_for_pid` / `mach_vm_read_overwrite`；发送路径早期用 `/usr/bin/lldb` + `debugserver` 附着，后改 `mach_vm_write` 免附着。
- 绑定微信 4.1.9 build 268596 / 268602；发送状态分级 `delivered` / `submitted_unconfirmed` / `status_unknown` / `failed`，`send-receipt` 用 `request_id` 核对原请求，不重发。
- 发**任意**联系人需先"导航"到该会话：模板显式校验当前打开的聊天 == 目标，注释 `A mismatch requires the separate signed navigation/provider path.`——第二条独立机制。

结论：既不是 `AXUIElement` 写输入框，也不是 `CGEventPostToPid` 模拟键盘；是进程内 Qt 元调用。复刻需要反汇编微信自身的 `wechat.dylib` 算出上述 RVA（本机符号表已剥光，仅剩 Qt moc 元数据串可作线索）。详细报告见 `other/temp/research/wechat-use-study/REA-findings-send.md`（未进仓库）。

## 本机实测（微信 4.1.10）

- 进程 `80788`，窗口 `13232`。cua-driver 读到完整会话列表（文件传输助手、多个群），但所有元素 `actions=[raise]`，**0 个可 `press` 的输入控件**。
- Swift `AXUIElement` 探测：`trusted=true`，`AXWindows` 在两次探测中分别返回 0 和 1 个窗口，`AXIsAttributeSettable(kAXValueAttribute)` 可写元素 **0 个**。
- 归档项目 `ginqi7/macos-wechat-cli` 记录：`WeChat 4.x does not support the Accessibility API required by this tool`，仅支持 3.8。
- 渲染层是 `WeChatAppEx` / WMPF / radium（`pgrep` 可见多个 helper 进程），这解释了定向事件与 AX 树的不稳定。

## HTTP bridge 契约（公开文档 + SDK）

默认 `127.0.0.1:18400`，可选 `WECHAT_BRIDGE_BEARER`，`/health` 恒公开。

| 方法 | 路径 |
|---|---|
| GET | `/health` `/chats?limit=N` `/unread` `/contacts?query=X&limit=N` `/resolve?hint=X&limit=N` |
| GET | `/chat/{wxid}` `/chat/{wxid}/history?since=&until=&limit=` |
| GET | `/messages/stream?since=<epoch>`（SSE；`since=0` 会 backfill 全历史） |
| POST | `/send` `{wxid,text,mention?}` → `{status,diagnostic,...}` |
| POST | `/typing`（仅 hermes shape） |

SDK `bridge.mjs` 的关键约束：网络异常或成功响应不可解码时抛 `AmbiguousSendError`，**不自动重试**，避免重复发送。本 skill 的 `send` 子命令与 502 分支照此实现。

`bridge.d.ts` 暴露 `WechatUseBridgeClient.sendText(wxid, text, {mention, signal})` 与 `streamMessages({since, includeSelf})`；SSE 默认过滤 `fromSelf:true`。

## 使用上游的前置条件

1. 微信 macOS 4.1.9 独立副本（`WeChatMac_4.1.9.dmg`，SHA-256 `0e8510d1a004fe6373aa0ad1806d73d4bcf9a32f0c62284d8eb82cefe2b78d06`），单独扫码登录，主微信不动。
2. Telegram `@WechatCliBot` 申请激活码，人工审核 1–24h。激活码进 macOS Keychain（service `wechat-use-profile-api`），bridge 每次 `/send` 校验 `expires_at`。
3. `wechat-use setup` 完成系统组件与授权；`doctor` 检查 `submission_ready` / `send_ready` / `send_delivery_verified`。
4. 仅 macOS arm64；群发 / 定时不在能力表内。

## 本 skill 的定位

只实现上述公开 HTTP 协议的独立互操作（`/health` `/resolve` `/chats` `/contacts` `/unread` `/chat/{wxid}` `/chat/{wxid}/history` `/messages/stream` `/send` + `/receipt`），零依赖标准库、只绑 loopback。注入、dylib、激活、版本适配均不在本层；真实发送由 `exec` 后端接自备发送器，或由 `upstream` 后端交给已运行的上游 bridge。

## 研究产物位置

克隆与 SDK 二进制在 `other/temp/research/wechat-use-study/`，AX 探测源码在 `other/temp/research/wechat-ax-probe/`。**均不进 vft-kit**。
