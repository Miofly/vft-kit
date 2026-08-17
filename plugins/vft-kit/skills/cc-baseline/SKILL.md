---
name: cc-baseline
description: Use when 用户要求核对本机 Claude Code / CC 装配基线，例如“cc-baseline”“cc-doctor”“工具链体检”“环境自检”“换机器后核对”“重装后哪些没恢复”，或询问 CLI、MCP、插件、Agent Skills、权限、系统配置与全局规范是否齐全。支持只读核对必需项和可选项；传入 --health 时额外实连核心 MCP。
---

# cc-baseline

核对 Claude Code 的本机装配状态。`scripts/check.sh` 是检查项和修复命令的唯一真相来源；不要在本文复制脚本实现细节。

## 执行

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/cc-baseline/scripts/check.sh
```

需要验证 MCP 实际连接时：

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/cc-baseline/scripts/check.sh --health
```

脚本本身只读。退出码为 0 表示必需项齐全，为 1 表示存在必需项缺失；可选项不影响退出码。

## 回报与修复

- 用“项 | 作用”表格回报缺失项，不向用户倾倒脚本中的长修复命令。
- 用户确认补齐后，执行对应检查行给出的命令并重跑检查。
- Ponytail 缺失和 Caveman 默认 full 缺失已获长期授权，可直接补齐；其他项目先回报。
- MCP、插件或全局规范变更后提醒用户新开 Claude Code 会话。

## 基线

| 类别 | 必需 | 可选 |
|---|---|---|
| CLI | node、npm、claude、codegraph | rtk、brew、jq、gh |
| npm | `@danielsogl/lighthouse-mcp` | - |
| MCP | codegraph、lighthouse-mcp | - |
| 插件 | superpowers、skill-creator、code-review、frontend-design、playwright、typescript-lsp、jdtls-lsp、claude-md-management、context-mode、ponytail、caveman、gsap-skills | claude-hud、context7、vercel、grill-me、understand-anything、diagram-design、pm-skills |
| Agent Skills | Emil 的 animate、review-animations、apple-design | AnySearch、Emil 其余 7 项 |
| 系统 | bypassPermissions、信任目录、CodeGraph 白名单、关闭自动更新、全局 CLAUDE.md | RTK hook、claude-hud 状态栏、CC Switch、项目 memory 目录 |
| 全局规范 | 中文回复、可点短链、压缩取舍、代理兜底、多 Agent 并行 | context7 / AnySearch 已安装时才检查对应调用规则 |

Claude Code 2.1.59 起默认提供 auto memory，项目记忆位于 `~/.claude/projects/<project>/memory/`。不要再叠加 `remember` 插件或 agentmemory MCP；只有用户明确需要外部向量检索服务时才单独评估。

## 可选安装

只在用户明确选择时安装：

```bash
# AnySearch：同时配置 API key 和全局调用规则
bash ${CLAUDE_PLUGIN_ROOT}/skills/cc-baseline/scripts/install-anysearch.sh

# PM 工作流：9 个插件，适合 PRD、产品发现、战略与上线规划
bash ${CLAUDE_PLUGIN_ROOT}/skills/cc-baseline/scripts/install-pm-skills.sh

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

## 约束

- CodeGraph 以 CLI 可执行为准；新项目用 `codegraph init`，增量刷新用 `codegraph sync`，完整重建用 `codegraph index -f`。
- RTK 未安装或未启用 hook 时只提示；hook 已启用但缺少 `cat/diff/find/grep/curl/head/wc` 豁免时才算故障。
- 插件检查读取 `installed_plugins.json`，覆盖 user、project 和 local scope。
- `--health` 只实连 codegraph、lighthouse 和 Playwright，不启动额外常驻服务。
