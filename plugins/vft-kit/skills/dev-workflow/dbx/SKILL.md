---
name: dbx
description: >-
  操作 DBX（dbxio.com 的跨平台数据库客户端）：创建、测试和维护数据库连接，管理驱动，查看结构和数据，编写或执行 SQL，使用 DBX MCP，或在桌面 UI 中打开结果。用户提到 DBX、数据库连接、DBX 驱动管理、DBX SQL 编辑器或 DBX MCP 时使用；不用于无关的数据库 CLI 或其他同名 dbx 工具。
---

# DBX

DBX 是本地优先的数据库客户端。默认走 DBX MCP 的 stdio 路径，适合静默、可重复、不会抢前台的连接和查询操作；只有 MCP 不适用，或用户明确要求看桌面 UI，才操作 DBX Desktop。不要把 DBX 的本地配置数据库当成业务数据库直接改写。

## 何时用

- 用 DBX 创建、测试、维护数据库连接，或管理驱动。
- 查看结构和数据、编写或执行 SQL、使用 DBX MCP，或在桌面 UI 打开结果。
- 不用于无关的数据库 CLI 或其他同名 dbx 工具。

## 硬规则

- 先确认目标连接、数据库/Schema、动作和结果形式；连接名相似时让用户指定，禁止猜生产目标。
- 默认走 DBX MCP；只有 MCP 不适用或用户要求看桌面 UI 才操作 DBX Desktop，静默任务不置前、不模拟键盘、不用固定坐标。
- 密码不进 argv、日志或项目配置；报告不输出密码、完整 URL、SSH 私钥或连接字符串。
- 写入、DDL、导入、删除前先明确 SQL、筛选条件和影响范围；用户未明确授权时停在预览。
- 生产连接用只读账号和 DBX Read-only，不启用 Full access，不绕过二次确认。
- 超时不代表失败，先查状态再重试；每个操作报告「已完成 / 已跳过 / 被阻塞 / 未验证」，并留一条可复核证据。

## 路由表

| 任务 | references | 脚本 |
|---|---|---|
| 官方文档、MCP 调用顺序、会话、静默加连接、`.mcp.json` | [mcp.md](references/mcp.md) | `scripts/dbx-mcp.mjs add-mysql … --password-stdin --probe` |
| 桌面端：新建/修改连接、多环境、驱动管理、查询与结构 | [desktop.md](references/desktop.md) | — |
| 写入和生产保护、完成验证 | [safety.md](references/safety.md) | — |
