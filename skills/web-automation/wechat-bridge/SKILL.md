---
name: wechat-bridge
description: "本机微信消息发送桥：与 wechat-use HTTP bridge 兼容的 loopback 服务，支持 /send、/resolve、/chats、/health 与 SSE；后端可插拔（noop 自检 / exec 接任意发送器 / upstream 透传已装 wechat-use）。用于把大模型或定时任务的输出静默发到任意微信联系人或群，不抢前台。仅 macOS，需已登录的微信桌面端。"
---

# 微信发送桥（wechat-bridge）

零依赖 Python 标准库实现，只绑 `127.0.0.1`。**协议兼容** `leeguooooo/wechat-use` 的 HTTP bridge 路由，是独立实现。后端决定「消息怎么真正发出去」。

## 什么时候用

- 大模型 / 定时任务 / CI 要把结果发到微信，且不想弹窗、不想抢焦点。
- 已有 wechat-use 或任意微信发送器，想统一成一套 HTTP 调用契约。
- 想在接真实发送器之前，先把调用方（agent、hook、脚本）调通。

不用：要企业微信机器人 / 公众号 API 这类现成通道；要读聊天记录做分析（本 skill 只做发送契约，读取路由交给后端）。

## 决策：后端选哪个

| 后端 | 环境变量 | 行为 | 何时用 |
|---|---|---|---|
| `noop` | 默认 | 收到 `/send` 只登记、`status_unknown`，**绝不发送** | 调调用方、跑自检、CI |
| `exec` | `WECHAT_BRIDGE_EXEC` 或 `WECHAT_BRIDGE_EXEC_SEND` | 每条操作起一个命令，stdin/stdout 传 JSON | 已有任意发送脚本，接进来 |
| `upstream` | `WECHAT_BRIDGE_UPSTREAM`（默认 `http://127.0.0.1:18400`） | 全路由透传给已运行的 wechat-use bridge | 已装好 wechat-use，要统一入口/加鉴权 |

**关键事实（本机实测 2026-11-10）**：微信 macOS 4.1.10 的辅助功能树没有可写的聊天输入框，AX 窗口数在 0 和 1 之间漂移。纯 `AXUIElement` / `CGEvent` 做不到后台静默发送。上游 wechat-use 的后台发送走的是 `wechat-public-native-send/v1`：在独立微信副本进程内用 LLDB 表达式求值调用 Qt `qt_metacall`（先 setText 写输入框，再触发 send 动作），早期经 `task_for_pid` / `mach_vm_read_overwrite` / LLDB 附着，后改 `mach_vm_write` 免附着；按微信 build 指纹的一组 RVA 适配，绑定 4.1.9 特定 build 与服务端激活码。本 skill 只做协议互操作，注入实现不在这一层；技术细节见 [upstream-notes.md](references/upstream-notes.md)。

结论：要「任意联系人 + 不影响操作电脑 + 静默」，必须自备发送器（exec 后端）或装 wechat-use（upstream 后端）。本 skill 不承诺自己能发。

## 附：自己算原生发送 profile（不需要上游）

上游的发送能力依赖一组**按微信 build 变化、由服务端下发**的 Qt RVA。本 skill 附带把这组 RVA 从本机微信 `wechat.dylib` 自己算出来的流程（Ghidra + REA），完整步骤与判定标准见 [qt-native-send-derivation.md](references/qt-native-send-derivation.md)。三个可复用件：

| 文件 | 用途 |
|---|---|
| `scripts/derive_profile.py` | **一条命令从本机微信算出 `profile.json`**（版本 + 切片 sha256 + 各类的 metacall/vtable RVA） |
| `scripts/ghidra_macos_bootstrap.sh` | 在 macOS arm64 装出 REA 能用的 Ghidra（官方 zip 不含 mac 原生反编译器，需自编） |
| `scripts/macho_chained_fixups.py` | 解 Mach-O chained fixup；**没这一步，「扫指针找引用」必然命中 0** |
| `scripts/ghidra/Profile.java` | Ghidra 侧：扫出目标类的元对象/vtable 并吐 JSON（`derive_profile.py` 调它） |
| `scripts/ghidra/EnumMeta.java` | 扫出**全部** Qt `QMetaObject` 并解类名（本机 4.1.10 = 1116 个） |
| `scripts/ghidra/MetaNames.java` / `WalkMeta.java` / `DumpMeta.java` | 解某类的方法表 / 继承链 / 原始字段 |
| `scripts/native/wechat_send.c` | 最小进程内发送器（扫 vtable 找输入视图 → `setPlainText` id 16 → `Send` id 5），Unix socket 触发 |
| `scripts/native/{build_dylib.sh,make_clone.sh}` | 编 dylib；建 ad-hoc 重签副本并用 `DYLD_INSERT_LIBRARIES` 启动 |
| `references/qt-native-send-derivation.md` | 端到端流程、**已派生的 4.1.10 profile（§10/§11）**、坑、未解项 |

```bash
SKILL=<本 SKILL.md 所在目录的绝对路径>
GHIDRA_VER=12.1.4 "$SKILL/scripts/ghidra_macos_bootstrap.sh" "$HOME/ghidra"
export GHIDRA_INSTALL_DIR="$HOME/ghidra/ghidra_12.1.4_PUBLIC"
python3 "$SKILL/scripts/derive_profile.py" --out profile.json     # → RVA 全在这
"$SKILL/scripts/native/build_dylib.sh"                            # 编译发送 dylib
"$SKILL/scripts/native/make_clone.sh"                             # 建副本 + 扫码登录 + 启动（会新建一个微信副本）
```

**已在 WeChat 4.1.10 上派生成功**，关键结论：发送目标类不是裸 `QTextEdit`，而是微信自己的 `mmui::XTextEdit : QTextEdit` → `mmui::ChatInputField` → `mmui::ChatInputView`（有 `Send(SendActionType)` / `InsertMessage` / `InsertMention` 等槽）。具体 RVA 与方法索引见 [§10](references/qt-native-send-derivation.md)。**不需要跑完整自动分析**——唯一不能省的是 Ghidra 导入（它负责解 chained fixup）。

**仍是维护型工作**：微信热更后 RVA 漂移，必须重跑 `EnumMeta` + `MetaNames`。发**任意**联系人的「切会话/导航」是另一条独立机制，本流程不覆盖。

## 快速开始

```bash
SKILL=<本 SKILL.md 所在目录的绝对路径>
python3 "$SKILL/scripts/wechat_bridge.py" self-test   # 协议自检，零 GUI 零发送
python3 "$SKILL/scripts/wechat_bridge.py" probe       # 只读环境报告
python3 "$SKILL/scripts/wechat_bridge.py" serve       # 启动 127.0.0.1:18400
```

客户端（单次 POST，**永不重试**）：

```bash
python3 "$SKILL/scripts/wechat_bridge.py" send "文件传输助手" "任务完成：84/84 通过"
# 或任意 HTTP 客户端
curl -sS -X POST http://127.0.0.1:18400/send \
  -H 'Content-Type: application/json' \
  -d '{"wxid":"filehelper","text":"hello"}'
```

`send` 返回 `status_unknown` 时退出码 2，调用方**不得自动重发**（可能已送达）。用 `GET /receipt?request_id=<id>` 查登记状态。

## 配置（全部走环境变量，不读仓库密钥文件）

| 变量 | 默认 | 含义 |
|---|---|---|
| `WECHAT_BRIDGE_BACKEND` | `noop` | `noop` / `exec` / `upstream` |
| `WECHAT_BRIDGE_PORT` | `18400` | 监听端口，仅 loopback |
| `WECHAT_BRIDGE_BEARER` | 空 | 非空时非 `/health` 路由要求 `Authorization: Bearer <值>` |
| `WECHAT_BRIDGE_EXEC` | 空 | exec 后端命令模板（经 shell） |
| `WECHAT_BRIDGE_EXEC_SEND` | 空 | 只覆盖 `/send` 的命令 |
| `WECHAT_BRIDGE_EXEC_TIMEOUT` | `30` | exec 超时秒 |
| `WECHAT_BRIDGE_UPSTREAM` | `http://127.0.0.1:18400` | upstream 后端目标 |
| `WECHAT_BRIDGE_UPSTREAM_TOKEN` | 空 | 透传 `/send` 时附加的 Bearer |
| `WECHAT_BRIDGE_URL` | `http://127.0.0.1:18400` | `send` 子命令目标 |

## exec 后端契约

命令从 stdin 读一个 JSON 对象、向 stdout 打印一个 JSON 对象：

```
输入: {"op":"send","wxid":"filehelper","text":"hello","mention":null}
输出: {"status":"delivered","diagnostic":"optional"}
```

`op` 取值 `send` / `chats` / `unread` / `contacts` / `resolve` / `chat` / `chat_history`。查询类输出直接作为路由响应体。`status` 建议用 `delivered` / `submitted_unconfirmed` / `status_unknown` / `failed`，与上游一致。

用 `python3 -c` 包一层即可接任何 CLI；命令经 shell，务必别把未转义的用户输入拼进命令串（本 skill 用 stdin 传参就是为此）。

## 路由（与 wechat-use bridge 对齐）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/health` | 恒不需鉴权，返回 `ok` / `backend` / `send_ready` |
| GET | `/chats?limit=N` | 最近会话 |
| GET | `/unread` | 未读会话 |
| GET | `/contacts?query=X&limit=N` | 联系人 |
| GET | `/resolve?hint=X&limit=N` | 昵称/备注 → wxid 候选 |
| GET | `/chat/{wxid}` | 会话最近消息 |
| GET | `/chat/{wxid}/history?since=&until=&limit=` | 历史 |
| GET | `/messages/stream?since=<epoch>` | SSE；`since` 默认当前时间，避免 backfill 全历史 |
| POST | `/send` | body `{wxid,text,mention?}`，返回 `{status,diagnostic,request_id}` |
| GET | `/receipt?request_id=X` | 本 skill 扩展，查登记状态 |

SSE 默认过滤 `fromSelf:true`；`?includeSelf=true` 关闭过滤。noop 后端无入站源，只发一条 `: connected` 注释后短暂保持，不伪造消息。

## 安全边界

- 只绑 `127.0.0.1`；要对外暴露必须自己做隧道 + 鉴权，别直接改监听地址。
- 日志只打方法、路径与状态码，**不打 wxid、消息正文、token**。
- `text` 上限 8000 字符；`mention` 只接受 string / list / object。
- 传输失败、响应不可解码一律返回 `status_unknown` + 502，调用方不得重试，避免重复发送。
- `noop` 是默认后端：任何人在没配发送器时跑 `serve`，都不会误发消息。

## 接 wechat-use（upstream）

```bash
export WECHAT_BRIDGE_BACKEND=upstream
export WECHAT_BRIDGE_UPSTREAM=http://127.0.0.1:18401   # 避开上游自己占用的 18400
export WECHAT_BRIDGE_PORT=18500
python3 "$SKILL/scripts/wechat_bridge.py" serve
```

上游前置（不在本 skill 范围，见 [upstream-notes.md](references/upstream-notes.md)）：微信 4.1.9 独立副本、Telegram 激活码、`wechat-use setup`。

## 验收

```bash
python3 "$SKILL/scripts/wechat_bridge.py" self-test
```

覆盖三后端共 17 项：noop 的边界校验与 `status_unknown`、bearer 鉴权（`/health` 放行、其余 401）、exec 的 `delivered` 与 `request_id`。真实 GUI 发送、微信端送达、上游联调不在自检内。
