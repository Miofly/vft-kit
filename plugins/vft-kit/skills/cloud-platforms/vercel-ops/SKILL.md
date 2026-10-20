---
name: vercel-ops
description: >-
  不依赖 MCP 的 Vercel 运维：使用 API token 管理项目、部署、域名、环境变量、构建日志、别名、团队、Edge Config 和 Webhook。
  Blob、运行时日志、函数检查和监控复用官方 Vercel CLI；Cron 使用项目配置。支持多 profile，适合交互操作和自动化。
---

# vercel-ops

优先使用本 skill 的 REST 脚本与官方 CLI；不需要安装 Vercel MCP，也不需要 MCP OAuth。API token 和 CLI 登录态分别核对。

## 何时用

管理 Vercel 项目、部署、域名、环境变量、构建日志、别名、团队、Edge Config、Webhook；Blob、运行时日志、函数检查和监控走官方 CLI，Cron 改项目配置。

## 硬规则

- Token 优先 `VERCEL_TOKEN`；显式配置或 profile 不存在直接失败，不静默换账号；不打印 token 或整个配置。
- 部署默认 preview，生产必须显式 `--target production`。
- 保存创建响应的部署 ID，按该 ID 等终态；不拿“最近一条 READY”代替本次部署。
- 写请求不自动重试；失败先查远程状态再决定重试。
- 列表默认只返回一页，不据一页输出做全量清理。
- 真实验证优先只读操作，不为测试创建生产资源。

## 路由

| 任务 | references | 脚本 |
|---|---|---|
| 入口、认证、配置与 profile | [auth-config.md](references/auth-config.md) | [vercel-ops.js](scripts/vercel-ops.js) |
| 能力与分流（REST 子命令或官方 CLI） | [capabilities.md](references/capabilities.md) | [vercel-ops.js](scripts/vercel-ops.js) |
| 常用命令与注意事项、输出与错误、维护与验证 | [operations.md](references/operations.md) | [test.sh](scripts/test.sh) |

- [官方 CLI、Cron、部署示例](references/examples.md)：按实际操作读取。
- [API 契约与官方来源](references/vercel-api.md)：增改 endpoint 前查阅。
- [故障定位](references/troubleshooting.md)：认证、网络、日志和发布失败时读取。
- [踩坑记录](references/lessons.md)：实际部署操作的问题沉淀（部署错项目、CLI 交互、代理验收等），操作前先查。
