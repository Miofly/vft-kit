---
name: wechat-ops
description: "微信桌面端与微信平台操作合集。桌面：给文件传输助手或指定联系人发消息（原 wechat-bridge 发送桥）、把这段话发到微信时使用；平台：公众号后台登录、草稿排版、发表、素材、IP 白名单、40164/48001，小程序开发者工具 CLI、automator 自测、miniprogram-ci 上传体验版、提审发布、版本状态、广告分享规则、wxapkg 反编译复刻样式，TikTok Minis 抓 H5 前端。"
---

# 微信操作（wechat-ops）

本 skill 由原 `wechat-bridge`（桌面微信发送桥）与 `wechat-mp`（公众号 / 开发者平台 / 小程序）合并而来，两条主线互不相干，按需要只看其中一条。

| 主线 | 覆盖 | 入口 |
|---|---|---|
| **A. 桌面微信发送** | 给文件传输助手或已授权联系人原样单次发消息；loopback HTTP 桥（noop / exec / upstream）；原生 Qt 发送 profile 派生（研究型） | 见下方「A」节；细节 [capability-scope.md](references/capability-scope.md)、[qt-native-send-derivation.md](references/qt-native-send-derivation.md) |
| **B. 微信平台后台** | 公众号草稿/发表/素材/密钥白名单；小程序上传、提审、发布、版本状态；wxapkg 反编译；TikTok Minis | 见下方「B」节；路由表在「B」节末 |

---

## A. 桌面微信发送（原 wechat-bridge）

零依赖 Python 标准库实现，只绑 `127.0.0.1`。**协议适配外壳**，不是已验收的 wechat-use 全功能替代。后端决定真实能力；当前 SSE 只有占位握手，没有消息源。

**最终目标**：覆盖上游 `docs/capabilities.md` 当前公开支持的全部功能。优先复用上游 CLI / daemon / SDK，保留其激活、签名与 build 前置条件；功能清单、缺口和逐项验收见 [capability-scope.md](references/capability-scope.md)。自派生 RVA 不等于已实现读取、媒体、朋友圈、TUI 或网关。

**账号保护**：用户授权测试的 `WeChatSend` 副本可以自主检查；消息测试仅用文件传输助手，不碰主微信。已登录后不擅自重启、重签、覆盖已映射 dylib 或要求反复扫码。优先用外部只读探测器，不连接旧版“收到任意正文就发送”的 socket；无收件人校验不得试发。不得承诺零风控风险。

**续研交接**：[2026-11-11 记录](references/handoff-2026-11-11.md) 包含暂停时状态、证据路径、约束与下一步；仅供恢复研究，不因加载此记录自动执行发送或 GUI 操作。

### 文件传输助手：后台快速发送（不启动 HTTP 服务）

微信 macOS 4.2.0 副本已验证发送侧文字和批量照片。明确指定文件传输助手与正文或本地图片后，优先用下方独立发送器复用已登录且可操作的 `WeChatSend`；不动主微信、不启用前台回退。

```bash
# 将 SKILL 和 WXS_WORK 设为技能目录和本机工作目录的绝对路径。
: "${SKILL:?set absolute skill directory}" "${WXS_WORK:?set absolute work directory}"
export WECHAT_DESKTOP_STATE_DIR="$WXS_WORK/desktop-receipts"
mkdir -p -m 700 "$WECHAT_DESKTOP_STATE_DIR"
/usr/bin/swiftc -O "$SKILL/scripts/desktop_sender.swift" -o "$WXS_WORK/desktop-sender"
"$WXS_WORK/desktop-sender" self-test
printf '%s\n' '{"op":"probe"}' | "$WXS_WORK/desktop-sender"
```

编译一次、按需复用，`probe` 仅读已打开的文件助手。明确获准发送时，通过 JSON stdin 提交 `{"op":"send","recipient":"filehelper","request_id":"<唯一请求号>","text":"<单行原文>"}`，或把 `text` 换成 `"photos":["<JPG 绝对路径>"]`（1–4 张）。同一状态目录内回执跨发送器进程保留；结果未知只用 `{"op":"receipt","request_id":"<原请求号>"}` 查询，不换号补发。此 CLI 不依赖 wechat-use 激活，但仍依赖微信副本登录及窗口可操作。CLI 已通过编译、自检和真实窗口预检。真机四图测试中，粘贴已生效，但草稿更新晚于首次回读；改为限时回读确认张数，不重复粘贴。随后对已核实的草稿仅提交一次，草稿清空，但无法从同名「图片」条目识别本批消息，故保留 `status_unknown`，不补发；成功发送总耗时和手机接收均未核实。

1. **确认目标**：复用标题精确匹配的文件传输助手独立窗；否则从副本会话列表绑定唯一匹配项并后台打开。操作前重新核对窗口归属、会话标题、输入框及草稿为空。隐藏窗 `ax_window_unresolved` 时停止，不重启、不置前。
2. **准备草稿**：文字原样后台输入并回读。批量 JPG 作为文件 URL 一次写入系统剪贴板，核对完整路径列表；只在能无损备份原剪贴板时使用，粘贴后按 `changeCount` 恢复，不覆盖期间用户复制的新内容。用输入框最新 `element_token` 调 `press_key(key:"v", modifiers:["cmd"])` 后台粘贴，不走 `hotkey` 菜单路线。复查草稿对象数与输入文件数一致；4 张 JPG 实测有 4 个 U+FFFC 占位，并出现「发送后合并展示照片」。这条路线按照片发送，不承诺原文件字节不变。
3. **单次提交并回验**：对同一输入框的最新 `element_token` 后台按一次 `Return`。复查草稿清空、聊天记录新增对应消息，并核对前台应用；不要把点击「发送」的成功回执当作已发。图片记录无法逐张确认时，只报提交张数和可见记录，不报手机端全收。结果未知不补发。好友、群聊和原文件发送不套用此路线。

**只读查询**：同一 CLI 支持 `{"op":"history","recipient":"filehelper","limit":20}`、`{"op":"search","recipient":"filehelper","query":"关键词","limit":20}`、`{"op":"stats","recipient":"filehelper","limit":20}`。`limit` 为 1–100，默认 20。只读已打开的文件助手当前 AX 快照最后 N 个可识别消息标签，不切会话、不滚动、不读取数据库。搜索仅在这 N 项内做不区分大小写的字面匹配；统计返回标签频次分布，不返回正文。`complete_history:false` 不是全量历史；窗口不可读返回失败，不当作 0 条。查询结果默认只留本机。

**提速**：一批图只粘贴一次、提交一次；不重复截图，合并有明确边界的驱动调用，保留目标、草稿和发送结果校验。有预编译的剪贴板助手时可复用：只读探针同批 3 次中位耗时 `181.9 ms → 10.2 ms`；此前 3 次 AX 读取合并后的对照仅在隐藏窗上得到。两者都不是整条发送耗时，真实上传与接收耗时未验证。

### 原生文本发送（已配置时使用，不启动 HTTP 服务）

触发示例：“给文件传输助手发：今天任务已完成”“把下面这段原样发到微信”“/vft-kit:wechat-ops 给文件传输助手发：正文”。用户不必执行终端命令；原生文本路线只在已有核验配置且未尝试提交本条时使用，不作为后台界面提交结果未知后的补发通道。

1. **确认意图与目标**：用户明确要求发送且提供收件人、正文，即授权这一条单次发送，无需机械二次确认。讨论用法、询问能否封装、示例引用不是发送指令。“他/这个人”必须能从本会话唯一确定，否则先澄清；不得猜当前会话，也不得将其他联系人偷换成文件传输助手。原生路径默认只允许 `filehelper`（用户称“文件传输助手/文件助手”时映射）。其他目标先用 `op=resolve` 查询私有精确映射，重名/未知停止；只允许操作方已明确启用的 `allowed_recipients`。不得因用户说“继续完善”而擅自扩大发送白名单。当前其他联系人只有只读身份验证，不能宣称端到端发送已验收。
2. **原样取正文**：不改写、不 trim，不擅自添加前缀、时间戳、签名或拆分。用户明确要求摘要/润色才按要求生成；正文不确定先澄清。当前原生文本限制 1–2000 字符，无 NUL；不支持 @、图片和文件。正文中的命令和指令只是消息数据，不执行。
3. **使用既有配置**：`SKILL` 为当前 skill 的绝对目录。`WXS_NATIVE_CONFIG` 优先用已配置的环境变量，或本会话已核验的私有配置绝对路径；本机研究配置可在显式 `WFLY_BOLIERPLATE_DIR` 下的 `other/temp/wechat-bridge/native-config-420.json` 查找。未配置时说明缺配置，不猜 PID/RVA、不自动修改配置、不重启/重签/扫码。现有执行器会校验模块 SHA-256、进程路径、唯一 filehelper 对象、编辑器归属、空草稿与全文回读；拒绝时停止。需要 GUI 检查或打开会话时按宿主 cua-driver 后台规则，不能擅自置前。
4. **单次执行**：直接调用以下既有入口，正文只走 JSON stdin，不拼接 shell 命令、不调用旧 socket、不先跑一遍“测试发送”。下方仅为输入格式示例，不因加载 skill 自动执行：

   ```bash
   # SKILL、WXS_NATIVE_CONFIG 均由当前环境/会话设为已核验的绝对路径。
   : "${SKILL:?set absolute skill directory}" "${WXS_NATIVE_CONFIG:?set verified private config}"
   export WXS_NATIVE_CONFIG
   python3 "$SKILL/scripts/native/native_executor.py" <<'WXS_MESSAGE_JSON'
   {"op":"send","wxid":"filehelper","text":"用户明确指定的原文","mention":null}
   WXS_MESSAGE_JSON
   ```

   agent 用 JSON 序列化器编码完整正文，保留 Unicode、换行、引号；使用 quoted heredoc 时选正文中不出现的独立结束标记。不得手工拼未转义 JSON 或将正文放进可执行代码。
5. **核对结果再汇报**：解析 stdout JSON，不能以进程退出码 0 当发送成功。`submitted_unconfirmed` 报“已提交给文件传输助手，送达未确认”并保留原生 `request_id`；`failed` 报拒绝原因；`status_unknown`、超时、无输出或不可解析响应报“结果未知，不重发”。只在独立聊天记录或接收端核验后说明相应证据，不将草稿清空冒充送达。
6. **未知不重发**：不切 GUI/HTTP 补发，不更换正文绕过去重，不删除 claim；重复正文拒绝时只读原回执。持久 claim 当前以 pid、精确收件人、正文为键，不承诺跨进程重启幂等；恢复会话后也先核对历史尝试，不能因 PID 改变就重发。读取回执不调用发送入口。

本工作流复用已测试的 `native_executor.py`，没有新增发送机制；封装完成不等于独立送达验收完成。

#### 精确收件人预检与私有配置

执行器新增只读输入 `{"op":"resolve","hint":"备注名"}` 和 `{"op":"preflight","wxid":"精确ID"}`，与发送相同入口、JSON stdin。`resolve` 只读私有配置的 `recipient_aliases`，返回 `resolved/ambiguous/not_found`；不能当完整通讯录搜索。`preflight` 重新读取对象并精确核对 `recipient_offset` 字段与编辑器归属，返回 `target_matched` 也固定 `send_ready:false`，不附着 LLDB、不读写草稿、不创建 claim、不发送。

私有配置可增加 `"recipient_aliases":{"唯一备注":["wxid_exact"]}` 与 `"allowed_recipients":["filehelper","wxid_exact"]`；只有操作方明确授权具体联系人后才修改白名单，不自动把发现的 ID 加进去。缺省白名单仍仅 filehelper。昵称重名可存多个候选，必须消歧，不能取第一条。收件人最长 128 字节，只接受 ASCII 微信 ID；主线程支持该 build 的 libc++ 短/长字符串完整比较，写入前和提交前复核。持久 claim 使用 pid、精确收件人、正文，旧 filehelper claim 摘要不变。

**探测器升级必须同步**：新版 `wechat_probe` 用法为 `PID INPUT_VTABLE_RVA EDITOR_VTABLE_RVA [RECIPIENT_OFFSET]`，执行器始终传入已核验偏移。编译到新的绝对路径、自测通过再修改私有配置的 `probe`；旧版无精确字段会拒绝，不能退回子串命中绕过。无需重启微信。

当前已实测另一现有会话的后台打开与精确 ID 只读读取，**未向该会话发送**。后台搜索还没有可靠候选结果，单击可能不切会话、双击可能打开独立窗口；独立窗口关闭后对象释放，须重新定位。通用导航及其他联系人端到端发送仍未完成；不可读时停止，不抢前台、不自动重启。

### 什么时候用

- 大模型 / 定时任务 / CI 要把结果发到微信，且不想弹窗、不想抢焦点。
- 已有 wechat-use 或任意微信发送器，想统一成一套 HTTP 调用契约。
- 想在接真实发送器之前，先把调用方（agent、hook、脚本）调通。

不用：要企业微信机器人 / 公众号 API 这类现成通道；要读聊天记录做分析（本 skill 只做发送契约，读取路由交给后端）。

### 决策：后端选哪个

| 后端 | 环境变量 | 行为 | 何时用 |
|---|---|---|---|
| `noop` | 默认 | 收到 `/send` 只登记、`status_unknown`，**绝不发送** | 调调用方、跑自检、CI |
| `exec` | `WECHAT_BRIDGE_EXEC` 或 `WECHAT_BRIDGE_EXEC_SEND` | 每条操作起一个命令，stdin/stdout 传 JSON | 已有任意发送脚本，接进来 |
| `upstream` | `WECHAT_BRIDGE_UPSTREAM`（默认 `http://127.0.0.1:18400`） | 全路由透传给已运行的 wechat-use bridge | 已装好 wechat-use，要统一入口/加鉴权 |

**关键事实（本机实测 2026-11-10）**：微信 macOS 4.1.10 的辅助功能树没有可写的聊天输入框，AX 窗口数在 0 和 1 之间漂移。该观察不能推出所有后台界面输入都不可用：2026-11-11 已在 4.2.0 副本完成一次 cua-driver 后台界面发送侧核验；零焦点变化与手机接收未单独验证。上游 wechat-use 的后台发送走的是 `wechat-public-native-send/v1`：在独立微信副本进程内用 LLDB 表达式求值调用 Qt `qt_metacall`（先 setText 写输入框，再触发 send 动作），早期经 `task_for_pid` / `mach_vm_read_overwrite` / LLDB 附着，后改 `mach_vm_write` 免附着；按微信 build 指纹的一组 RVA 适配，绑定 4.1.9 特定 build 与服务端激活码。本 skill 只做协议互操作，注入实现不在这一层；技术细节见 [upstream-notes.md](references/upstream-notes.md)。

结论：上述 HTTP 桥本身不发送，需配置真实后端。文件传输助手可走前文已验的后台界面路线；任意联系人和群聊不在该路线的验收范围内。

### 附：自己算原生发送 profile（不需要上游）

上游的发送能力依赖一组**按微信 build 变化、由服务端下发**的 Qt RVA。本 skill 附带把这组 RVA 从本机微信 `wechat.dylib` 自己算出来的流程（Ghidra + REA），完整步骤与判定标准见 [qt-native-send-derivation.md](references/qt-native-send-derivation.md)。三个可复用件：

| 文件 | 用途 |
|---|---|
| `scripts/derive_profile.py` | **一条命令从本机微信算出 `profile.json`**（版本 + 切片 sha256 + 各类的 metacall/vtable RVA） |
| `scripts/ghidra_macos_bootstrap.sh` | 在 macOS arm64 装出 REA 能用的 Ghidra（官方 zip 不含 mac 原生反编译器，需自编） |
| `scripts/macho_chained_fixups.py` | 解 Mach-O chained fixup；**没这一步，「扫指针找引用」必然命中 0** |
| `scripts/ghidra/Profile.java` | Ghidra 侧：扫出目标类的元对象/vtable 并吐 JSON（`derive_profile.py` 调它） |
| `scripts/ghidra/EnumMeta.java` | 扫出**全部** Qt `QMetaObject` 并解类名（本机 4.1.10 = 1116 个） |
| `scripts/ghidra/MetaNames.java` / `WalkMeta.java` / `DumpMeta.java` | 解某类的方法表 / 继承链 / 原始字段 |
| `scripts/native/wechat_probe.c` | 外部只读探测：核对核心镜像、vtable、QObject 回指、成员归属与 filehelper 字段，不注入、不调用 Qt、不发送 |
| `scripts/native/native_executor.py` / `lldb_runner.py` | 限定 build 的实验 exec 发送器：精确收件人白名单（默认 filehelper）、只读 resolve/preflight、主线程 Qt 校验与持久防重发；此前 filehelper 发送侧聊天记录已核验，多收件人改动未真发验收 |
| `scripts/native/test_native_executor.py` | 原生执行器离线回归；不附着微信、不发送 |
| `scripts/native/wechat_send.c` | 实验 dylib 安全底座：只接受 `probe\n`，唯一对象与成员绑定复核在主线程；发送永久拒绝，尚不能作为 exec 发送器 |
| `scripts/native/build_dylib.sh` | 编译到指定的全新绝对路径，签名失败即退出，不覆盖已加载 dylib |
| `scripts/native/make_clone.sh` | 只准备副本和签名，绝不自动启动或登录；已有副本拒绝覆盖 |
| `scripts/test_derive_profile.py` / `scripts/native/test_native.py` | profile 回归、对象校验、socket 拒绝发送和端点占用保护 |
| `references/qt-native-send-derivation.md` | 端到端流程、**已派生的 4.1.10 profile（§10/§11）**、坑、未解项 |

```bash
SKILL=<本 SKILL.md 所在目录的绝对路径>
GHIDRA_VER=12.1.4 "$SKILL/scripts/ghidra_macos_bootstrap.sh" "$HOME/ghidra"
export GHIDRA_INSTALL_DIR="$HOME/ghidra/ghidra_12.1.4_PUBLIC"
python3 "$SKILL/scripts/derive_profile.py" --out profile.json     # → RVA 全在这
WXS_WORK=<已存在的任务产物目录的绝对路径>
"$SKILL/scripts/native/build_dylib.sh" "$WXS_WORK/wechat_send-probe-only.dylib"
# 不加载进已登录副本，也不要再跑 make_clone.sh 触发重建。
python3 "$SKILL/scripts/test_derive_profile.py"
python3 "$SKILL/scripts/native/test_native.py"
```

**已在 WeChat 4.1.10、4.2.0 上派生静态元数据**；`methods` 从当前 build 的元对象表提取，输出固定 `runtime_ready:false`，不沿用硬编码索引。4.2.0 中 `ChatInputView` **持有** `ChatInputField`（实测偏移 `0x200`），后者经中间类继承 `XTextEdit` / `QTextEdit`；不能把持有关系写成继承链。`Send` 局部 id 为 8，`setPlainText` 为 16。**不需要跑完整自动分析**，Ghidra loader 负责解 chained fixup。实例、ABI、目标身份与送达必须另外验收，静态成功不代表能发。

**仍是维护型工作**：微信热更后 RVA 漂移，必须重跑 `EnumMeta` + `MetaNames`。发**任意**联系人的「切会话/导航」是另一条独立机制，本流程不覆盖。

### 快速开始

```bash
SKILL=<本 SKILL.md 所在目录的绝对路径>
python3 "$SKILL/scripts/wechat_bridge.py" self-test   # 协议自检，零 GUI 零发送
python3 "$SKILL/scripts/wechat_bridge.py" probe       # 只读环境报告
python3 "$SKILL/scripts/wechat_bridge.py" serve       # 启动 127.0.0.1:18400
```

客户端（单次 POST，**永不重试**）：

```bash
python3 "$SKILL/scripts/wechat_bridge.py" send filehelper "任务完成：84/84 通过" --request-id task-84
# 或任意 HTTP 客户端（两种方式只选一种）
curl -sS -X POST http://127.0.0.1:18400/send \
  -H 'Content-Type: application/json' \
  -d '{"wxid":"filehelper","text":"任务完成：84/84 通过","request_id":"task-84"}'
```

每笔新发送用唯一 `request_id`，省略时自动生成。同一桥进程中，同 ID、同内容只提交一次；同 ID、不同内容返回 `409`。用 `GET /receipt?request_id=<id>` 只读查询，后端 ID 单列为 `native_request_id`。`pending` 和 `status_unknown` 的 CLI 退出码为 2，**只查回执，不自动重发**。去重与回执仅存于当前桥进程，重启后 `not_found` 也不代表没发。

### 配置（全部走环境变量，不读仓库密钥文件）

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

### exec 后端契约

命令从 stdin 读一个 JSON 对象、向 stdout 打印一个 JSON 对象：

```
输入: {"op":"send","wxid":"filehelper","text":"hello","mention":null}
输出: {"status":"delivered","diagnostic":"optional"}
```

`op` 取值 `send` / `chats` / `unread` / `contacts` / `resolve` / `chat` / `chat_history`。查询类输出直接作为路由响应体。`status` 建议用 `delivered` / `submitted_unconfirmed` / `status_unknown` / `failed`，与上游一致。

用 `python3 -c` 包一层即可接任何 CLI；命令经 shell，务必别把未转义的用户输入拼进命令串（本 skill 用 stdin 传参就是为此）。

### 路由（与 wechat-use bridge 对齐）

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
| POST | `/send` | 仅文本：body `{wxid,text,mention?,request_id?}`；返回桥接回执 |
| GET | `/receipt?request_id=X` | 只读查询当前桥进程登记的回执，不触发发送 |

SSE 默认过滤 `fromSelf:true`；`?includeSelf=true` 关闭过滤。noop 后端无入站源，只发一条 `: connected` 注释后短暂保持，不伪造消息。

### 安全边界

- 只绑 `127.0.0.1`；要对外暴露必须自己做隧道 + 鉴权，别直接改监听地址。
- 日志只打方法、路径与状态码，**不打 wxid、消息正文、token**。
- `text` 上限 8000 字符；`mention` 只接受 string / list / object。
- 传输失败、响应不可解码一律返回 `status_unknown` + 502，调用方不得重试，避免重复发送。
- `noop` 是默认后端：任何人在没配发送器时跑 `serve`，都不会误发消息。

### 接 wechat-use（upstream）

```bash
export WECHAT_BRIDGE_BACKEND=upstream
export WECHAT_BRIDGE_UPSTREAM=http://127.0.0.1:18401   # 避开上游自己占用的 18400
export WECHAT_BRIDGE_PORT=18500
python3 "$SKILL/scripts/wechat_bridge.py" serve
```

上游前置（不在本 skill 范围，见 [upstream-notes.md](references/upstream-notes.md)）：微信 4.1.9 独立副本、Telegram 激活码、`wechat-use setup`。

### 验收

```bash
python3 "$SKILL/scripts/wechat_bridge.py" self-test
```

自检覆盖参数边界、Bearer 鉴权、并发去重、请求号冲突、超时后回执查询与后端回执关联。只使用本地模拟后端，不验证真实微信端送达。

### 实验原生 Qt exec 接线（仅 filehelper）

`native_executor.py` 不调用旧 dylib socket、不导航、不重启，只对已运行的 `WeChatSend` 副本做短暂 LLDB 主线程调用。它需要显式的 `WXS_NATIVE_CONFIG` 私有 JSON（绝对路径），字段与构建参数见 [派生说明](references/qt-native-send-derivation.md)。不能把自动派生的静态 profile 直接作为可发送配置。

```bash
export WXS_NATIVE_CONFIG=<已人工核验的私有配置绝对路径>
export WECHAT_BRIDGE_BACKEND=exec
export WECHAT_BRIDGE_EXEC_SEND="python3 '$SKILL/scripts/native/native_executor.py'"
python3 "$SKILL/scripts/native/test_native_executor.py"
# 服务由用户明确要求时启动；所有发送只尝试一次。
python3 "$SKILL/scripts/wechat_bridge.py" serve --port 18540
```

2026-11-11 原生 Qt 与 HTTP 各完成一次真实提交、草稿清空，原回执均为 `submitted_unconfirmed`；后续后台截图已确认这两条与聊天 skill 消息的发送侧聊天记录，未见失败标记，手机端接收未验证。新增多收件人门禁尚未进行真发回归，不能拿此前结果当新代码的发送验收。`request_id` 是 HTTP 追踪号，exec 返回的原生回执号另以 `native_request_id` 保留。重复正文会拒绝，不能删除 claim 后重试；只读核对原回执。并发操作由串行锁拒绝。LLDB 异常/超时后不得假定没有提交，也不得重启副本来清除疑点。

---

## B. 微信公众号 / 开发者平台 / 小程序（原 wechat-mp）

用 ego-lite 复用登录态操作公众平台（草稿、素材、发表）与开发者平台（密钥、白名单、接口权限），并用 CLI/接口完成小程序上传、提审、版本查询和反编译复刻。

### 何时用

- 公众号：Markdown 转草稿、配图与封面、发表、素材/发表记录/用户管理读取。
- 开发者平台：AppID/AppSecret、IP 白名单、接口权限与额度，排查 `40164`/`48001`。
- 小程序：开发者工具 CLI、automator 自测、miniprogram-ci 上传体验版、提审与发布、版本状态、广告分享规则、wxapkg 反编译复刻。

### 浏览器到 API 的强制演进

本 skill 只要以浏览器执行远端业务动作，就必须先读并遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)。登录、验证码、2FA、纯视觉验收可保留浏览器；认证后的可接口化动作仍须抓取、复现、独立回验，并在同一任务自更新本 skill 与脚本。

### 核心流程（发文到草稿箱）

1. 读 [policies.md](references/policies.md)；`useOrCreateTaskSpace('wechat mp <做什么>')` 复用登录态，见 [login.md](references/login.md)。
2. 从当前页面 URL 现取 `token`，确认右上角账号名。
3. `node scripts/md-to-mp-html.mjs article.md --json` 转 inline-style HTML。
4. 开 `isNew=1` 新编辑器页，等编辑器初始化；标题 `insertText`，正文合成 paste。
5. 关弹窗后点「保存为草稿」，URL 出现 `appmsgid=` 即成功。
6. 用户明确要求发表时才走发表流程，以发表记录精确命中标题为准。

逐步代码见 [publish-article.md](references/publish-article.md)。

### 硬规则

- 改密钥、白名单、看接口权限一律去开发者平台；公众平台那页只剩迁移通知。
- 不去 `.secrets` 找密码；只有实际出现扫码/确认步骤才 `handOffTaskSpace`。
- `token` 每次登录都变，永远从当前页面 URL 现取，不复用旧 token。
- 每篇文章开 `isNew=1` 新编辑器；不在已有内容页重复 paste。
- 正文用合成 paste 写入，不直接写 `innerHTML`；成功看 `chars`/`h2` 数。
- 图片只走本地上传；封面是发表硬前置，判据是 `.js_cover_preview_new` 背景图含 `mmbiz`。
- 动手前把视口调到 1100 高，或用 `elementFromPoint` 确认命中。
- 除非用户明确说发布/群发，一律停在草稿。
- 发表成功只认发表记录 `publish_list` 按完整标题命中并拿到 `content_url`。
- 管理员验证二维码 `img.qrcode.js_qrcode` 不在 dialog 内，别漏掉。
- 接口能不能调只看开发者平台「接口权限与额度」，不靠记忆。
- AppSecret 重置后旧值立即失效，先确认能同步配置。
- 解除授权、重置密钥、发表、删文、提审与发布动手前先确认。
- 凭据不写进本 skill 或仓库；多账号先核对 `.weui-desktop-account__info`。
- 反编译只用于学习研究或有权使用的设计，不分发解出的源码。

### 路由表

| 任务 | references | 执行脚本 |
|---|---|---|
| API 优先、安全边界、确认规则 | [policies.md](references/policies.md) | — |
| 登录、handoff、远程扫码二维码交付 | [login.md](references/login.md) | `ego-browser nodejs` |
| 两个后台分工、token、公众平台页面清单、编辑器 DOM | [mp-backend.md](references/mp-backend.md) | — |
| Markdown 发草稿、插图、封面、视口、草稿箱发表、管理员扫码 | [publish-article.md](references/publish-article.md) | `scripts/md-to-mp-html.mjs`（`--selftest`） |
| 开发者平台 tab、AppSecret、白名单、接口权限与额度 | [console.md](references/console.md) | `ego-browser nodejs` |
| `40164`、`48001`、粘贴重复、发表无反应等报错 | [troubleshooting.md](references/troubleshooting.md) | — |
| 小程序上传、预览、版本状态、提审 | [miniprogram-release.md](references/miniprogram-release.md) | `scripts/mp-ci.mjs`、`scripts/wxamp-version-status.mjs`、`scripts/wxamp-submit-audit-api.mjs`（兜底 `scripts/wxamp-submit-audit.mjs`） |
| 小程序开发者工具 CLI、automator 自测、本地后端、广告与分享；小游戏后台登录、测试号、读控制台（cua-driver） | [miniprogram-devtools.md](references/miniprogram-devtools.md) | `scripts/miniprogram-automator-helpers.cjs` |
| 反编译 wxapkg、还原 WXSS、复刻到 Taro；小游戏代码与已访问资源归档 | [wxapkg-unpack.md](references/wxapkg-unpack.md) | `scripts/wxapkg/wxapkg.sh`、`scripts/wxapkg/extract-wxss.mjs`、`scripts/wxapkg/split-service.mjs`、`scripts/wxapkg/export-game.py` |
| TikTok Minis 链接抓 H5 前端产物学习 | [tiktok-minis.md](references/tiktok-minis.md) | `scripts/tiktok-minis/fetch.py` |
| 全部文件说明 | [file-index.md](references/file-index.md) | — |
