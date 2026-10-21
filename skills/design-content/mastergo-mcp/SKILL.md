---
name: mastergo-mcp
description: "配置或使用 MasterGo Vibe/Magic MCP，读取设计稿、原型、画布与 DSL，导出素材或转代码；排查连接、needsCanvasVisit、50678 端口和 token。"
---

## 浏览器到 API 的强制演进

本 skill 只要以浏览器执行远端业务动作，就必须先读并遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)。登录、验证码、2FA、纯视觉验收可保留浏览器；认证后的可接口化动作仍须抓取、复现、独立回验，并在同一任务自更新本 skill 与脚本。

# MasterGo MCP

配置或使用 MasterGo 的 Vibe MCP（本机画布）与 Magic MCP（按链接读取远程 DSL/D2C），两种能力不混淆、不静默互相降级。

## 何时用

读取设计稿、原型、画布与 DSL，导出素材或转代码，生成或修改画布；排查连接、`needsCanvasVisit`、50678 端口和 token。

## 硬规则

- 任何 MasterGo 任务的第一条命令是 `node "$SKILL_DIR/scripts/mastergo-mcp.mjs" status`，不是打开浏览器；缺失就按 [setup.md](references/setup.md) 补装。
- 用户请求使用 MasterGo MCP 执行实际设计任务，视为允许为当前宿主安装 Magic 和 Vibe 两套官方 MCP；仅问能力、状态或诊断时保持只读。
- 实际任务开始前先检查当前宿主；Magic 或 Vibe 任一缺失时，分别运行对应的 `configure --mode ... --target <当前宿主>` 补齐两套，不得只安装当前任务直接用到的一套。
- Magic Token 只从环境变量读，且必须与域匹配；不让用户把 Token 发到聊天，不打印、不写仓库。
- 只修改用户点名的宿主；装完提醒新开会话才生效。
- 删除节点/变量、全量 HTML 同步需明确授权；Vibe 连接失败时停止写操作，不降级为 Magic 假装完成。
- 浏览器步骤有 ego-lite 就用独立 task space，没有才用 Playwright。

## 路由

| 任务 | references | 脚本 |
|---|---|---|
| API 优先、抓接口、维护 API 化进度 | [api-first.md](references/api-first.md) | — |
| 模式选择、status/doctor、安装配置、代理与 Token | [setup.md](references/setup.md) | [mastergo-mcp.mjs](scripts/mastergo-mcp.mjs) |
| 读取/生成/修改/同步设计稿、Magic 链接、`needsCanvasVisit`、浏览器回退与导切图、设计操作边界、完成标准 | [workflows.md](references/workflows.md) | [enumerate-containers.js](scripts/enumerate-containers.js)、[collect-export-nodes.js](scripts/collect-export-nodes.js)、[extract-text.js](scripts/extract-text.js)、[measure-layout.js](scripts/measure-layout.js) |

测试：`node --test tests/test-mastergo-mcp.mjs`。
