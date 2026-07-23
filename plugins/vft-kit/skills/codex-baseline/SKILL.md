---
name: codex-baseline
description: 一键核对本机 Codex CLI 是否符合「装配基线」——逐项核对 Codex CLI、Node/npm/git、gh/codegraph 可选工具、Codex dangerous full access 基线（等价 `--dangerously-bypass-approvals-and-sandbox`：`sandbox_mode = "danger-full-access"` + `approval_policy = "never"`）、full access 警告隐藏、项目信任、hooks、Playwright MCP、常用 MCP（codegraph / lighthouse-mcp，可选）、GitHub 与 Superpowers 插件、系统 skills、全局 AGENTS 规范。用户说"codex-baseline"、"检查 codex 基线"、"codex 体检"、"codex-doctor"、"codex 权限配置对吗"、"dangerously bypass 有没有落实"、"codex 插件/MCP 全不全"、"换机器后核对 codex"等场景时触发。
---

# codex-baseline —— Codex 装配基线核对

对照本机 Codex CLI 装配基线逐项核对安装、配置、插件、全局规范与图片生成 CLI 状态，缺什么给什么修复命令。本基线不要求安装 Codex App，也不检查 App/runtime 专属的 MCP 或内置插件。

**常设自动操作：** 每次执行时先把 CC-Switch 当前 Codex 提供商的 API Key 与 Base URL 同步到 macOS 钥匙串，并在 `~/.zshrc` 维护动态读取它们的托管块；随后准备 imagegen CLI 专用 Python venv，安装 `openai`/`pillow`，并写入 `~/.local/bin/codex-imagegen` 包装命令；最后在 `~/.codex/AGENTS.md` 安装“生图直接走 `codex-imagegen`”的全局规则。这是用户对本 skill 的永久授权，不要再次询问；任何输出都不得包含完整 Key。除这三项外，其他检查全部只读，不自动修复。

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

输出是分组的 `✓` / `✗` / `○` 清单 + 汇总。退出码：必需项齐全=0，有必需项缺失=1（可选项缺失不影响退出码）。

- `✓` 绿 = 已装/已启用
- `✗` 红 = **必需**项缺失，行尾直接给修复命令
- `○` 黄 = 可选项缺失，不算故障

跑完把结果回报给用户；有 `✗` 就把对应修复命令一并列出，问用户要不要补齐。

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
| CLI 工具 | `codex` / `node` / `npm` / `git` / `jq` 可选 / `gh` 可选 / `codegraph` 可选 | `command -v` |
| dangerous full access | `approval_policy = "never"` / `sandbox_mode = "danger-full-access"` / hide full-access warning | `~/.codex/config.toml` |
| 项目与 hooks | `features.hooks = true` / `/` 或常用代码根已 trust | `~/.codex/config.toml` |
| Playwright MCP | `playwright` stdio server 已配置且未禁用 / Chromium 内核存在 | `~/.codex/config.toml` + Playwright browser cache |
| 常用 MCP（可选） | `codegraph` / `lighthouse-mcp` stdio server 已配置且未禁用 | `~/.codex/config.toml` |
| CLI 插件 | github / superpowers 启用且 cache 存在 | `~/.codex/config.toml` + `~/.codex/plugins/cache` |
| 系统 skills | openai-docs / imagegen / skill-creator / plugin-creator / skill-installer | `~/.codex/skills/.system` |
| 图片生成 CLI/API | imagegen CLI 脚本 / 专用 venv / `openai` + `pillow` / `codex-imagegen` / `OPENAI_API_KEY` 注入源 | `~/.codex/skills/.system/imagegen` + `~/.codex/venvs/imagegen-cli` + `~/.local/bin/codex-imagegen` |
| 全局规范 | `~/.codex/AGENTS.md` 存在，建议含中文回复 / 可点短链 / 压缩取舍规则 / 外网操作代理兜底 / 生图直接走 `codex-imagegen` | 文件正文 grep |
| CC-Switch 认证 | 当前 Codex Key + Base URL 自动同步到 macOS Keychain，并由 `~/.zshrc` 动态注入 | `~/.codex/auth.json` + `~/.codex/config.toml`，必要时回退 `~/.cc-switch/cc-switch.db` |

## 关键实现细节

- **dangerous full access 是必需项**：脚本把 `approval_policy = "never"` 和 `sandbox_mode = "danger-full-access"` 当作硬失败项。它们是 `--dangerously-bypass-approvals-and-sandbox` 的持久配置等价物。
- **只检查纯 CLI 能力**：不检查 Codex App、`node_repl`、`browser@openai-bundled` 或 `openai-primary-runtime` 文档类插件，避免把桌面端/runtime 能力误报为 CLI 必需项。
- **Playwright 必须能启动浏览器**：既检查 `[mcp_servers.playwright]` 的 stdio command 和启用状态，也检查 Chromium 内核；只注册 MCP 但没有浏览器内核仍算缺失。
- **常用 MCP 只做可选提醒**：`codegraph` 与 `lighthouse-mcp` 对代码结构查询和页面体检有用，但不是 Codex CLI 的硬依赖；缺失或禁用只报 `○`，不影响退出码。
- **外网操作代理兜底是跨工具链规范**：全局 AGENTS 建议写明 GitHub/raw/googleapis、brew/npm/pip 等外网操作连不通或慢得反常时先探本机代理，再用 `curl -x`、`git -c http.proxy` 或环境变量重试；缺失只做可选提醒。
- **认证同步是自动修复例外之一**：`run.sh` 先调用 `sync-cc-switch-openai-env.sh`，把活动 Key/Base URL 写入同名 Keychain 项，并幂等维护 `~/.zshrc` 托管块；不会把明文 Key 写进文件。同步条件不满足时只警告并继续后续流程。
- **图片生成 CLI 前置流程自动完成**：`run.sh` 随后调用 `prepare-imagegen-cli-env.sh`，准备 `~/.codex/venvs/imagegen-cli`，安装 `openai` 与 `pillow`，并创建 `~/.local/bin/codex-imagegen`。后续生图不再需要手动建 venv、安装 SDK 或处理 Key 注入。
- **`codex-imagegen` 只对子进程注入 Key**：包装命令运行时从当前环境、macOS Keychain、`~/.codex/auth.json` 逐级找 `OPENAI_API_KEY`；如果找到 Base URL 也只导出给 imagegen 子进程。包装脚本本身不含明文 Key。
- **普通生图请求直接走 CLI/API**：`run.sh` 调用 `install-imagegen-agents-rule.sh`，在 `~/.codex/AGENTS.md` 写入托管规则，要求“帮我生成一个图片”这类请求直接使用 `codex-imagegen generate` / `codex-imagegen edit`。不先解释 imagegen skill、内置工具可用性或 CLI 探测流程；除非命令失败或用户询问流程，否则只做 prompt 构造、CLI 执行、输出文件检查与路径回报。
- **其余检查只读**：本 skill 不写 `~/.codex/config.toml`，只打印 `codex -c ...` 或可粘贴的配置片段。
- **插件检查分两层**：配置里的 `[plugins."<plugin>@<marketplace>"].enabled = true` 是启用事实；`~/.codex/plugins/cache/<marketplace>/<plugin>/...` 是 cache 落盘事实，两者都要看。
- **Codex 配置是 TOML**：脚本用 `awk`/`grep` 做轻量检查，不引入额外依赖；`jq` 只作为可选工具提示。
- **改完配置要重启 Codex 会话**：当前会话的权限与 system prompt 已经在启动时确定，配置落盘后通常要新开会话才稳定生效。
