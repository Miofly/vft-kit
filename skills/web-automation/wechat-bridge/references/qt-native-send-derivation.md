# 自算原生发送 profile（Qt RVA 派生流程）

目标：不依赖上游服务端下发的 profile，自己从本机微信的 `Contents/Resources/wechat.dylib` 算出后台静默发送所需的 RVA 集合。上游的发送实现（见 [upstream-notes.md](upstream-notes.md)）就是靠这组 RVA 在微信进程内调 Qt 私有接口。

> 结论先说：**这条流程是「逐 WeChat build 重算」的维护型工作**，不是一次性脚本。微信热更后 RVA 漂移，必须重跑。
>
> **本机 WeChat 4.1.10 已实际派生成功**，结果与复现步骤见 [§10](#10-已派生的-profilewechat-4110本机实测纯静态不用自动分析)。全程不需要完整自动分析。

## 当前有效结论（2026-11-11 复核，优先于下文历史记录）

- **已登录副本不重启**：使用外部 `wechat_probe.c`，只调用读取接口，不暂停进程、不写内存、不调用 Qt、不触发登录或发送。旧版 socket 收到任意正文会执行写入/发送，不能拿它当只读探针。
- **4.2.0 / 270353 只读实测**：`ChatInputView` vtable RVA `0x9caf6c8`，其 `+0x200` 成员是 `ChatInputField`，vtable RVA `0x9caf158`。两对象均通过 `QObjectData::q_ptr` 回指检查。Ghidra 继承链证明 `ChatInputField` 经中间类继承 `XTextEdit` / `QTextEdit`。不是要求对象的动态 vtable 必须等于基类 `XTextEdit` 的 vtable。
- **RTTI 不可按明文类名盲搜**：该 build 的输入视图/编辑器 RTTI 名称分别是散列形式 `_dfb5955a` / `_3d16f471`；明文 `ChatInputView` / `TextEdit` 子串搜索会漏报。libc++ 的 `type_info` 名称指针还可能带高位标签。
- **字符串布局更正**：上游模板的 `QString` 是单指针持有 `QArrayData` 的 Qt5 风格布局；`data()` 地址为 `header + *(header+16)`。旧实现把偏移写成 `24-8`，与该模板不符；更不能把该布局称为通用 Qt6 ABI。当前代码删除手拼字符串和未验证的 Qt 调用，不再靠猜 ABI 发送。
- **必须在 GUI 主线程执行 QWidget 操作**：旧 socket 工作线程直接调用 Qt 是不正确的。新版安全底座将绑定复核放在 main queue；目前没有任何文本写入或发送调用。
- **新版产物仅支持 `probe\n`**：拒绝所有其他请求，`mutation_ready:false`；不宣称草稿或送达已验收。构建只写全新输出文件，不覆盖已映射 dylib；现有已登录进程仍加载旧产物，源码修复不等于已部署。
- `derive_profile.py` 的方法表现在由 `Profile.java` 从当前二进制解析，4.2.0 的 `Send` 为局部 id **8**、`setPlainText` 为 **16**；不再把旧的硬编码方法表写到新 profile。输出固定 `runtime_ready:false`。
- **后续原生/HTTP 实测补充**：`native_executor.py` / `lldb_runner.py` 通过短暂 LLDB 附着，在已运行副本主线程调用 Qt，不加载新 dylib。4.2.0 的收件人字段在 input `+0x258`（libc++ 短字符串 `filehelper`），editor 在 `+0x200`。已完成空草稿检查、Qt 写入与 UTF-16 回读、单次 `Send`（局部 id 8 / action 0）及发送后草稿清空；原生与 HTTP 各一次。状态均为 **`submitted_unconfirmed`**，窗口不可见导致聊天记录和手机端送达未独立确认。
- 实验字符串使用堆分配的 Qt5 风格数据头，offset=24、ref=1、capacity=len+1，使用当前 build 的 QString 析构释放；不是通用 Qt6 ABI，也不等于已找到真实字符串工厂。已复核的析构 RVA `0xadba4`，共享空串头 RVA `0xa383938`。模块须匹配完整文件 SHA-256，静态 slice 指纹不能混用。
- 原生 exec 通过私有 `WXS_NATIVE_CONFIG` 显式配置：`pid/module/module_sha256/probe/lldb_runner/state_dir/input_vtable/editor_vtable/editor_offset/recipient_offset/text_metacall/input_metacall/qstring_destructor/qstring_empty`；路径必须绝对。只允许 `WeChatSend.app` 与精确 filehelper，所有地址从此次 probe 重新取得，不缓存对象指针。字段从本 build 独立验证后填写，不自动将静态 profile 升为可发送配置。
- LLDB `--timeout` 的单位是微秒；5 秒为 `5000000`。SB API 设置 `SetTimeoutInMicroSeconds(5000000)`，选择唯一 main-thread，finally 分离。发送前持久 claim、串行锁、不自动重发；外部超时和窗口不可见不能作为未发送的证据。
- 尚未完成：独立送达确认、真实 Qt 字符串工厂、跨 build 生命周期验证、通用收件人导航及媒体发送。全功能范围另见 [capability-scope.md](capability-scope.md)。

下文保留研究线索；其中“Qt6”“RTTI 类名匹配已修好”“重启必丢登录”等早期断言不能作为当前使用依据。

## 1. 产出（profile 字段）

| 字段 | 含义 |
|---|---|
| `qtextedit_metacall_rva` | 输入框 `QTextEdit`(子类)`::qt_metacall` |
| `inputview_metacall_rva` | 输入视图 widget 的 `qt_metacall`（触发 send 的那支） |
| `editor_vtable_rva` / `message_vtable_rva` | `QTextEdit` 与消息对象的 vtable |
| `qstring_from_utf8_rva` | `QString::fromUtf8(const char*, qsizetype)` |
| `qarray_deallocate_rva` | `QArrayData::deallocate` |
| `editor_offset` | 输入视图对象内 `QTextEdit*` 的偏移（本机 4.1.10 观察值 `0x1f8`） |
| `recipient_offset` | 输入视图对象内 recipient `QString` 的偏移（观察值 `0x2b0`） |
| `send_action` | 传给输入视图 `qt_metacall` 的 method index（图像路径观察值 `3`） |
| `target_module_sha256` / `module_size` | 绑定 build 的指纹，用于校验取到的是同一份 dylib |

发送时序（上游模板原文摘录，method index 绑 build）：

```
wx_context_ok()                                    // INPUT/EDITOR vtable 匹配 且 *(INPUT+recipient_offset) == 目标 peer
wx_text_meta(EDITOR, 1, 9,  &before)               // 读草稿(QMetaObject::PropertyAccess, idx 9)，要求为空
wx_text_meta(EDITOR, 0, 16, {nullptr,&desired})    // setText(InvokeMetaMethod, idx 16)
wx_text_meta(EDITOR, 1, 9,  &actual)               // 回读校验
INPUT_META(INPUT, 0, 5, {nullptr,&send_action})    // 触发发送
```

## 2. 前置

```bash
# 2.1 取薄切片（fat → 单架构；file offset == vmaddr for __TEXT，省掉换算）
lipo -thin arm64 /Applications/WeChat.app/Contents/Resources/wechat.dylib -output /tmp/wechat_arm64.dylib

# 2.2 Ghidra（macOS arm64 必须自编原生反编译器，见 scripts/ghidra_macos_bootstrap.sh）
GHIDRA_VER=12.1.4 scripts/ghidra_macos_bootstrap.sh "$HOME/ghidra"
export GHIDRA_INSTALL_DIR="$HOME/ghidra/ghidra_12.1.4_PUBLIC"

# 2.3 REA + Ghidra 必须放长启动超时 + 加大堆，否则大目标直接失败
export REA_GHIDRA_STARTUP_TIMEOUT_MS=14400000
export REA_GHIDRA_DECOMPILE_TIMEOUT_SECONDS=900
export GHIDRA_MAXMEM=14G          # REA 默认给 headless 2G；147 MB / 34 万函数会在
                                  # ConstantPropagationAnalyzer 阶段 java.lang.OutOfMemoryError
npx -y rea-agents@latest capabilities    # ghidra 应显示 status: available
```

## 3. 为什么不能「直接扫指针」

`wechat.dylib` 带 `LC_DYLD_CHAINED_FIXUPS`：**磁盘上的指针是位编码的 chained-fixup 条目，不是明文地址**。用「在 `__DATA_CONST` 里找指向字符串区的 8 字节值」这类办法必然命中 0，会让你误判「这些数据没人引用」。

先用 `scripts/macho_chained_fixups.py` 看清引用关系再动手：

```bash
scripts/macho_chained_fixups.py /Applications/WeChat.app/Contents/Resources/wechat.dylib
# → arch=arm64 rebases=484952（本机 4.1.10 实测）
scripts/macho_chained_fixups.py <dylib> --find 0x87f6000-0x87f7000
# → 某个地址区间被谁引用（entry 就是持有指针的字段地址）
```

⚠️ **地址按 8 位十六进制写**：`0x87f6000` 是 142 MB 处；多写一位（`0x87f60000` = 2.28 GB）会超出镜像、静默返回 0 条，看起来像「没人引用」——这个坑我踩过，见 §9。

`--find` 输出的 `entry` 是**切片相对地址**（与 Ghidra 导入后看到的一致），fat 文件偏移 = `entry + slice_offset`（本机 = `+0x9ec8000`）。

实测：fixup 里确实存在指向 Qt moc stringdata 表的引用（`entry 0x904a3e8 -> 0x87f6c04` 等），但那些结构不是 `QMetaObject`（见 §9）。

## 4. 定位 RVA（Ghidra headless + 持久 project）

**不要用 REA 的 `inspect` / `search` / `trace` 做迭代查询**：REA 的 Ghidra 会话是「每次调用即导入、关闭即丢弃」，`rea inspect` 之后再 `rea search` 会**重新导入并重跑一遍 147 MB 全分析**。一个查询几十分钟，迭代不可行。

改用 `analyzeHeadless` + **持久 project**（分析一次，后续 `-process` 秒级复用）：

```bash
D=/tmp/wechat_arm64.dylib
GH="$GHIDRA_INSTALL_DIR/support/analyzeHeadless"

# 4.1 首次：导入 + 自动分析 + 跑扫描脚本；不传 -deleteProject，project 留用
GHIDRA_MAXMEM=14G "$GH" /tmp/ghproj wechat \
  -import "$D" -scriptPath <skill>/scripts/ghidra -postScript ScanQtRefs.java

# 4.2 之后：复用已分析 project，只跑脚本（秒级）
GHIDRA_MAXMEM=14G "$GH" /tmp/ghproj wechat -process -noanalysis \
  -scriptPath <skill>/scripts/ghidra -postScript <你的脚本>.java

# 4.3 取单个函数伪代码（REA 也可，但它会重建会话）
npx -y rea-agents@latest decompile "$D" --file-offset=0x<...>
```

`scripts/ghidra/ScanQtRefs.java` 做侦察：打印所有内存块、Qt moc 字符串地址，以及**每一条指向 moc 字符串区的数据引用**（`REF entry=0x... -> 0x...`，entry 就是持有指针的字段地址）。用它把元对象结构找出来。

判定标准（在跑通前都算未验证）：

- `qtextedit_metacall_rva` 反编译出来应是 `qt_metacall(QMetaObject::Call, int, void**)` 形状的薄分发函数（`switch` / 表驱动，转发到 `qt_static_metacall`）。
- `inputview_metacall_rva` 的 `method index == send_action` 分支应最终触发发送（可对 `send_action` 取值做交叉验证）。
- `editor_offset` / `recipient_offset` 用运行期内存布局复核（attach 副本后读对象字段），不要只靠静态猜。

## 5. 剩余未知（不要当成已解决）

- **导航**：上游实现只校验「当前会话 == 目标」；发任意联系人的「切会话」是另一条独立机制，未在本流程覆盖。已定位候选类：`mmui::ChatSessionList` / `mmui::ChatSessionCell` / `mmui::ChatPage`（见 §10）。
- **`send_action` 语义**：已确认是 `SendActionType` 枚举，喂给 `ChatInputField::send`(id 0) 或 `ChatInputView::Send`(id 5)（见 §10.4）；**各枚举值的含义（哪个=文本/图片/文件）仍未验证**。
- 未实跑：需要在**副本**（`com.tencent.xinWeChat419WechatUse` 之类）上 ad-hoc 重签加 `get-task-allow` 并独立登录，主微信不动。

## 6. 坑

1. Ghidra release zip **不含 macOS 原生反编译器**（只有 linux/win）→ 必须自编；Makefile Darwin 分支硬编码 `-arch x86_64`。
2. 别 build 默认目标：`com_*` 依赖 GNU BFD（`bfd.h`）；只要 `ghidra_opt`。
3. REA 的 Ghidra 启动超时默认太短，`wechat-send-mcp`（3.88 MB）都会 timeout；必须设 `REA_GHIDRA_STARTUP_TIMEOUT_MS`。
4. **headless 堆默认 2 GB 不够**：147 MB 的 `wechat.dylib` 会在 `ConstantPropagationAnalyzer` 阶段 `java.lang.OutOfMemoryError: Java heap space`，Ghidra 直接退出（REA 报 `failure_kind: process / "Ghidra exited before bridge startup"`）。设 `GHIDRA_MAXMEM=14G`（`analyzeHeadless` 也认 `GHIDRA_HEADLESS_MAXMEM`）。实测机器需 ≥24 GB 内存。
5. REA 的 MCP/CLI 输出很大，全部重定向到文件再 grep；`--json` 不要直接灌进会话。
6. Ghidra 分析会临时建立 project（本机实测 ~1.4 GB），`REA_GHIDRA_DISABLED_ANALYZERS` 可用来跳慢分析器。

## 7. 实测记录（2026-11-10，本机 WeChat 4.1.10 build 268851，未跑通）

按上面流程实际执行到的位置与结果：

1. **`-noanalysis` 就够**：Ghidra 的 Mach-O loader **在导入阶段解析了 chained fixup**，内存里是明文指针。因此「扫数据段找指向 X 的指针」在 Ghidra 内存里成立，在裸文件字节上不成立。
2. **交叉验证通过**：`ScanQtRefs` 报指向 `[0x87b0000,0x8a83000]` 的引用 **62,569** 条；自写 `macho_chained_fixups.py` 报 **62,564** 条。两边一致 → 解码器可信；之前「0 引用」的结论只是窗口没取到（Qt 的 `QMetaObject` 串在 0x8a7dxxx，不在 0x87fxxxxx 窗口内）。
3. **Qt 元对象没找到**：按「连续 3 个指针指向 __TEXT / __text」的签名扫，命中 111 条全是 C++ RTTI `type_info`（类名形如 `N10mars_boost12bad_any_castE`），**没有一条是 Qt `QMetaObject`** → 该 build 的 Qt 元对象是紧凑/相对偏移布局，需要 Qt6 元对象感知的解析才能定位。
4. **符号表无 Qt 命名**：443,793 条符号里 `_ZN7Q*` 为 **0**，Qt 内部函数全是匿名 `FUN_*`；`QTextEdit` 相关只命中 1 条自动命名 `s_{QString="d"^v}_08a9299e`。
5. **`-noanalysis` 拿不到真实函数边界**：只建出 **3,436 个函数**（`__stubs` 的绑定导入），不是 `LC_FUNCTION_STARTS` 的 342,114 个。
6. **完整自动分析在本机跑不动**：`-Xmx14G` 跑到约 18 分钟时 RSS 从 1.37 GB 掉到 0.26 GB、CPU 掉到 10%、日志停更——swap 已用 20.3/21.5 GB，是换页打满而非报错。第一轮 `-Xmx2G` 则在 `ConstantPropagationAnalyzer` 阶段 `java.lang.OutOfMemoryError` 退出。

## 8. 结论与下一步

> **本节写于「还没派生出 RVA」时。后来换了思路（见 §10）：不需要函数级分析，Qt 元对象数据本身就是完整的，`-noanalysis` 就能全部枚举，RVA 已成功派生。以下保留为过程记录。**

- 工具链已打通并验证（Ghidra 自编原生反编译器、headless 持久 project、chained-fixup 解析、扫描脚本、与自写解码器交叉一致）。
- 当时以为卡点是资源：147 MB / 34 万函数的完整自动分析需要 ≥16 GB 空闲内存，本机 swap 打满会卡死。**实际不需要走这条路**（见 §10）。
- 两条当时设想的路线：①换机器跑完整分析；②自写 Qt6 元对象解析（不依赖自动分析）。**②最后成功了**，而且比预想简单：不用解紧凑布局，Qt6 的 `QMetaObject` 布局就能直接枚举。

## 9. 补充实测（同场次，修正 §7 第 2 条的两处误判）

- **§7 第 2 条里「0 引用」是我打错十六进制位数**：写成 `0x87f00000`（9 位 = 2.28 GB，超出镜像），正确是 `0x87f0000`。用对窗口后确实有引用。
- **确实有 fixup 指向 Qt moc stringdata 表**：`entry 0x904a3e8 -> 0x87f6c04`（stringdata0 基址，offset 0）、`0x904a4d8 -> 0x87f6c12`、`0x904a508 -> 0x87f6c70`。
- **但这些结构不是 `QMetaObject`**。读 `0x904a3e0` 的字段：`{963dd10, 87f6c04, 9041020, 963dd10, 87f6ec2, 9041008, 0, 904a4d0}` —— 是「指针 + 字符串」成对表（GOT/描述符风格），不是 `{superdata, stringdata, data, static_metacall, …}`。
- **Qt6 紧凑元对象（相对偏移 int32 版本）也没找到**：按「field[1]/field[2] 相对落在 `__TEXT,__const`、field[3] 相对落在 `__text`」扫描得 26 条，逐条核验全是 SVG path / XMP 元数据的偶然命中。

**净结论**：静态侧走到「知道数据里存在指向 Qt 字符串表的引用，但这些引用不是 Qt 元对象结构」为止。要把 RVA 钉出来，需要**函数级**能力（完整自动分析，或自写 Qt6 元对象解析），本机资源不支持前者。

## 10. 已派生的 profile：WeChat 4.1.10（本机实测，纯静态、不用自动分析）

**突破点**：`wechat.dylib` 的 Qt **元对象数据是完整的**，且**不需要 Ghidra 自动分析**就能全部枚举——`-noanalysis` 导入即可（loader 已解 chained fixup）。办法是扫 `QMetaObject` 结构签名并按 Qt6 布局解类名/方法名。

### 10.1 类层级（`WalkMeta.java` 沿 `superdata` 链走，独立交叉验证）

```
mmui::XTextEdit      : QTextEdit            ← 编辑器本体
mmui::ChatInputField : mmui::XTextEdit      ← 输入框
mmui::ChatInputView                         ← 输入视图（含 Send 槽）
mmui::ChatInputSendView                     ← 发送按钮
```
`mmui::XTextEdit` 的 `superdata` 落在 `0x904a3b0` —— 正是用 RTTI（`9QTextEdit` mangled 名 → `type_info` → `vtable[-1]`）独立定位到的 `QTextEdit::staticMetaObject`。两条独立路径互证。

### 10.2 可直接用的 RVA（arm64 切片，RVA 即 `__TEXT` 内地址）

| 项 | 值 |
|---|---|
| `mmui::XTextEdit::staticMetaObject` | `0x8e231f8` |
| `mmui::XTextEdit` static_metacall | **`0x197e10c`** |
| `mmui::ChatInputField::staticMetaObject` | `0x8c5c870` |
| `mmui::ChatInputField` static_metacall | **`0xb5638`** |
| `mmui::ChatInputView::staticMetaObject` | `0x8c5c900` |
| `mmui::ChatInputView` static_metacall | **`0xb6040`** |
| `mmui::ChatInputSendView` static_metacall | `0xb5b14` |
| `QTextEdit` 主 vtable / `staticMetaObject` | `0x904a178` / `0x904a3b0` |
| 切片 sha256 | `664db7d439fef26fdfb772f12559ca68512ba5f09eed5ca5ffd8e5406231929f` |

> `static_metacall(QObject*, QMetaObject::Call, int id, void**)` 的签名与 `qt_metacall` 相同，**可以直接调用**，因此不一定需要再取 vtable 里的 `qt_metacall`。注意 `static_metacall` 的 `id` 是**本类局部索引**；`qt_metacall` 的 `id` 要先减去父类方法数。

### 10.3 方法表（`MetaNames.java` 按 size 扫字符串块还原，真名）

`mmui::ChatInputView`（id 为 static_metacall 局部索引）：

| id | 方法 | argc |
|---|---|---|
| 0 | `OnSend` (signal) | 0 |
| 1 | `OnSendResult` | 1 |
| 2 | `OnShowBizMenu` | 0 |
| 3 | `EditModeChanged` | 2 |
| 4 | `SwitchInputType` | 1 |
| **5** | **`Send`** (slot) | 1 (`SendActionType`) |
| 6 | `HandleUserWillLogout` | 0 |
| 7 | `HideMainWindowWhenShot` | 0 |
| **8** | **`InsertMessage`** (slot) | 1 (`kernel::MessageWrapper`) |
| **9** | **`InsertMention`** (slot) | 1 (`kernel::AtUsersMemberInfo`) |
| **10** | **`SetReferMessage`** (slot) | 1 (`kernel::ReferSendData`) |

`mmui::ChatInputField`：

| id | 方法 | argc |
|---|---|---|
| **0** | **`send`** | 1 (`SendActionType action_type`) |
| 1 | `enterPress` | 0 |
| 2 | `SendEmoticon` | 1 (`kernel::EmoticonDataInfoPtr`) |
| 3 | `focusStateChanged` | 2 |
| 4 | `enterLongTextEdit` | 1 |
| 5 | `exitLongTextEdit` | 1 |

`mmui::XTextEdit`：`textDidChanged`(signal)、`emoticonInsertPlainText`(slot)。

### 10.4 与上游 profile 的对应

- 上游 `send_action` → **`SendActionType` 枚举**，喂给 `ChatInputField::send`(id 0) 或 `ChatInputView::Send`(id 5)。这就是「3/5/16」这类常量的来源。
- 上游 `qtextedit_metacall_rva` ↔ `mmui::XTextEdit` 的 qt_metacall（本机可直接用 `0x197e10c`）。
- 上游 `inputview_metacall_rva` ↔ `mmui::ChatInputView` 的 qt_metacall（本机 `0xb6040`）。
- 上游 `mention_rva` ↔ `mmui::ChatInputView::InsertMention`(id 9)。
- **导航**（发任意联系人）：候选 `mmui::ChatSessionList` / `mmui::ChatSessionCell` / `mmui::ChatPage`。
- 上游还要 `qstring_from_utf8_rva` / `qarray_deallocate_rva` 是为了造 `QString`；若改用 `InsertMessage(kernel::MessageWrapper)` 这类接口，未必要走 QString 路径（待验证）。

### 10.5 复现步骤（全部不依赖自动分析，秒级）

```bash
# 1) 导入（--noanalysis 足够）
GHIDRA_MAXMEM=6G "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" /tmp/ghproj wechat \
  -import /tmp/wechat_arm64.dylib -noanalysis -scriptPath <skill>/scripts/ghidra -postScript EnumMeta.java
# 2) 复用 project 取具体类的方法表 / 继承链 / 原始字节
GHIDRA_MAXMEM=6G ... -process -noanalysis -postScript MetaNames.java  0x8c5c900
GHIDRA_MAXMEM=6G ... -process -noanalysis -postScript WalkMeta.java   0x8e231f8
GHIDRA_MAXMEM=6G ... -process -noanalysis -postScript DumpMeta.java   0x904a3b0 0x8c5c900
```

`EnumMeta.java` 在 4.1.10 上输出 **1116 个带类名的 QMetaObject**（完整清单存 `other/temp/research/wechat-use-study/wechat-4110-classes.txt`）。

### 10.6 仍未验证

- `SendActionType` 各枚举值的含义（哪个值=发文本/发图/发文件）——需要读 `ChatInputField::send` 的反编译或运行时试。
- `mmui::XTextEdit` / `ChatInputField` / `ChatInputView` 的 vtable 地址（identity 校验用）与 `editor_offset`（输入视图对象内编辑器指针偏移）。
- 群聊 @ 提及参数结构、导航（切会话）的具体槽。
- 整条链**未在真机跑过**：需要副本 + `get-task-allow` 重签 + attach。

## 11. 补全：vtable、setText id、以及两处可以砍掉的复杂度

### 11.1 vtable（`Vtables` 思路已并入 `Profile.java`，`derive_profile.py` 一次出全）

| 类 | vtable（RVA，列表） |
|---|---|
| `mmui::ChatInputView` | `0x8c7ab98` |
| `mmui::ChatInputField` | `0x8c7a088`, `0x8e11e30` |
| `mmui::XTextEdit` | `0x8e2deb8` |
| `QTextEdit` | 14 个，含 `0x8e398c8`（子对象）、**`0x904a178`（主，与 RTTI 路径独立得出同一地址）**、`0x904dee0` 等 |

方法：vtable 第 0 槽是 `metaObject()`，其函数体就是 `adrp/add` 算出 `&staticMetaObject`。所以「找以 V 开头的函数是不是 metaObject()」→ 命中即为 vtable 起始槽。

⚠️ **一个类可能有多个 vtable**（多继承/子对象），`profile.json` 输出的是**列表**：判定「某对象是不是该类的实例」要**任一匹配**，不能只比列表第一个。列表顺序：`offset-to-top == 0`（即 `*(vtable-16)==0`）的排前面。

### 11.2 `setText` 的 id = 16（**上游硬编码常量在 4.1.10 上复现**）

解 `QTextEdit::staticMetaObject` 的方法表：

```
m[16] setPlainText(QString)   ← 上游 C++ 模板里的 index 16
m[19] setText(QString)
m[25] clear()
m[27] insertPlainText(QString)
```

上游 `wx_text_meta(EDITOR, 0, 16, ...)` 用的就是 **16 = `setPlainText`**（不是注释里写的 `setText`）。这是第三条独立互证：**我解出来的 id 与上游自己的常量一致**。

### 11.3 能砍掉的复杂度（相对上游）

| 上游做法 | 简化 | 依据 |
|---|---|---|
| LLDB 表达式求值 / `mach_vm_write` | **`DYLD_INSERT_LIBRARIES` 加载自己的 dylib**，进程内直接调 | ad-hoc 重签（无 hardened runtime）的副本认这个环境变量；上游自己已经有 load-command 注入的机制 |
| `qstring_from_utf8_rva` + `qarray_deallocate_rva` | **不再省略真实工厂与析构验证** | 旧手拼头偏移与上游模板不符，不能将 Qt5 风格布局称作通用 Qt6 ABI；目前写入/发送关闭 |
| 完整自动分析 | `-noanalysis` 导入即可 | §10 |

### 11.4 最小实现（已进 skill）

| 文件 | 说明 | 验证程度 |
|---|---|---|
| `scripts/derive_profile.py` | 一条命令算出 `profile.json`（版本 + 切片 sha256 + 各类 RVA/vtable） | **已跑通**，产出 4.1.10 的真实 profile |
| `scripts/native/wechat_send.c` | 进程内发送器：扫 vtable 找输入视图/编辑器 → `setPlainText`(id 16) → `Send`(id 5)；Unix socket 触发 | **编译通过**（arm64 dylib），**未在真机跑** |
| `scripts/native/build_dylib.sh` | 编 + ad-hoc 签 dylib | 已跑通 |
| `scripts/native/make_clone.sh` | 复制副本 → 改 bundle id → 加 `get-task-allow` 重签 → `DYLD_INSERT_LIBRARIES` 启动 | **未跑**（会新建一个微信副本并要扫码登录） |

### 11.5 仍未验证（别当成能用）

- `SendActionType` 的取值（哪个值 = 发文本）。上游 4.1.9 图片路径观察值是 3。
- 编辑器绑定：`wechat_send.c` 现在按「输入视图附近 0x4000 内的 XTextEdit」找编辑器；上游 4.1.9 用的是固定偏移 `0x1f8`，**4.1.10 的偏移没算**。
- 整条链**一次真机都没跑过**：需要执行 `make_clone.sh`（建副本、扫码登录）才能验。

## 12. 真机注入实测记录（2026-11-10，WeChat 4.1.10 副本）

做法：`ditto` 一份 WeChat.app → `PlistBuddy` 改 `CFBundleIdentifier` 为 `com.tencent.xinWeChat.send` → `codesign --force --deep -s - --entitlements`（`get-task-allow` + `cs.disable-library-validation`）→ `DYLD_INSERT_LIBRARIES=<dylib> .../Contents/MacOS/WeChat`。

**已验证**：
- 副本独立运行：独立 bundle id、独立容器 `~/Library/Containers/com.tencent.xinWeChat.send/`，**主微信不受影响**。
- **`DYLD_INSERT_LIBRARIES` 在 ad-hoc 重签的副本里生效** —— dylib 的构造函数确实在 WeChat 进程内跑了（日志 `[wechat_send]` 出现在进程 stderr）。所以**不需要**打 load command、**不需要**调试器。
- Unix socket 能起、能收请求、能回响应。

**踩的四个坑（都已修，代码里带注释）**：

1. **构造函数跑得比 `wechat.dylib` 加载早**：在 constructor 里解析 image base 必然拿到 0 → 必须**收到请求时懒解析**。
2. **Helper 进程也继承 `DYLD_INSERT_LIBRARIES`**，会跟主进程抢 socket。守卫不能写 `strstr(path, "/Contents/MacOS/WeChat")` —— `WeChatAppEx.app/Contents/MacOS/WeChatAppEx` 也命中这个前缀；必须要求路径**结尾**精确等于 `/Contents/MacOS/WeChat`。否则拿到 socket 的是没加载 `wechat.dylib` 的 Helper，请求永远 `notready`。
3. **直接解引用可写内存扫对象 → 进程 `Bus error: 10` 崩溃**：WeChat 有大量保留/未提交 VM 区域。必须用 `mach_vm_read_overwrite`（读不了返回错误码，不崩），按 0x1000 分块扫，跳过 >256 MB 的保留区。
4. `mach_vm_read_overwrite` 要 `#include <mach/mach_vm.h>`（只有 `mach/mach.h` 会隐式声明报错）。

5. **同名镜像有两份**：`Contents/Resources/wechat.dylib`（307 MB，真核心，RVA 是给它的）和 `Contents/Frameworks/wechat.dylib`（**84 KB，stub**）。按 `strstr(name,"wechat.dylib")` 找 base 会先命中 84K 的 stub，`base+RVA` 指到无意义位置 → 扫出假对象 → 崩。**必须只认 `/Contents/Resources/wechat.dylib`**（或取最大的那个）。
6. 修完 base 后**请求路径仍会崩**（SIGSEGV，约 1 s 内、扫描之后）。最可能是实例扫描的**假阳性**：可写内存里随机出现等于 vtable 地址的 8 字节值，被当成对象后调进去。下次迭代要先给候选加校验（例如要求 `metaObject()` 返回值等于该类的 `staticMetaObject`），并让 dylib 用 `write(2)` 逐步打点，别用 stdio（崩了看不到缓冲）。

**未验证（需要扫码登录副本后才谈得上）**：`ChatInputView` 实例扫描能否命中、`setPlainText`/`Send` 调用是否真的发出消息、`SendActionType` 取值。**真机发送路径从未成功跑通一次**——注入、socket、安全性（不崩在扫描外）已验证，但「调用」这一步未验证。

7. **dylib 必须 fat（arm64 + arm64e）**：宿主 `WeChat` 用 `lipo -archs` 看是 `x86_64 arm64`，但 dyld 插入时按 **arm64e** 校验，纯 arm64 dylib 直接被拒并在启动瞬间退出：`terminating because inserted dylib ... (mach-o file, but is an incompatible architecture (have 'arm64', need 'arm64e'))`。`build_dylib.sh` 现在两切片一起编再 `lipo -create`，不猜。
8. **从 shell 启动副本会变英文 UI**：本机 shell（Claude Code / Orca 宿主）带 `__CFBundleIdentifier=com.stablyai.orca` 和 `LANG=en_US.UTF-8`，AppKit/CFBundle 的本地化按这个宿主解析，于是副本登录窗全英文（`Scan to log in`）。启动时清掉：`env -u __CFBundleIdentifier -u __CF_USER_TEXT_ENCODING -u LANG -u LC_ALL -u LC_CTYPE DYLD_INSERT_LIBRARIES=... WeChat`。清完窗口标题即恢复「微信」。

9. **不要为调试擅自重启已登录副本**：此前看到登录窗口便断言“重启必丢登录”，没有确认当前主窗口；后续同一 pid 已存在聊天主窗口，旧登录窗仍可隐藏留存。Keychain ACL 是否影响登录态也未验证，不能当根因。正确做法是绑定当前可见主窗口确认登录状态，离线完成修复后再说明加载变更的影响，不让用户反复扫码。旧版 `/tmp/wxs.conf` 热加载不能替代收件人和草稿安全检查。
10. **局部方法 id 逐 build 变，别信旧表**：4.2.0 的 `mmui::ChatInputView::Send(SendActionType)` 局部 id 是 **m[8]**（`MetaNames.java` 实测），4.1.10 的 profile 里写的是 5；`QTextEdit::setPlainText` 两版都仍是 **m[16]**。
11. **不能从未登录探针推断实例定位方案优劣**：登录后外部只读探测通过精确 vtable 和 QObject 回指找到唯一输入视图及其 `+0x200` 编辑器。前者 RTTI 是 `_dfb5955a`，后者是 `_3d16f471`，按明文类名搜索反而会漏。基类 vtable 不等于派生对象 vptr；必须核对继承链与成员归属，不能全局挑第一个 `TextEdit`。

副本位置 `~/Applications/WeChatSend.app`（1.6 GB）；不再需要时直接删目录即可，主微信与它的容器都没动。
