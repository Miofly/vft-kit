# Craft Anything：独立工具链与复刻闭环

将 [storytold/craft-anything](https://github.com/storytold/craft-anything) 接入同一个 `rea` 入口，不替换 REA，不另注册 skill，也不自动安装或修改客户端配置。

## 来源与收录范围

- 固定提交：`7859973d7ca41b0f19c5fa5d11ac93e053ec39e6`，分支 `main`，收录日期 `2026-11-09`。
- `upstream/` 原样收录 13 个文件：英文 README、MIT / Apache-2.0 双许可、官方调查 skill 与恢复说明、工具目录 / 状态 / 文件格式 / 命名说明，以及 4 份项目与检查 JSON schema。文件内容与上游一致，校验见 `SHA256SUMS`。
- 这是**精选参考快照**，不是全仓源码或可执行引擎。README 内未收录的相对链接需回固定提交的上游查看；不把上游贡献者规则加载成宿主指令。
- 唯一路径映射：`crates/setup/src/skill.md` → `upstream/crates/setup/src/PLAYBOOK.md`，字节不变。macOS 大小写不敏感文件系统会把 `skill.md` 当作 `SKILL.md`，导致单 skill 校验失败；归档参考统一避开该名称。
- 官方调查入口：[PLAYBOOK.md](upstream/crates/setup/src/PLAYBOOK.md)；[恢复说明](upstream/crates/setup/src/skill_recovery.md)；[完整工具目录](upstream/docs/tools.md)；[上游验证范围](upstream/docs/tool-status.md)；[格式](upstream/docs/file-formats.md)。
- 本地验收版本为 CLI `0.3.0`；当次 `commands` / `capabilities` 均列 315 个工具。快照 README 的宣传数量与生成工具文档计数不同，后续以当前可执行文件和 MCP schema 为准，不照抄数量作能力保证。

## 选择工具链

| 问题 | 路线 |
| --- | --- |
| 现有 REA 会话已能回答 | 继续使用 REA 及其 Evidence，不为同一问题重跑另一套引擎 |
| 希望使用 Craft 内置原生解析、Java、Apple、游戏归档或项目账本 | 进入 Craft；先核实当前模式、工具与外部引擎需求 |
| 只有已发布产物，要追一个功能 | 先静态识别，再按目标启用一个 toolset；需要时配合 REAP 模板 |
| 从网站 / App / 游戏重建，并持续对照原目标 | Study → Build → Check → Refine；采用下方项目与验收规则 |
| 完整源码的常规分析、普通浏览器操作 | 用代码图、项目工具和宿主浏览器流程，不启动逆向引擎 |

REA 与 Craft 的工具名、会话、分析数据库及证据 id **不通用**。报告用 `REA:<id>` / `Craft:<ev_id>` 标明来源；跨引擎时附目标 SHA-256、版本、地址空间和原始证据位置，不直接把另一套 id 传入工具。

## 首轮与接入

1. 已有 Craft MCP 工具就直接使用；只缺某组时先 `list_toolsets`，再 `enable_toolset`。无工具才检查 CLI，按需 `doctor`；不要每次 setup。
2. `capabilities` 检查当前模式、可用工具与引擎；`commands` 列工具，`<command> --help` 查实际参数。MCP 工具 id 使用下划线，CLI 对应连字符。
3. MCP 持久会话入口为 `craft-anything-cli mcp`。默认只列 core 与已启用组；`mcp --all-tools` 可列全表，但不授予 Deep 或运行权限。若现有注册有 `--all-tools`，不要执行 setup 覆盖掉它；上游已记录 doctor 可能将其误报为不同命令形状。
4. 需要新增注册时先 `setup --dry-run` 展示方案，再按宿主配置规范确认写入；重连后核实真实工具表。加载本 skill 不等于 MCP 已注册。
5. **Clean room 默认不读目标内部**；获准静态检查产物时用单次 `--deep` 或带该参数的专用 MCP 会话，不全局修改 `deep_mode`。`details.reason=clean_room` 是模式边界，不是引擎故障，不换工具绕过。Deep 也不等于允许执行目标。

以下路径变量由调用者设置为绝对路径；公共 skill 不携带个人目录：

```bash
craft-anything-cli --version
craft-anything-cli capabilities
craft-anything-cli commands
craft-anything-cli js-app-map --help

# 同一次 CLI 调用中打开并识别目标；只解析，不执行目标。
craft-anything-cli --deep --project "$REA_WORK_DIR/investigation.cany" triage "$REA_TARGET"

# 单次静态分析已发布 JS / ASAR / bundle，不需要先打开目标。
craft-anything-cli --deep --project "$REA_WORK_DIR/investigation.cany" \
  js-app-map --input-path "$REA_TARGET" --output-format json

# 需要持久 targets、浏览器或 debugger 状态时使用同一个 MCP 会话。
craft-anything-cli --project "$REA_WORK_DIR/investigation.cany" mcp
```

CLI 每次调用会新建 session。不能把 `core-target-open` 与依赖 active target 的工具拆成两个独立命令并假定目标仍打开；`--project` 保存证据与调查记录，不保证活连接跨进程恢复。网页的 `web_site_open` / `web_site_capture` 必须放在同一个 MCP / app / rebuild 会话内。

## 按目标取证

| 目标 | Craft 工具 id；用前查实时 schema |
| --- | --- |
| 原生 ELF / PE / Mach-O | `core_target_open` → `core_target_triage` / `core_overview_show` → `native_function_study`、`native_call_path_find` |
| Go / Rust / WASM / 固件 / 网络记录 | `native_go_binary_show`、`native_rust_binary_show`、`formats_wasm_module_show`、`firmware_regions_list`、`web_recording_show` / `packets_capture_show` |
| Electron / ASAR / JS | `js_app_map` → `app_feature_follow`；静态不足才 `js_runtime_code_match` / `js_electron_walkthrough_record` |
| Apple / Android / Java / .NET | 对应 `apple` / `android` / `java` / `managed` toolset；外部反编译器按 capabilities 核实，不把未安装视为整个工具链不可用 |
| 版本差异 | `app_graphs_compare`、`app_function_versions_compare`、`app_builds_line_up`；歧义匹配保留 unknown |
| 网页复刻 | `web_site_capture`、`web_page_states_capture`、`web_walkthrough_check`、`web_pixels_compare`；浏览器选型与后台授权遵守宿主规范 |
| 行为重建覆盖 | `app_ledger_build` → `app_coverage_evaluate` / `app_rebuild_claim_check` |

长调查按官方 skill 使用 `core_investigation_show` / `core_session_show` 恢复，再维护 brief、plan、可证伪 hypothesis、带证据 finding、unknown 和 handoff。大结果复用 `core_evidence_browse` 或 `evidence://<id>` 分页，不重跑。`stale_revision` 先重新读取再合并，不盲重试覆盖别人的进度。事实分 observed / derived / inferred；没有证据的仍是待验证假设。

## 复刻而非只生成代码

1. **Study**：固定目标版本、授权范围和目标哈希；记录入口、输入 / 输出、布局、状态、失败分支与副作用。网页覆盖多宽度、菜单 / 弹窗 / tab，不仅截首页。
2. **Build**：从行为规格实现，优先现有组件与技术栈。原始证据与新实现分开；标志、图片、文本的复用另核授权。构建代理、依赖安装、项目写入和外部 API 都有副作用；自动重建不是默认只读命令。
3. **Check**：在相同输入、页面宽度、状态与环境下对照原目标；同时验证可构建、业务输出、交互、截图和错误分支。台账每个 expectation 有 owner、证据、用例与 passing check；`ready`、构建通过或截图相似都不能单独证明业务一致。
4. **Refine**：按差异修复并重新验收。`craft.json`、`checks/`、`investigation.cany/` 和 `inbox/` 保存进度；继续原项目，避免每次新建导致历史与额度丢失。完成标准以用户范围为准；App / 游戏的行为检查在上游仍为 partial，手工补足并报告未知项。

确需自动重建时先核实 `rebuild --help` 与 `ai list`，显式选已获授权的 backend、预算和绝对输出目录：

```bash
craft-anything-cli --clean-room rebuild "$REA_TARGET" "$REA_REQUEST" \
  --project-folder "$REA_OUTPUT_DIR" --backend "$REA_BACKEND" --rounds 1

craft-anything-cli rebuild "$REA_TARGET" "$REA_REQUEST" \
  --continue-in "$REA_OUTPUT_DIR" --backend "$REA_BACKEND"
```

`--existing edit` 会原地改已有文件，使用前备份并确认范围；`start-from` 把原文件作为材料，在 `app/` 下构建。`--resume` 配合 `--continue-in` 恢复中断且忽略 request，不拿它提交新需求。`--unattended` 会选问题的第一项并拒绝审批，不能用来替用户决定业务方案；`--allow-run` 不默认添加；`--generate-assets` 需要付费 fal.ai key，不自动开启。宿主若禁止自动外派，保持手工 Study / Check + 当前执行者实现，不调用 `rebuild` 绕过限制。

MCP 的 `rebuild_start` 在当前服务内后台执行，用 `rebuild_status` / `project_show` 查状态，以 `project_inbox_answer` 回答待决问题；`rebuild_check` 需要运行中的 rebuild 上下文，不能当独立的通用比较命令。暂停用 `rebuild_stop` 保留成果，结束检查该任务创建的浏览器、preview 与子进程，不碰别的会话。

## 已核实与未核实

- `2026-11-09` 本机 CLI `0.3.0` 的帮助、315 项命令表与 capabilities 已读取；未改 MCP 注册或全局设置。
- 对系统自带二进制做静态 triage，仅验证解析与证据输出，不执行目标；这不是全工具或自动复刻验收。
- 快照 `docs/tool-status.md` 的 Verified / Partial / Unverified 是**上游审计声明**，不是本次实测。上游仍为 early alpha；外部引擎、真实网页、设备与构建代理按任务分别验证。

更新时重新固定提交，保持上述 13 个文件（90,888 字节）内容原样及 PLAYBOOK 路径映射，同步 `SHA256SUMS`、本索引和主 skill / 博客说明。运行 `scripts/verify-reference-snapshots.py --skill-dir "$REA_SKILL_DIR"` 和 skill-creator 的 `quick_validate.py`；`REA_SKILL_DIR` 设为本 skill 绝对路径。不要运行快照里的安装命令作为资料融合步骤。
