# 官方 CLI 与操作示例

## 官方 CLI 认证

先 `command -v vercel`，再 `vercel <command> --help` 核对本机版本。
CLI 复用其现有登录态；token 自动化按本机帮助和用户保险库接入，禁止把 token 展示在会话中。
REST 脚本的 --config 不会自动传给官方 CLI。用 --scope 明确团队，项目相关操作用 --project 或在已链接项目目录运行。

## Git 项目与部署

在实际项目目录执行：

```bash
vercel link
vercel git connect
```

先确认目标项目和仓库再连接。通用脚本的 projects link 已停止调用未经确认的 REST 地址。
已有 Git 集成时从 skill 目录执行：

```bash
node scripts/vercel-ops.js deployments create prj_xxx --ref main --target production --json
node scripts/vercel-ops.js deployments wait dpl_returned_id --timeout 1800 --json
```

将第一条返回的 id 传给第二条。ERROR、CANCELED 或超时都停止发布成功判断；READY 后验证实际域名版本。生产发布必须处于用户授权范围。

## 构建日志、运行时日志、函数

```bash
vercel inspect dpl_xxx --logs --wait
vercel inspect dpl_xxx --format json
vercel logs --project my-project --environment production --since 1h --level error --json
vercel logs dpl_xxx --follow
```

inspect 查看部署及函数信息；logs 查看请求与函数运行时输出。CLI 的 --json 日志是 JSON Lines，区别于本地脚本的单个 JSON 文档。
函数调用走应用自己的 URL 与认证，不向应用 URL发送 Vercel Access Token。

来源：[inspect](https://vercel.com/docs/cli/inspect)、[logs](https://vercel.com/docs/cli/logs)。

## Blob

先检查各子命令帮助；数据操作通常需要独立的 BLOB_READ_WRITE_TOKEN 或 OIDC/store 配对凭证，不能拿 VERCEL_TOKEN 当 Blob token。

```bash
vercel blob list-stores
vercel blob create-store my-store
vercel blob list
vercel blob put ./asset.png
vercel blob get <url-or-pathname>
vercel blob del <url-or-pathname>
```

从项目关联的正确 store 操作；下载输出路径遵守用户指定产物目录。执行 put/get 前检查子命令的 pathname、access 与输出参数，不猜测旧 skill 的 store-id/key 参数格式。
创建、上传、删除只在当前任务授权范围执行。

来源：[Blob 管理](https://vercel.com/docs/vercel-blob/manage-blob-storage)。

## 监控

```bash
vercel metrics schema
vercel metrics <actual-metric-id> --project my-project --since 1h --format json
```

指标 ID 从 schema 选，权限/套餐和可查询时间范围以实际返回为准。流量指标不等同于 Web Analytics 页面访问数据；需要页面访问分析时单独核对官方 CLI/Analytics 能力，不把不存在的 analytics 子命令当成功。

来源：[CLI](https://vercel.com/docs/cli)。

## Cron

合并到项目原有 vercel.json，保留其它字段：

```json
{
  "crons": [
    { "path": "/api/daily", "schedule": "0 5 * * *" }
  ]
}
```

schedule 使用 UTC；更改/删除配置后重新部署才更新线上计划。
先实现对应 HTTP handler；若用 CRON_SECRET，handler 必须校验 Bearer secret。
手动运行用 Dashboard 的 Run，或在已获执行授权后按应用认证调用 handler；不能把普通 GET 当无副作用检查。
不要为 Cron 创建、更新、触发编造 REST endpoint。

来源：[Cron 维护](https://vercel.com/docs/cron-jobs/manage-cron-jobs)。

## 环境变量与 Webhook

多行环境变量用私有 JSON 文件，值必须是字符串；env import 支持 upsert，可重跑，不从 env list 导出明文。

```bash
node scripts/vercel-ops.js env import prj_xxx --file /private/env.json --target production --json
node scripts/vercel-ops.js webhooks create --url https://example.com/hook --events deployment.created --project prj_xxx --secret-file /private/new-webhook-secret
```

Webhook 密钥文件必须尚不存在，权限 0600。调用失败后保留的文件可能为空，先确认是否已创建远程 Webhook；不要盲目创建第二个。
