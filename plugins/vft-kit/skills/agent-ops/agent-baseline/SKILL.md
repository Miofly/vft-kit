---
name: agent-baseline
description: "核对和维护 Claude Code/CC 或 Codex 通用装配：CLI、MCP、插件、技能、权限、Hooks 和全局规范，以及刷新本地或远端插件缓存、排查技能修改未生效；用于工具链体检、配置排障或换机恢复检查，支持 --health 实连。"
---

# Claude Code / Codex 通用装配基线

先按任务选择路线，再按用户指定的目标工具执行；未指定工具时使用当前宿主。

- 插件刷新、cache 不一致、技能修改未生效或重装插件：只读 [插件维护](references/plugins.md)，执行其中的刷新脚本，不运行完整基线维护。
- CLI、MCP、权限、Hooks、全局规范或整体装配检查：按下表读取宿主基线。只执行选中路线，不同时改动另一宿主。

| 目标 | 流程与检查规范 | 统一执行入口 |
|---|---|---|
| Claude Code / CC | [claude-code.md](references/claude-code.md) | [run.sh](claude-code/scripts/run.sh) |
| Codex CLI | [codex.md](references/codex.md) | [run.sh](codex/scripts/run.sh) |

每条路线的 scripts/check.sh 是检查项和修复命令的唯一来源。通过 run.sh 执行该宿主已有的常设维护，再做检查；需要验证 MCP 连接时传 --health。版本审计、缺失项回报和修复授权按对应 reference 执行。

公共层接受环境变量和宿主配置，不包含个人账号、仓库、数据库或凭据。私有默认值及资产核对由调用方的私有 skill 追加；调用私有入口时不要再重复运行公共 run.sh。

两宿主的认证、权限、Hooks、插件和配置格式各自维护；已安装的 Claude 插件不自动映射为 Codex 插件。新加能力只改适用的路线。

认证后远端业务动作遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)；本机装配检查按宿主流程执行。密钥不进入 argv、日志或报告。
