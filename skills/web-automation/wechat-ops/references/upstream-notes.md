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

2026-11-20 核对上游正式版 v1.19.31 与主分支 README：仍只承诺 4.1.9 build 268596 / 268602，本机 4.2.0 build 270390 未获该版本的兼容承诺。本机同日试登 4.1.9 副本时提示「版本过低」。授权与版本都需通过；只拿到激活码不能解除版本阻塞，不让用户重复扫码碰运气。独立实现另行寻找能在当前副本运行的授权数据源和发送通道；窗口快照不能作为这两项的验收。

本机已将腾讯官方安装包下载到隔离目录，核对 SHA-256，随后只读挂载核实版本 4.1.9、build 268602、bundle ID `com.tencent.xinWeChat`，应用严格签名校验通过。镜像已卸载，未安装或启动专用副本。下载验签通过不等于专用副本已部署或官方订阅已激活。

## 本 skill 的定位

当前实现是公开 HTTP 路由的适配层：`upstream` 可转发本机已配置后端的 SSE 和精确图片引用，`noop` 没有消息源；真实发送和查询依赖实际后端。本机通过签名核验的 v1.19.29 CLI 实测指出「尚未激活订阅」，`sessions`、`contacts`、`unread` 返回退出码 2；`doctor` 退出码 0 但 `query_ready`、`send_ready` 和 `submission_ready` 均为 false。`upstream-adapter` 接入经发布包哈希、组件哈希及签名核验的官方伴随程序。Hermes 在本地鉴权成功后仍返回 `missing_activation`；只读 MCP 可握手列出 9 个工具，但业务查询缺 daemon；Wechaty 缺 `~/.wx-rs` 父目录时原版报 `upload root unavailable`。在隔离 HOME 仅建立父目录后网关正常启动；REST `/health` 返回 200，四个只读业务入口正确鉴权后返回 `402 subscription_required`，gRPC `Version` 报 `missing activation`。集成入口现在先检查父目录再开监听。未为测试改动上游安装或账户状态。不能把握手、鉴权或桥接模拟通过当成微信业务验收。

目标是独立实现上游公开行为，不要求安装、激活或调用上游程序。上游兼容入口单独保留原有授权和 build 前置条件，不计入独立实现。ADB 与手机不是架构、开发或桌面验收的依赖；若没有独立收端证据，只把对应回执报告为已提交或未知，不把手机验收当成全项目阻塞。

## 核心分层与独立复刻切入点

证据分两层：本地公开仓库快照 `ba23524`（v1.19.22）的能力表、变更记录与 Node SDK 源码说明公开行为；v1.19.29 验签发布包的清单和静态字符串核对组件边界。后者不是运行时跟踪，不能据此还原完整函数调用链，也不能假定两个版本的内部实现完全相同。

| 层 | 有证据的行为 | 独立实现的判据 |
|---|---|---|
| 后台提交 | 公开资料表明发送由原生执行路径处理，而不是通过 HTTP 直接向腾讯发消息。发布包拆出 `wechat-native-owner`，其中可见 `request_identity`、`submitted_unconfirmed` 和 `status_unknown`。Node SDK 对网络失败、成功响应无法解析分别报告 `AmbiguousSendError`，不重发。 | 执行器只作用于明确目标；先持久登记，再单次提交，未知只查回执。桌面证据和送达证据分开。现有 `desktop` 有这条状态链，但提交能力仍限文件助手。 |
| 结构化读取 | 文档说明 `wechatd` 持有账号绑定的私有快照和读取租约；历史/搜索跨分片合并、按时间排序。发布包将 `wechat-snapshot-validator` 单列，`wechatd` 可见快照校验协议和分片可用性标记。公开资料不能证明具体采集实现。 | 先区分已验证、部分和不可用，不把不可用当空结果。独立查询核心只消费合法导入或受支持接口提供的数据；联系人、群、历史和未读分开声明字段来源。现有 AX 快照不能提供这些完整数据。 |
| 实时接收 | 公开变更记录说明先建立历史基线，再用游标补读同秒消息、迟到写入与新分片；SSE 是输出形式，不是采集机制。SDK 默认从当前时间订阅、过滤 `fromSelf:true`。v1.19.29 bridge 中也可见 `/messages/stream`、`fromSelf` 和 `mentionedIds`。 | 先用有明确消息身份的授权输入验证基线、持久游标、重复和续接。原始输入没有消息 ID、发送者或未读状态时不得推造；窗口变化不能冒充实时新消息。现有 SSE 转发不算独立事件源。 |
| 媒体与接入 | 公开图像接口用会话与精确消息引用校验缓存/内容；相同「图片」标签不是同一条消息。HTTP、MCP、Wechaty 是不同适配入口，组件存在不证明业务通过。 | 原图/文件必须绑定到具体消息并核验字节；各入口共享一个结构化数据和回执契约。上游自身对部分客户端及媒体也有单独限制。 |

优先补结构化读取和事件核心，而不是增建接口外壳。验收数据至少包含跨分片同秒消息、迟到消息、同名联系人、不可用分片、重复导入及断线恢复。先用受控数据验证机制；只有授权的桌面数据源真实接通，才将全库、未读和实时流标为业务通过。逐项范围见 [capability-scope.md](capability-scope.md)。

### 双工具取证实测

同一 v1.19.29 发布包离线取证：Craft Anything CLI 0.3.0 `triage` 将 `wechatd` 识别为 arm64 Mach-O，Rust 为推断（`Craft:ev_7deedc63a828b07831b4aa32d223a3544d36afe50dae985a50eaae6f817b4aac`）；REA 6.8.0 `inspect-artifact` 对 `wechat-snapshot-validator` 返回 Mach-O 静态证据（`REA:ev_2ac29577194a1af0be9b56984e0db1acb6564a71736988496f70a790202a60b8`）。随后 REA 复核同一 SHA-256 的 `wechatd`，确认 Mach-O（`REA:ev_e43789b8ac140f3994e9044b98d36c0c3c6f9430bcfae1b9ed836848213f16ec`）。一致范围只到组件格式，不是同一函数的双引擎交叉核验，不证明已拿到源码或快照采集调用链。

固定 v1.19.29 公开标签 `fcbe215d85645c121335b4a9f14e96324e9a9232` 已独立检出：131 个受跟踪文件，包含 7 个 Node SDK 文件，不含 `.rs` 源文件或 `Cargo.toml`。发布清单中的构建提交与公开标签提交不同，不把公开标签当成原生构建源码。REA 6.8.0 与 Craft 0.3.0 都静态分析了该标签下的 `sdk/node`（`REA:ev_1baa209af72b434dda939950e8517c47c61b72c668f1fa807b93a85e77e7256a`、`Craft:ev_6bcf98dff01265e72c1aa601097320ab7fd9c933f40e6d72eb047a09579e571f`）。Craft 报告部分覆盖（检查 5/7 个文件、4 个源码模块）；9 项公开 SDK 契约测试通过。源码核对确认该版本客户端识别 `fromSelf` 与 `sender_is_self` 两种自发标记，并逐条处理 `{meta, rows:[...]}` 批次。旧桥只看事件外层，混合批次会漏过自发消息。现有兼容桥逐条过滤，保留批次元数据及 SSE 事件 ID；全为自发消息时保留空 `rows`，不把它解释成收到消息。回环回归覆盖混合批次、全过滤、`includeSelf=true` 原帧和异常批次，不算微信实时接收。独立归档按导入的 `from_self` 字段过滤，未获得微信实时数据。该轮不重建未公开的原生读写调用链。

## 研究产物位置

克隆与 SDK 二进制在 `other/temp/research/wechat-use-study/`，AX 探测源码在 `other/temp/research/wechat-ax-probe/`。**均不进 vft-kit**。
