# Vercel API 契约

核对来源：[官方 OpenAPI](https://openapi.vercel.sh)、[REST 文档](https://vercel.com/docs/rest-api)。本次核对日期：2026-09-05。不要从旧示例推测不存在的 endpoint。

- Origin 固定 `https://api.vercel.com`；token 仅发往该 origin，不跟随重定向。
- `team_id` 转成查询参数 `teamId`；这只是 scope 选择，服务端才执行权限校验。
- 版本跟随各 endpoint，不存在“全局统一 v13”。
- 列表按响应的 pagination 字段继续，不把 limit 当成完整清单。

| 操作 | 本地实现使用的契约 |
|---|---|
| 用户 | GET /v2/user |
| 项目 | GET /v10/projects；POST /v11/projects；GET/PATCH/DELETE /v9/projects/{idOrName} |
| 部署 | GET /v7/deployments；POST /v13/deployments；GET/DELETE /v13/deployments/{id}；PATCH /v12/deployments/{id}/cancel |
| 项目域名 | GET /v9/projects/{id}/domains；POST /v10/projects/{id}/domains；POST /v9/projects/{id}/domains/{domain}/verify；DELETE /v9/projects/{id}/domains/{domain} |
| 域名详情 | GET /v5/domains/{domain} |
| 环境变量 | GET/POST /v10/projects/{id}/env；PATCH/DELETE /v9/projects/{id}/env/{envId} |
| 构建日志 | GET /v3/deployments/{id}/events，builds=1；since/until 为毫秒时间戳 |
| Edge Config | 当前 OpenAPI 的控制面路径为 /v1/global-config；items 批量更新使用 PATCH |
| Webhook | GET/POST /v1/webhooks；GET/DELETE /v1/webhooks/{id} |

创建部署必须提供 name。GitHub gitSource 用 repoId/ref，GitLab 用 projectId/ref，Bitbucket 用 repoUuid/ref；高级覆盖可用 --git-source JSON。重新部署提供 deploymentId 与原部署 name。

Edge Config 创建体为 `{"slug":"example"}`；更新体为 `{"items":[{"operation":"upsert","key":"flag","value":false}]}`。旧文档里的 /v1/edge-config 与当前 OpenAPI 名称不同，修改前重新核对，不自动重试写请求去探测别名。

Webhook 创建体含 url、events，可选 projectIds；响应的 secret 是签名密钥。CLI 要求 --secret-file 接收它。没有把历史示例中的 test 子命令映射到猜测的 URL。

不存在已核实的本地 Blob/cron/analytics 通用 REST 封装。使用 [官方 CLI 与项目配置](examples.md)；不要恢复 /v1/blob、/v1/analytics、/v1/builds/time 等未经确认的示例。
