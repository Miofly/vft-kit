# REAP：REA-Prompts 完整资料与任务路由

完整收录 [JoasASantos/REA-Prompts](https://github.com/JoasASantos/REA-Prompts)，作为本 REA skill 的调查模板库。原始内容完整保存在 `upstream/`；展开版仅把 26 个 `Skills/*/SKILL.md` 改名为 `PROMPTS.md`，避免单 skill 打包拒绝多个 `SKILL.md`，其余路径和全部字节不变。不拆成新的独立插件，不自动运行上游安装器。

## 来源与完整性

- 仓库：`https://github.com/JoasASantos/REA-Prompts`
- 分支：`main`
- 固定提交：`ccb02b89721dd7d466beb17004a89d6bc25f5b02`
- 上游提交时间：`2026-10-26T00:00:09-03:00`
- 收录日期：`2026-11-04`
- 全量范围：**31 个受跟踪文件，180,217 字节**，包括 26 份 `Skills/*/SKILL.md`、完整 README、合并系统提示词、两个安装脚本及 LICENSE。
- 许可：[MIT，Copyright (c) 2025 Joas Antonio dos Santos](upstream/LICENSE)，原样保留。
- 可按需读取的展开文件在 `upstream/`；[SHA256SUMS](SHA256SUMS) 按展开路径覆盖所有 31 个文件。原始路径将 `PROMPTS.md` 对应回 `SKILL.md`，内容哈希与上游相同。从 `upstream/` 工作目录执行 `shasum -a 256 -c "$REA_SKILL_DIR/references/rea-prompts/SHA256SUMS"`；`REA_SKILL_DIR` 由使用者设置为本 skill 的绝对路径。

## 如何与现有 REA 融合

1. **先选调查模板，再选工具参考**：按下表读取对应 REAP pack 的完整内容；实际工具参数、分页、provider 与恢复规则，仍以本 skill 的 REA 官方参考及当前工具 schema 为准。REA-Prompts 是调查模板库，不是另一个分析引擎。
2. **填实输入**：将模板中的 `<FEATURE>`、`<PATH>`、版本、函数、平台等占位符替换为用户实际对象。未提供路径或授权范围时不编造。每次优先追踪一个功能，整体复刻可按功能逐个建立可验收清单。
3. **先静态，后运行时**：先找入口、调用链、数据与副作用，附文件/函数/地址及 Evidence；把事实、推断、未知分开。确需运行时才在授权环境观察，恶意样本不在宿主直接执行。
4. **以交付物结束**：根据模板产出行为规格、可读伪代码、数据结构、协议说明、移植计划或最小重建，并用原始程序的同输入/输出及边界用例对照。Go/Rust 恢复的是结构与逻辑，不声称拿回原始源码。
5. **能力受限时如实降级**：模板提到的工具未安装、provider 不支持或当前版本改名时，先核实可用能力；不要为套模板伪造函数地址、运行结果或成功状态。

### 两类资料不要混用

- 本资料库的 REAP 模板用于安排实际 REA 调查；按用户任务选择和改写，不整篇当宿主系统指令加载。
- `jailbreaks` 是独立的提示词研究样本库；不要把其中规则覆盖文本拼入 REAP 调查提示词。
- 内核、漏洞、反作弊、DMA、DRM、保护器和恶意样本相关 pack 保留上游授权与隔离边界，只用于明确授权的分析、防御、互操作或 CTF。收录文件不意味着所有操作已获授权。

## 26 份 pack 全量路由

路径均在快照 `upstream/Skills/`，按当前任务读匹配的一份；不是要求另行调用同名 skill。

| 任务 | 完整 pack | 配合本 skill 的 REA 官方参考 |
| --- | --- | --- |
| 00 安装与连接核验 | [reap-00-install-and-verify](upstream/Skills/reap-00-install-and-verify/PROMPTS.md) | connection-and-recovery |
| 01 入门、陌生应用总览、CSV 导出追踪 | [reap-01-getting-started](upstream/Skills/reap-01-getting-started/PROMPTS.md) | 按目标选 provider |
| 02 功能、按钮到副作用、规则恢复 | [reap-02-feature-tracing-any-program](upstream/Skills/reap-02-feature-tracing-any-program/PROMPTS.md) | javascript-applications / native-and-artifacts |
| 03 原生二进制、函数、文件格式、序列化协议 | [reap-03-native-binary-exploration](upstream/Skills/reap-03-native-binary-exploration/PROMPTS.md) | native-and-artifacts |
| 04 应用/功能行为复刻与一致性验证 | [reap-04-software-and-feature-cloning](upstream/Skills/reap-04-software-and-feature-cloning/PROMPTS.md) | evidence-workflows / runtime-observation |
| 05 游戏逻辑、难度、引擎与离线单机 mod | [reap-05-games](upstream/Skills/reap-05-games/PROMPTS.md) | native-and-artifacts / javascript-applications |
| 06 原生游戏移植 WASM、无界面逻辑核心 | [reap-06-game-portability-to-wasm](upstream/Skills/reap-06-game-portability-to-wasm/PROMPTS.md) | native-and-artifacts |
| 07 固件、MCU/IoT、协议及更新机制 | [reap-07-firmware-and-embedded](upstream/Skills/reap-07-firmware-and-embedded/PROMPTS.md) | native-and-artifacts |
| 08 Android APK、JNI、存储与加密、加壳排查 | [reap-08-android](upstream/Skills/reap-08-android/PROMPTS.md) | android-applications / native-and-artifacts |
| 09 内核与驱动、IOCTL、syscall | [reap-09-kernel-analysis](upstream/Skills/reap-09-kernel-analysis/PROMPTS.md) | native-and-artifacts |
| 10 信任边界、输入到 sink、补丁差异、崩溃 | [reap-10-vulnerability-research](upstream/Skills/reap-10-vulnerability-research/PROMPTS.md) | native-and-artifacts / evidence-workflows |
| 11 Electron/JS、IPC、bundle、API、认证、扩展、PWA | [reap-11-electron-and-javascript](upstream/Skills/reap-11-electron-and-javascript/PROMPTS.md) | javascript-applications / runtime-observation |
| 12 反作弊、产品保护、DRM 互操作分析 | [reap-12-anti-cheat-and-protection-research](upstream/Skills/reap-12-anti-cheat-and-protection-research/PROMPTS.md) | native-and-artifacts |
| 13 DMA 原理、样本分析、检测与设备固件研究 | [reap-13-dma-and-hardware-assisted-cheat-research-defensive](upstream/Skills/reap-13-dma-and-hardware-assisted-cheat-research-defensive/PROMPTS.md) | native-and-artifacts |
| 14 保护流程文档、crackme/CTF、保护差异 | [reap-14-software-cracking-research](upstream/Skills/reap-14-software-cracking-research/PROMPTS.md) | native-and-artifacts / evidence-workflows |
| 15 双版本行为与崩溃对比 | [reap-15-version-comparison-and-crash-work](upstream/Skills/reap-15-version-comparison-and-crash-work/PROMPTS.md) | evidence-workflows / javascript-applications |
| 16 长调查续接、复用证据 | [reap-16-long-running-investigations](upstream/Skills/reap-16-long-running-investigations/PROMPTS.md) | evidence-workflows |
| 17 恶意样本、C2 配置、IOC/YARA、阶段链 | [reap-17-malware-analysis](upstream/Skills/reap-17-malware-analysis/PROMPTS.md) | native-and-artifacts |
| 18 去混淆、控制流恢复、字符串与常量解密 | [reap-18-advanced-binary-exploration-and-deobfuscation](upstream/Skills/reap-18-advanced-binary-exploration-and-deobfuscation/PROMPTS.md) | native-and-artifacts |
| 19 内核与驱动漏洞、防御与隔离复现 | [reap-19-kernel-and-driver-exploitation-research](upstream/Skills/reap-19-kernel-and-driver-exploitation-research/PROMPTS.md) | native-and-artifacts / evidence-workflows |
| 20 高级功能重建、状态机、数据与协议兼容 | [reap-20-advanced-software-cloning-and-feature-reconstruction](upstream/Skills/reap-20-advanced-software-cloning-and-feature-reconstruction/PROMPTS.md) | javascript-applications / evidence-workflows |
| 21 保护器、虚拟化、混淆与反篡改研究 | [reap-21-protector-and-obfuscator-research](upstream/Skills/reap-21-protector-and-obfuscator-research/PROMPTS.md) | native-and-artifacts |
| 22 Go/Rust 元数据、类型、调用约定与逻辑恢复 | [reap-22-go-and-rust-binary-source-recovery](upstream/Skills/reap-22-go-and-rust-binary-source-recovery/PROMPTS.md) | native-and-artifacts |
| 提示词编写原则 | [reap-prompt-writing-tips](upstream/Skills/reap-prompt-writing-tips/PROMPTS.md) | evidence-workflows |
| 上游主索引 | [reap-prompts](upstream/Skills/reap-prompts/PROMPTS.md) | 按本页路径读，不另注册 |
| 不确定从哪开始的通用模板 | [reap-wildcard](upstream/Skills/reap-wildcard/PROMPTS.md) | 按目标选 provider |

## 其余完整原文件

- [README.md](upstream/README.md)：完整项目说明与所有场景模板，适合查跨 pack 的上下文。
- [system_prompt.md](upstream/system_prompt.md)：上游合并版系统提示词；完整保留，默认不整体加载。
- [setup.sh](upstream/setup.sh)、[setup.bat](upstream/setup.bat)：上游安装器，仅归档。其用途是复制 skills 到宿主配置，不因本次融合而运行；本 skill 已有入口，无需重复安装。
- [LICENSE](upstream/LICENSE)：上游 MIT 原文。

## 更新与验收

按固定提交的 Git 树更新完整展开版，同步全部新增、修改和删除；展开时将 `Skills/*/SKILL.md` 映射为 `Skills/*/PROMPTS.md`，避免嵌套技能入口。上游主索引与安装脚本仍原样保留，其中的 `SKILL.md` 路径对应原始归档；本 skill 调用展开版时使用本页路由。

同时更新提交、文件数、字节数、路由及 SHA-256。逐字节验证固定提交原始路径与 31 个展开文件，检查 26 个 pack 都有入口，运行 skill-creator 的 `quick_validate.py`，保留 REA 官方文档与 jailbreaks 快照不变。结构与完整性检查通过只说明融合正确，不代表模板里的每项工具链和真实目标都已测试。
