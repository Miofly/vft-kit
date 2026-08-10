---
name: codex-baseline
description: 一键核对本机 Codex CLI 是否符合「装配基线」——核对 CLI、dangerous full access、项目信任、hooks、Memories、稳定版 multi-agent、Playwright、CodeGraph/Lighthouse/OpenAI Docs MCP、Context7/Vercel 可选 MCP、GitHub/Superpowers/Build Web Apps/Ponytail/Context Mode 插件、Caveman/GSAP/AnySearch/Grill-me skills、RTK Codex 指令、图片生成 CLI 与全局 AGENTS 规范。MCP 与插件检查读取 Codex 合并后的真实状态，覆盖用户和项目 scope；支持 `--health` 实连 stdio MCP。用户说"codex-baseline"、"检查 codex 基线"、"codex 体检"、"codex-doctor"、"codex 权限配置对吗"、"dangerously bypass 有没有落实"、"codex 插件/MCP 全不全"、"换机器后核对 codex"等场景时触发。
---

# codex-baseline —— Codex 装配基线核对

对照本机 Codex CLI 装配基线逐项核对安装、配置、插件、全局规范与图片生成 CLI 状态，缺什么给什么修复命令。本基线不要求安装 Codex App，也不检查 App/runtime 专属的 MCP 或内置插件。

**常设自动操作：** 每次执行时同步 CC-Switch 认证、准备 imagegen CLI，并在 `~/.codex/AGENTS.md` 幂等维护 imagegen 与 `Caveman 默认 full` 两个托管块。Caveman 托管块让每个新会话从首条回复起自动采用 full 档，不再要求手动 `/caveman`；同时把共享配置 `~/.config/caveman/config.json` 的 `defaultMode` 固定为 `full`。这是用户的永久授权，不要再次询问；任何输出都不得包含完整 Key。除下述 Ponytail 例外外，其他检查全部只读，不自动修复。

**Ponytail 自动补齐例外：** 只要本次检查报 `ponytail@ponytail` 缺失，直接依次运行 `codex plugin marketplace add DietrichGebert/ponytail`、`codex plugin add ponytail@ponytail`；两条分开执行。安装后提示用户在新会话中打开 `/hooks` 审查并信任生命周期 hooks。其余缺失项仍先汇报，不自动安装。

**AnySearch 是可选项：** 用户明确选择安装时运行 `bash ${CODEX_PLUGIN_ROOT:-${VFT_PLUGIN_ROOT:-.}}/skills/codex-baseline/scripts/install-anysearch.sh`。脚本安装到 `~/.codex/skills/anysearch`、注册 API key，并补 `~/.codex/AGENTS.md` 调用规范。

基线里最核心的一项是 dangerous full access：等价于启动参数 `--dangerously-bypass-approvals-and-sandbox`，持久配置写在 `~/.codex/config.toml`：

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"
```

## 怎么用

直接跑统一入口：

```bash
bash ${CODEX_PLUGIN_ROOT:-${VFT_PLUGIN_ROOT:-.}}/skills/codex-baseline/scripts/run.sh
```

需要额外验证 MCP 进程能完成初始化握手时加 `--health`：

```bash
bash ${CODEX_PLUGIN_ROOT:-${VFT_PLUGIN_ROOT:-.}}/skills/codex-baseline/scripts/run.sh --health
```

输出是分组的 `✓` / `✗` / `○` / `⊘` 清单 + 汇总。退出码：必需项齐全=0，有必需项缺失=1（可选项或声明为刻意不装的项目不影响退出码）。

- `✓` 绿 = 已装/已启用
- `✗` 红 = **必需**项缺失，行尾直接给修复命令
- `○` 黄 = 可选项缺失，不算故障
- `⊘` 灰 = 已通过 `CODEX_BASELINE_SKIP` 声明为刻意不装，不算故障

只有必需项与本机既有方案互斥时才使用 `CODEX_BASELINE_SKIP`；它按逗号分隔，并对检查项标签做子串匹配。例如：`CODEX_BASELINE_SKIP="lighthouse-mcp,GSAP" bash ${CODEX_PLUGIN_ROOT:-${VFT_PLUGIN_ROOT:-.}}/skills/codex-baseline/scripts/run.sh`。普通缺失项不要跳过。

跑完把结果回报给用户。有 `✗` 时用「项 | 作用（缺了有什么影响）」表格说明，不要把脚本里的长修复命令整段倾倒给用户；用户确认补齐后，再按脚本行尾给出的命令执行并重跑核对。

跑过一次后，后续生图直接调用包装命令即可：

```bash
codex-imagegen generate \
  --model gpt-image-2 \
  --prompt "一个蓝色方块，白色背景，极简测试图，无文字" \
  --quality low \
  --size 1024x1024 \
  --out output/imagegen/test.png \
  --force
```

`codex-imagegen` 会在启动子进程时按顺序注入认证：优先使用当前环境的 `OPENAI_API_KEY` / `OPENAI_BASE_URL`；缺失时读取 macOS Keychain 里的 `CC_SWITCH_CODEX_API_KEY` / `CC_SWITCH_CODEX_BASE_URL`；再缺失时回退读取 `~/.codex/auth.json` 的 `OPENAI_API_KEY`。Key 只进入当前 imagegen 子进程，不写入包装脚本正文，也不在输出里打印。

## 检查项

| 类别 | 检查项 | 数据来源 |
|---|---|---|
| CLI 工具 | `codex` / `node` / `npm` / `git` / `codegraph` 必需；`brew` / `jq` / `gh` / `vercel` / RTK 可选 | `command -v` + `~/.codex/RTK.md` |
| dangerous full access | `approval_policy = "never"` / `sandbox_mode = "danger-full-access"` / hide full-access warning | `~/.codex/config.toml` |
| 项目与 hooks | `features.hooks = true` / `features.memories = true` / `multi_agent` 实际启用 / `/` 或常用代码根已 trust；集中管版本时可选关闭启动更新检查 | `~/.codex/config.toml` + `codex features list` |
| Playwright MCP | `playwright` stdio server 已配置且未禁用 / Chromium 内核存在 | `~/.codex/config.toml` + Playwright browser cache |
| 代码与审计 MCP | `codegraph` CLI、`lighthouse-mcp` 的 npm 载体，以及两者的注册与启用状态，全部必需 | `command -v` + `$(npm root -g)` + `codex mcp get --json` |
| 文档与部署 MCP | OpenAI Developer Docs 必需；Context7 / Vercel 可选 | `codex mcp get --json` |
| CLI 插件 | github / superpowers / build-web-apps / ponytail / context-mode 必需；GitHub 另检查 `GITHUB_PAT_TOKEN` | `codex plugin list --json`，失败时回退全局 config + cache；环境变量 + `gh auth token` |
| 兼容 Agent Skills | Caveman skill + 全局默认 full 托管块必需；GSAP 官方 8 项 skills 必需；AnySearch 与 Grill-me 可选 | `~/.agents/skills` + `~/.codex/skills` + `~/.codex/AGENTS.md` |
| 系统 skills | openai-docs / imagegen / skill-creator / plugin-creator / skill-installer | `~/.codex/skills/.system` |
| 图片生成 CLI/API | imagegen CLI 脚本 / 专用 venv / `openai` + `pillow` / `codex-imagegen` / `OPENAI_API_KEY` 注入源 | `~/.codex/skills/.system/imagegen` + `~/.codex/venvs/imagegen-cli` + `~/.local/bin/codex-imagegen` |
| 全局规范 | `~/.codex/AGENTS.md` 必须含中文回复 / 可点短链 / 压缩取舍 / 代理兜底 / 多 Agent 并行 / Caveman 默认 full / 生图规则；装了 codegraph、context7、anysearch 后条件检查对应调用规范 | 文件正文 grep + CLI/MCP/skill 安装状态 |
| CC-Switch 认证 | 当前 Codex Key + Base URL 自动同步到 macOS Keychain，并由 `~/.zshrc` 动态注入 | `~/.codex/auth.json` + `~/.codex/config.toml`，必要时回退 `~/.cc-switch/cc-switch.db` |
| 系统辅助工具（可选） | CC Switch App | `/Applications/CC Switch.app` |
| MCP 健康检查（可选） | `--health` 时对已启用的 Playwright、CodeGraph、Lighthouse stdio MCP 发起 `initialize` 握手 | `codex mcp get --json` + 子进程 JSON-RPC |

## 关键实现细节

- **dangerous full access 是必需项**：脚本把 `approval_policy = "never"` 和 `sandbox_mode = "danger-full-access"` 当作硬失败项。它们是 `--dangerously-bypass-approvals-and-sandbox` 的持久配置等价物。
- **只检查纯 CLI 能力**：Codex App、`node_repl`、`browser@openai-bundled` 或 `openai-primary-runtime` 文档类插件都不是必需项；但用户显式启用 `node_repl` 且配置的 command 已不存在时，报 `○` 提示删除或禁用这段陈旧配置。
- **Playwright 必须能启动浏览器**：既检查 `[mcp_servers.playwright]` 的 stdio command 和启用状态，也检查 Chromium 内核；只注册 MCP 但没有浏览器内核仍算缺失。
- **CodeGraph 与 Lighthouse 已与 CC 基线对齐为必需项**：CodeGraph 检查 CLI 是否可执行，Lighthouse 检查全局 npm 载体；两者都检查命令、MCP 注册和启用状态，任一缺失都报 `✗`。
- **MCP 检查覆盖项目 scope**：优先用 `codex mcp get <name> --json` 读取当前目录下 Codex 合并后的实际配置；命令不可用时才回退读取用户级 TOML。
- **OpenAI Docs / Context7 / Vercel 各走原生接入**：OpenAI Docs 是 `openai-docs` system skill 的必需数据源；Context7 用官方 npm MCP；Vercel 用官方 OAuth HTTP MCP。
- **Lighthouse 全局 npm 包查目录，不跑 `npm ls -g`**：直接检查 `$(npm root -g)/@danielsogl/lighthouse-mcp`。
- **CodeGraph 以 CLI 能力为准**：官方 `install.sh` standalone 安装或 npm 安装均可，只要 `codegraph` 可执行即合格。新项目运行 `codegraph init`，增量刷新运行 `codegraph sync`，完整重建运行 `codegraph index -f`；不存在 `codegraph update` 子命令。
- **全局 AGENTS 是个人基线的必需项**：中文回复、可点短链、压缩取舍、代理兜底和多 Agent 并行均为硬检查。codegraph CLI 已装时额外要求写明 `init` / `sync` / `index -f`，并拒绝旧的 `codegraph update` 规范；context7 MCP 已启用或 anysearch skill 已装时，额外要求对应调用场景规范。
- **多 Agent 与 CC 基线效果等价、编排接口不同**：Codex 用 `spawn_agent` 等协作工具扇出独立子任务、主 Agent 汇总结果。基线同时要求 `codex features list` 的 `multi_agent` 实际状态为 `true`，以及 AGENTS.md 写明自动触发、并发编排、文件所有权和最终整体验证；只有“可以并行”一句弱提示不算合格。Codex 子 Agent 与主 Agent 共享工作区，因此必须给各 Agent 分配互不重叠的文件或问题边界，主 Agent 负责冲突处理与最终验证。
- **Claude 插件映射到 Codex 原生能力**：frontend-design → `build-web-apps@openai-api-curated`；remember → `features.memories = true`；code-review → `codex review` + GitHub 插件；playwright → Playwright MCP；skill-creator → system skill。
- **Ponytail 使用其官方 Codex 插件**：安装后同时获得 skills 与 Codex lifecycle hooks；缺失时按上面的常设授权自动补齐。
- **Caveman 在 Codex 使用 skill + 全局托管规则**：官方 `npx skills add JuliusBrussee/caveman -a codex` 只提供 skill，官方安装表仍要求每会话手动 `/caveman`；仓库根 `.codex/hooks.json` 不是可安装插件清单。基线因此用 `scripts/install-caveman-default.sh` 向全局 `AGENTS.md` 写入可幂等替换的 full 规则块，实现真正默认开启，同时保留 `stop caveman` / `normal mode` 当前会话关闭能力。GSAP 仍检查官方 8 个 skill 是否完整，Grill-me 为可选全局 skill。
- **RTK 只迁移 Codex 支持的模式**：检查 `rtk init --codex --global` 生成的 `RTK.md` 与 AGENTS 引用，不检查 Claude 专属 `rtk hook claude` 和压缩豁免。
- **Memories 是 remember 的原生映射**：要求 `[features] memories = true`；持久规则仍放 AGENTS.md，memories 只承担跨会话回忆层。
- **`--health` 做真实 stdio 握手**：`run.sh` 将参数透传给 `check.sh`；检查器通过 `codex mcp get <name> --json` 取得实际启动配置，再发送 MCP `initialize` 请求。冷启动上限 60 秒，结束时回收完整进程组，避免 `npx` 留下 MCP 子进程。默认不实连。
- **认证同步是自动修复例外之一**：`run.sh` 先调用 `sync-cc-switch-openai-env.sh`，把活动 Key/Base URL 写入同名 Keychain 项，并幂等维护 `~/.zshrc` 托管块；不会把明文 Key 写进文件。同步条件不满足时只警告并继续后续流程。
- **图片生成 CLI 前置流程自动完成**：`run.sh` 随后调用 `prepare-imagegen-cli-env.sh`，准备 `~/.codex/venvs/imagegen-cli`，安装 `openai` 与 `pillow`，并创建 `~/.local/bin/codex-imagegen`。后续生图不再需要手动建 venv、安装 SDK 或处理 Key 注入。
- **`codex-imagegen` 只对子进程注入 Key**：包装命令运行时从当前环境、macOS Keychain、`~/.codex/auth.json` 逐级找 `OPENAI_API_KEY`；如果找到 Base URL 也只导出给 imagegen 子进程。包装脚本本身不含明文 Key。
- **普通生图请求直接走 CLI/API**：`run.sh` 调用 `install-imagegen-agents-rule.sh`，在 `~/.codex/AGENTS.md` 写入托管规则，要求“帮我生成一个图片”这类请求直接使用 `codex-imagegen generate` / `codex-imagegen edit`。不先解释 imagegen skill、内置工具可用性或 CLI 探测流程；除非命令失败或用户询问流程，否则只做 prompt 构造、CLI 执行、输出文件检查与路径回报。
- **其余检查只读**：除认证、imagegen 与 Caveman 托管块外，本 skill 不写 `~/.codex/config.toml`，只打印 `codex -c ...` 或可粘贴的配置片段。
- **插件检查优先读合并态**：`codex plugin list --json` 能覆盖用户、项目、本地及 runtime 来源；只有命令不可用时才回退用户级 enabled + cache 检查。
- **GitHub 插件还需要认证环境**：安装并启用插件后检查 `GITHUB_PAT_TOKEN` 是否非空；若 `gh auth token` 可用，可在 shell 启动文件中动态导出 `GITHUB_PAT_TOKEN="$(gh auth token 2>/dev/null)"`，复用 GitHub CLI 登录态且不落盘明文 token。
- **不迁移 Claude 专属机制**：claude-hud/statusLine、Claude permissions 白名单和 typescript-lsp/jdtls-lsp 插件没有稳定 Codex 等价物，因此不纳入；Context Mode 使用 `context-mode@context-mode` Codex 插件并作为必需项检查。本基线仅把默认自动更新关闭作为集中管版本场景的可选提示。
- **Codex 配置是 TOML**：脚本用 `awk`/`grep` 做轻量检查，不引入额外依赖；`jq` 只作为可选工具提示。
- **改完配置要重启 Codex 会话**：当前会话的权限与 system prompt 已经在启动时确定，配置落盘后通常要新开会话才稳定生效。
