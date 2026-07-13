---
name: notify-setup
description: 一键开通 vft-kit 的 macOS 桌面通知（任务完成/失败、等待输入、等待授权）。装 terminal-notifier、触发系统通知授权、并把 4 个 hook 事件（Stop/PostToolUse/PreToolUse/PermissionRequest）幂等写进 ~/.claude/settings.json（用稳定绝对路径，不受插件升级影响）。用户说"开通通知"、"设置桌面通知"、"通知不弹/没反应"、"装 terminal-notifier"、"开启 Claude 通知"、"notify-setup"、"配置任务完成提醒"、"怎么让 cc 完成时弹通知"、"刚装了 vft-kit 通知怎么开"等场景时触发。仅 macOS。会改 settings.json，改前自动备份。
---

# notify-setup —— 开通 vft-kit 桌面通知

装完 vft-kit 后跑一次，把桌面通知彻底打通。**仅 macOS**。

## 它解决什么

vft-kit 的 `notify.mjs` 能在「任务完成 / 任务失败 / 等待输入 / 等待授权」时弹 macOS 通知，但要真正收到通知，有三件插件自身没法自动完成的事：

1. 装 `terminal-notifier`（可选增强，缺了退 osascript）；
2. 首次发通知时 macOS 要**手动授权**；
3. hook 要注册。本 skill 把 hook 写进**你自己的 `~/.claude/settings.json`**，并指向一个**不随插件版本变的稳定脚本路径**（`~/.claude/vft-kit/hooks/notify.mjs`）——避免插件升级后带版本号的 cache 路径失效。

> 通知走 settings.json（本 skill 负责），用量告警仍走插件自带 hooks.json，两者不重复、不双弹。

## 怎么用

直接跑脚本：

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/notify-setup/scripts/setup.sh
```

脚本是**幂等**的，反复跑安全：settings.json 已有的 hook 会跳过，`notify.mjs` 每次刷新到最新版。

跑完照脚本末尾的两步收尾：

1. **授权**：若没看到测试通知，去「系统设置 › 通知」允许 `terminal-notifier`（或「脚本编辑器」）发通知；
2. **重启会话**：settings.json 里的 hook 需重启 Claude Code 会话才生效。

## 插件升级后

`notify.mjs` 有新版时，**重跑一次本 skill** 即可把新脚本刷到稳定路径（settings.json 无变化）。

## 自定义（可选）

本 skill 首次运行会在 `~/.claude/vft-kit/notify-config.json` **落一份填满默认值的配置模板**（已存在则不覆盖）。直接编辑它即可改通知文案 / 声音 / 图标 / 开关，改后重启会话生效。

- 四种通知：`taskComplete`（有工具且成功收尾）/ `taskError`（工具失败）/ `waitingForInput`（等授权或 AskUserQuestion/ExitPlanMode）/ `conversationComplete`（纯对话收尾）。
- `sound` 用 macOS 系统音名（Hero / Basso / Glass / Ping / Funk / default…，取自 `/System/Library/Sounds`）。
- 全关：把顶层 `enabled` 设 `false`；关某一类：把该类的 `enabled` 设 `false`。
- **为什么落满字段模板**：`notify.mjs` 对 `notifications.<类型>` 是**整块替换**（浅合并），不是深合并。有了齐全模板，改任意一项都不会丢掉同块内其它默认字段。

## 边界与安全

- **非 macOS**：直接打印说明退出，不做任何改动。
- **无 brew**：terminal-notifier / jq 装不了时——terminal-notifier 缺失退 osascript（仍能通知）；jq 是写 settings.json 的硬依赖，缺了会提示手动装后重跑。
- **settings.json 保护**：改前自动备份（`settings.json.bak-<时间戳>`）；若原文件不是合法 JSON，只备份并报错退出，**绝不覆盖**。
