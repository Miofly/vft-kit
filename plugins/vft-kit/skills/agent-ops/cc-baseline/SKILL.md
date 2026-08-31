---
name: cc-baseline
description: Use when 用户要求核对本机 Claude Code / CC 装配基线，例如“cc-baseline”“cc-doctor”“工具链体检”“环境自检”“换机器后核对”“重装后哪些没恢复”，或询问 CLI、MCP、插件、Agent Skills、权限、系统配置与全局规范是否齐全。执行时自动确保 Caveman 默认 full，再只读核对必需项和可选项；传入 --health 时额外实连核心 MCP。
---

# cc-baseline

核对 Claude Code 的本机装配状态。`scripts/check.sh` 是检查项和修复命令的唯一真相来源；不要在本文复制脚本实现细节。

## 执行

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/agent-ops/cc-baseline/scripts/run.sh
```

需要验证 MCP 实际连接时：

```bash

bash ${CLAUDE_PLUGIN_ROOT}/skills/agent-ops/cc-baseline/scripts/run.sh --health
```

`run.sh` 先保证 RTK 可用（缺失时 Homebrew 安装）并把 RTK 的 `PreToolUse` Bash hook 幂等补进 `~/.claude/settings.json`（`rtk hook claude`，装了才会自动压缩 Bash 输出），再幂等安装或更新并启用 Caveman 插件，把 `~/.config/caveman/config.json.defaultMode` 固定为 `full`，最后调用只读的 `check.sh`。退出码为 0 表示必需项齐全，为 1 表示存在必需项缺失；可选项不影响退出码。

启动 skill 后立即新建一个子 Agent，与主线程的 baseline 检查并行。子 Agent 只读比较 `claude --version` 与 `npm view @anthropic-ai/claude-code version --registry=https://registry.npmjs.org`，按 SemVer 数字段（禁止字符串排序）判断 Claude Code CLI 是否有新版本；**不核对插件版本**（用户明确不需要，也不提示）。主线程完成检查后收集其结果：CLI 有新版本时列出“Claude Code｜当前版本｜最新版本”，询问用户是否更新；无新版本时只报告已是最新。本地或上游命令失败、输出为空、版本无法解析时必须报告“无法判断”，不得当作已是最新。子 Agent 不可用时由主线程完成同一只读检查，不阻塞 baseline。

## 回报与修复

- 用“项 | 作用”表格回报缺失必需项；**未安装的可选项也必须一并列出**（项 | 作用 | 适合场景），让用户知道还有哪些可装，装不装由用户选。不向用户倾倒脚本中的长修复命令。
- 用户确认补齐后，执行对应检查行给出的命令并重跑检查。
- RTK（含其 PreToolUse hook）、Ponytail 和 Caveman 默认 full 缺失已获长期授权，可直接补齐；其他项目先回报。
- MCP、插件或全局规范变更后提醒用户新开 Claude Code 会话。

## 基线

> 下表是**概览**，具体项以 `check.sh` 实际输出为准（新增检查项时它会先于本表变化）。

| 类别 | 必需                                                                                                                                          | 可选 |
|---|---------------------------------------------------------------------------------------------------------------------------------------------|---|
| CLI | node、npm、claude、rtk、codegraph、code-review-graph                                                                                             | brew、jq、gh |
| npm | `@danielsogl/lighthouse-mcp`                                                                                                                | - |
| MCP | codegraph、code-review-graph、lighthouse-mcp                                                                                                  | - |
| 插件 | superpowers、skill-creator、code-review、frontend-design、playwright、typescript-lsp、jdtls-lsp、context-mode、ponytail、caveman、gsap-skills | claude-hud、context7、grill-me、understand-anything、diagram-design、pm-skills |
| Agent Skills | Emil 的 animate、review-animations、apple-design                                                                                               | AnySearch、Emil 其余 7 项 |
| 系统 | RTK hook（PreToolUse Bash 自动压缩）、bypassPermissions、bypass 警告已接受、`~` 目录已信任、CodeGraph 白名单、关闭自动更新、Codex 自动注入 `OPENAI_API_KEY`、全局 CLAUDE.md、项目 memory 目录 | claude-hud 状态栏、CC Switch |
| 全局规范 | 中文回复、可点短链、压缩取舍、代理兜底、多 Agent 并行、CodeGraph 自动初始化、Code Review Graph 优先                                                                                         | context7 / AnySearch / context-mode 已安装时才检查对应调用规则（各 1 项） |

Claude Code 2.1.59 起默认提供 auto memory，项目记忆位于 `~/.claude/projects/<project>/memory/`。不要再叠加第三方记忆插件或记忆类 MCP；只有用户明确需要外部向量检索服务时才单独评估。

## 可选安装

只在用户明确选择时安装：

```bash
# AnySearch：同时配置 API key 和全局调用规则
bash ${CLAUDE_PLUGIN_ROOT}/skills/agent-ops/cc-baseline/scripts/install-anysearch.sh

# PM 工作流：9 个插件，适合 PRD、产品发现、战略与上线规划
bash ${CLAUDE_PLUGIN_ROOT}/skills/agent-ops/cc-baseline/scripts/install-pm-skills.sh

# Understand Anything：首次全量分析耗 token，适合陌生大仓和新人导览
claude plugin marketplace add Egonex-AI/Understand-Anything
claude plugin install understand-anything@understand-anything

# Diagram Design：专业架构图、流程图和时序图
claude plugin marketplace add cathrynlavery/diagram-design
claude plugin install diagram-design@diagram-design
```

Claude Code 会话中执行 marketplace 和 install 时分开发送，避免前一条配置尚未刷新。

Emil 动效 skills：

```bash
npx skills add emilkowalski/skills \
  --skill animate \
  --skill review-animations \
  --skill apple-design \
  --agent claude-code --global --yes
```

`animation-vocabulary`、`ask-sonner`、`emil-design-eng`、`find-animation-opportunities`、`improve-animations`、`pick-ui-library`、`prototype` 按项目安装，不自动补齐。

## 自检测试

`scripts/test-*.sh` 共 7 个，全部用 `mktemp` 造隔离的假 `HOME` 与假 `PATH` 运行，**不碰真实环境、不装任何东西**。改动 `check.sh` / `run.sh` 后必跑：

```bash
cd ${CLAUDE_PLUGIN_ROOT}/skills/agent-ops/cc-baseline/scripts
for t in test-*.sh; do bash "$t" >/dev/null 2>&1 && echo "✓ $t" || echo "✗ $t"; done
```

覆盖：`run.sh` 的安装顺序 / 参数转发 / 退出码传播、RTK 二进制与 hook 的幂等安装、Caveman 默认 full、codegraph 与 code-review-graph 与 Emil skills 的基线判定、RTK hook 缺失判为必需项。

> 测试靠环境变量注入 mock（`RTK_SCRIPT` / `CAVEMAN_SCRIPT` / `CHECK_SCRIPT`），所以 `run.sh` 里这三个路径变量**必须保持 `${VAR:-默认值}` 形式**；写成硬编码会让 mock 注入失效、测试报出误导性的「exit code not propagated」。

## 约束

### 改动纪律

- 发现更简单且等价的方案时，明确提出并采用。
- 只修改与请求或必要联动直接相关的文件，保持现有风格。
- 不重构未损坏的代码；不要顺手整理相邻注释、格式或死代码。
- 只清理本次修改造成的孤儿 import、变量、函数、测试和引用。

- CodeGraph 以 CLI 可执行为准；新项目用 `codegraph init`，增量刷新用 `codegraph sync`，完整重建用 `codegraph index -f`。
- 所有代码审查优先通过 code-review-graph MCP 获取最小上下文、影响半径和相关测试，再按结果读取源码；图谱首次建立或完整重建用 `code-review-graph build`，日常刷新用 `code-review-graph update`，状态检查用 `code-review-graph status`。
- 插件检查读取 `installed_plugins.json`，覆盖 user、project 和 local scope。
- `--health` 只实连 codegraph、code-review-graph、lighthouse 和 Playwright，不启动额外常驻服务。
- 装了 context-mode 时，发 HTTP 一律走 `ctx_execute` / `ctx_fetch_and_index`。它的 PreToolUse hook 会拦下「响应体打到 stdout」的 curl/wget 并渲染成红色 Error——那是设计好的路由提示，不是故障，插件也没有静默开关；被拦一次就白费一轮工具调用。非要用 Bash curl 就写成 hook 放行的形态：`-s`（wget `-q`）+ 输出落文件，且不能是 `-o -` / `/dev/stdout`，不能带 `-v`。
- 文本检索一律走 `rg` 或 `/usr/bin/grep`（绝对路径）。裸 `grep` 会被 Claude Code shell 快照注入的 `grep` shell 函数劫持（转发 claude 二进制内置 ugrep，本机派发坏，报 `error: unknown option '-G'`）；与 rtk 无关——rtk hook 不改写 grep。例：`(rg -l "关键字" dir 2>/dev/null || /usr/bin/grep -rl "关键字" dir)`。`scripts/*.sh` 内部 grep 跑在子 shell，不受该函数影响。
