# 能力与分流

## 能力与分流

| 需求 | 实际入口 |
|---|---|
| 项目 | `projects list/get/create/update/delete`；连接 Git 用项目目录下的 `vercel link`、`vercel git connect` |
| 部署 | `deployments list/get/create/redeploy/cancel/delete/wait` |
| 项目域名 | `domains list/add/get/verify/remove`；verify/remove 必须给 `--project` |
| 环境变量 | `env list/add/update/remove/import` |
| 构建日志 | `logs get`；持续观察用 `vercel inspect <deployment> --logs --wait` |
| 运行时日志、函数检查 | `vercel logs`、`vercel inspect`，见 [官方 CLI 工作流](examples.md) |
| 别名、团队 | `aliases list/assign/remove`、`teams list/get/members/invite` |
| Edge Config | `edge-config list/create/get/set/delete/update` |
| Webhook | `webhooks list/create/get/delete`；创建时必须提供私有 `--secret-file` |
| Blob | 官方 `vercel blob`；存储凭证与 Vercel Access Token 不同 |
| Cron | 修改项目 `vercel.json` 的 `crons` 后部署；不能假设存在 cron CRUD API |
| 监控 | `vercel metrics schema` 后按实际指标调用 `vercel metrics` |
| 其它已确认 API | `api METHOD /path --data-file /private/body.json --query 'limit=10'` |

后四类由 skill 指导调用官方能力，不伪装成本地 Node 子命令。旧占位入口返回非零并指向真实工作流。
首次使用某个官方 CLI 命令先检查本机 `vercel <command> --help`；不要为例子自动升级 CLI。
