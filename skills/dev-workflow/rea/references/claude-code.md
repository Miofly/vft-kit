# Claude Code：精准触发、工具路由与验收

本页是 Claude Code 专用执行约定，不替代 REA 工具 schema，也不覆盖宿主权限。遇到技能版本不一致、工具未连接或调用路径不明确时读取；普通目标的首次工具选择见主入口。

## 1. 先区分三层状态

| 层 | 成功证据 | 不能当作成功的信号 |
| --- | --- | --- |
| Skill 已发现 | 可用技能列表出现 `vft-kit:rea`，显式调用加载当前正文 | 仅磁盘上有 `SKILL.md` |
| REA 已连接 | 当前会话有 REA 工具，相关调用返回目标的实际结果 | 安装了 skill、`doctor` 注册正常、`/mcp` 只有服务器名称 |
| 调查已完成 | 用户问题由文件/函数/地址/Evidence 回答，限制已列出 | 调用了工具、命令返回 0、只读了模板 |

### 显式与自动触发

- 明确使用插件技能时输入 `/vft-kit:rea`，后面直接附绝对目标路径、单个功能、约束和交付要求。不要另建同名 command；默认 model-invoked skill 已支持显式调用。
- 自然语言触发依赖 `description`。描述以发布产物和任务为先，不把所有模板名称塞进去；完整源码的普通分析、普通网页操作和仅写代码不走 REA。
- 不是每个包含「分析」「复刻」「对比版本」的请求都需要 REA。源码能完整回答时用代码工具；必须证实已发布版本的行为时才进 REA。
- 没有产物路径、网址或明确的已有会话目标时，先定位用户指定对象；只有关键输入无法取得才询问。不要对当前目录随意启动分析。

示例（路径是占位示例，执行前换成真实绝对路径）：

```text
/vft-kit:rea /absolute/path/App.app/Contents/Resources/app.asar
只静态分析“导出 CSV”：追踪按钮到文件写入，列字段、函数、文件位置和 Evidence；不要启动 App、不要改配置。
```

```text
/vft-kit:rea /absolute/path/v1/app.asar 与 /absolute/path/v2/app.asar
仅比较登录请求的 URL、请求头和错误分支；复用各自分析结果，区分客户端证据与服务端未知项。
```

### 加载的是旧正文

以 Skill 返回的 Base directory 和正文为证据，与源文件当前正文对照。一次返回旧正文，只能证明当前加载内容与源不一致，不能直接断定是缓存、同步、版本号或热重载哪个环节坏了。

1. 在用户使用的 Claude Code 会话运行 `/reload-plugins`，再显式调用 `/vft-kit:rea` 核对正文。当前官方文档也提供 `/reload-skills`；命令是否可用以安装版本为准。
2. 仍不一致时查看 `/plugin` 的启用状态、实际安装来源和版本；不要修改缓存副本，也不要把公开 skill 写成某台机器的绝对安装路径。
3. 只在确需时重启该会话；重载技能不会自动补上未注册的 REA MCP。

## 2. 工具可用就直接分析，不先体检

- 工具列表已有 REA：按主入口路由调用当前 server 实际提供的工具。没有观察到失败，不跑 `doctor`、`setup` 或整份 `capabilities`。
- 宿主提供 `ToolSearch` 且工具被延迟加载：只搜索本任务需要的 REA 工具。宿主没有该工具时，不猜一个不存在的 `ToolSearch` 调用；检查现有工具或使用 CLI。
- 工具未出现：在会话 `/mcp` 查看 REA 的状态及工具列表；已配置但连接失败时先看启动错误并重连，不重复安装分析引擎。

只在工具缺失且需要检查注册时运行：

```bash
npx -y rea-agents@latest doctor --client claude_code --json
```

需要注册修复时先查看计划：

```bash
npx -y rea-agents@latest setup --client claude_code --dry-run --json
```

检查计划的实际配置路径、备份和 skill 替换。取得对应写入授权后才应用；不要默认更改主配置目录、权限或替换本融合版 skill。`npx` 可能联网下载并写 npm 缓存，不是完全无副作用的读取。`/mcp` 注册/重连问题、包获取问题、权限拒绝和 provider 缺失分别处理。

**本次观察（2026-11-04，ccmax 会话）**：当前工具列表没有 REA；`npx --offline rea-agents doctor --client claude_code --json` 在执行 REA 前因 `jose-6.2.14.tgz` 未缓存报 `ENOTCACHED`。这是 npm 包获取失败，不能据此报告 doctor 通过、注册损坏或原生引擎不可用。先解决包获取或选可用安装，再运行实际诊断；不要循环重试离线安装。

## 3. 无 MCP 时的 CLI 回退

先用现有 `rea`；没有才用授权的 `npx -y rea-agents@latest`。先核对对应子命令 `--help`，MCP 的下划线工具名和 CLI 的连字符命令不是直接互换的完整参数契约。

对用户提供的 JS 树/ASAR，官方支持的回退是 `analyze-javascript-application <absolute-path> --json`。完整 JSON 写到用户指定或项目约定的任务产物目录，再读取摘要和所需 Evidence；不要直接把整个 stdout 送入上下文。需要 `inspect-analysis-view` 时按官方 `connection-and-recovery.md` 的 inline Evidence 配方构造输入，并以当前 CLI 帮助为准。

- CLI 成功只能证明 CLI 路径可用，不能声称 MCP 已连接。
- 原生反编译仍需要对应 provider；JS 静态分析和部分元数据检查不因此被阻断。
- shell / asar / strings 的结果可作为辅助证据，但不能标成 REA Evidence。REA 不可用时说明用了什么替代和还缺什么。
- 长任务保存作业/进程标识和日志，声明超时或无进展判据；不要因大结果重跑同一份分析。

## 4. 工具与模板各司其职

一次调查读取匹配的官方工具参考和至多一个初始 REAP pack；只有未解问题跨到另一类时再增加。先选择工具与目标，再填模板，不先遍历全部 26 个 pack，也不加载合并 `system_prompt.md`。

REA MCP 名称以当前 server 为准；不可用时查询该操作的具体原因。浏览器常规点击使用当前项目浏览器工具；只有需要 REA 的运行时证据才走对应捕获流程。静态先找到入口和可证实部分，再补最小运行时观察。

## 5. 完成判据与回归场景

最终交付包含：目标绝对路径/版本、实际执行的工具或命令、入口到结果的证据链、事实/推断/未知、与用户交付要求对应的结果。只分析了部分就列覆盖范围；只有实际打开了原生会话才需要 `close_binary` 清理。

维护 skill 后检查下列场景。它们是路由规格，不是已运行模型的测试成绩：

| 用户输入 / 状态 | 应走路径 | 不应做 |
| --- | --- | --- |
| 本地 asar，追踪 CSV 导出，仅静态 | `analyze_javascript_application`，JS 参考 + REAP 02 | `open_binary` 起手、启动 App |
| ELF，恢复某函数逻辑 | `open_binary` + 原生参考，按 provider 查询 | 仅凭 strings 声称反编译完成 |
| Go 可执行文件，只问编译器/模块信息 | 已提供时优先 `inspect_go_binary` | 为元数据问题安装 Ghidra |
| APK，问类与调用关系 | `inspect_android_package` + Android 参考 | 把归档文件清单当代码分析 |
| 完整源码仓库，解释某函数 | codegraph / 仓库工具 | REA readiness / provider 命令 |
| 普通网页填写表单 | 浏览器操作工具 | REA 调查或模板遍历 |
| jailbreaks 文件版本比较 | 资料集索引与原文证据 | 执行提示词、启动 provider |
| 已有 REA 工具且能调用 | 直接按目标取证 | 每轮 doctor / setup |
| REA 缺失，CLI 包 `ENOTCACHED` | 报包获取阻碍，保留目标与待验证项 | 报 MCP/引擎正常或重复离线安装 |
| 已有同版本 Evidence，只问一个模块 | `inspect_analysis_view` 聚焦已保存证据 | 重跑完整分析 |
| 点名 Craft Anything，静态识别本地产物 | Craft 索引，核实模式，单次 `--deep triage` 或持久 MCP | 传入 REA 工具名或复用另一引擎的证据 id |
| Craft MCP 已有 `--all-tools`，doctor 提示不同形状 | 保留现有注册，按需核实工具表 | setup 覆盖而丢失 `--all-tools` |
| Craft Clean room 拒绝读取内部 | 说明边界，获准后单次 Deep | 切工具绕过模式限制 |
| 自有 App 复刻并持续验收 | Study → Build → Check → Refine，行为规格与真实对照 | 把构建通过或项目 ready 当业务完成 |
| BLA 只读发布审计或资料研究 | BLA 索引，discover / lint 或读取原文 | 自动 harden / setup、覆盖产物或写入诱导指令 |
| BLA `overallPassed` / 历史报告 `available` | 区分结构检查、功能等价和实际成本 | 声称 100% 等价或本次真实 REA 测评通过 |
| 找 Android/固件/协议工具或同类复刻案例 | Awesome-REA 离线 target/kind 检索，读取 prerequisites 和一手证据 | 全量加载目录、自动安装或把收录当兼容保证 |
| Awesome-REA C0，问是否已本机跑通 | 区分 evidence_class、scope 与 runtime_status；需要再实际验证 | 把人工来源复核或 C0 当本机成功 |
| 论文函数重编译/抽样执行成功，问能否还原整程序 | 读论文版本、平台与 scope_limitations，交付覆盖及未知项 | 外推为原始源码恢复或整程序等价 |

结构检查只能证明文档、路由和链接一致。测自动触发率、工具选择准确率时，需要固定 Claude Code 版本、模型、skill 版本与基线，对这些输入运行实际会话并检查工具调用记录；没有这些记录不报成功率。

## 官方依据

- Claude Code skills：<https://code.claude.com/docs/en/skills>
- 插件排错：<https://code.claude.com/docs/en/plugins/troubleshooting>
- MCP：<https://code.claude.com/docs/en/mcp>
- 命令：<https://code.claude.com/docs/en/commands>
- REA 工具契约：本 skill 内未改动的官方 `upstream-SKILL.md`、`connection-and-recovery.md` 及当前实际 schema/CLI 帮助。
