---
name: agent-baseline
description: "维护 Claude Code/CC 与 Codex 装配：工具链体检、CLI/MCP/插件/Hooks 配置、缓存刷新；备份恢复或清理 CC 环境，添加或修正 CC Switch 供应商与协议。用于配置排障、换机重装，支持 --health 实连。"
---

# Claude Code / Codex 通用装配基线

先按任务选择路线，再按用户指定的目标工具执行；未指定工具时使用当前宿主。

- 插件刷新、cache 不一致、技能修改未生效或重装插件：只读 [插件维护](references/plugins.md)，执行其中的刷新脚本，不运行完整基线维护。
- CC 配置备份、恢复、迁移或清理残留：只读 [备份 / 恢复 / 清理](references/backup.md)，执行 `backup/scripts/`；清理须展示范围并由用户交互确认。恢复后只做只读核对，不顺带运行完整维护。
- CC Switch 添加 / 修正供应商、协议转换或模型映射：只读 [供应商配置](references/cc-switch.md)，执行 `cc-switch/scripts/`；写库前备份，默认保留当前供应商。
- CLI、MCP、权限、Hooks、全局规范或整体装配检查：按下表读取宿主基线。只执行选中路线，不同时改动另一宿主。

| 目标 | 流程与检查规范 | 统一执行入口 |
|---|---|---|
| Claude Code / CC | [claude-code.md](references/claude-code.md) | [run.sh](claude-code/scripts/run.sh) |
| Codex CLI | [codex.md](references/codex.md) | [run.sh](codex/scripts/run.sh) |

每条路线的 scripts/check.sh 是检查项和修复命令的唯一来源。两宿主共用的全局规范正文放在 [rules/](rules/)（如 [先找成熟方案](rules/reuse-first.md)），check.sh 只核对关键词并给出追加命令。通过 run.sh 执行该宿主已有的常设维护，再做检查；需要验证 MCP 连接时传 --health。版本审计、缺失项回报和修复授权按对应 reference 执行。

Claude Code 路线的常设维护包含 Caveman 风格模式同步：run.sh 拉上游最新代码，只把风格模式的 hook 和文件 vendor 成用户级 hook，接进 settings.json 后卸载插件本体。拉取失败或上游结构变化时保留旧版本。配置见 [caveman-hooks.json](claude-code/config/caveman-hooks.json)，调用方可用 `CAVEMAN_VENDOR_CONFIG` 换成自己的配置；通用实现是 [vendor-plugin-hooks.mjs](claude-code/scripts/vendor-plugin-hooks.mjs)。

公共层接受环境变量和宿主配置，不包含个人账号、仓库、数据库或凭据。私有默认值及资产核对由调用方的私有 skill 追加；调用私有入口时不要再重复运行公共 run.sh。

两宿主的认证、权限、Hooks、插件和配置格式各自维护；已安装的 Claude 插件不自动映射为 Codex 插件。新加能力只改适用的路线。

认证后远端业务动作遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)；本机装配检查按宿主流程执行。密钥不进入 argv、日志或报告。
