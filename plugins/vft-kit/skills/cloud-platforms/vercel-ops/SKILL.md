---
name: vercel-ops
description: >-
  不依赖 MCP 的 Vercel 运维：使用 API token 管理项目、部署、域名、环境变量、构建日志、别名、团队、Edge Config 和 Webhook。
  Blob、运行时日志、函数检查和监控复用官方 Vercel CLI；Cron 使用项目配置。支持多 profile，适合交互操作和自动化。
---

# vercel-ops

优先使用本 skill 的 REST 脚本与官方 CLI；不需要安装 Vercel MCP，也不需要 MCP OAuth。API token 和 CLI 登录态分别核对。

## 入口与认证

Node.js 18+，REST 脚本无第三方依赖。将下文 `$SKILL_DIR` 设为本 skill 的实际绝对目录：

```bash
node "$SKILL_DIR/scripts/vercel-ops.js" --help
node "$SKILL_DIR/scripts/vercel-ops.js" --config /absolute/private/vercel.json verify --json
```

Token 优先级：`VERCEL_TOKEN` > 配置中选定 profile 的 `access_token`。
配置路径：显式 `--config` > 当前目录 `vercel-config.json` > `~/.config/vercel/config.json`。
显式路径不存在、JSON 非法或 profile 不存在时直接失败，不能静默换账号。
即使环境变量提供 token，仍读取所选配置的 team scope；`--team-id` 最后覆盖。

配置可用 `config.example.json` 的单账号结构，或 `{"default": {...}, "work": {...}}` 多 profile 结构。私有凭证留在用户现有保险库，不复制到 skill。诊断只检查字段是否存在、调用是否成功，不打印 token 或整个配置。

## 能力与分流

| 需求 | 实际入口 |
|---|---|
| 项目 | `projects list/get/create/update/delete`；连接 Git 用项目目录下的 `vercel link`、`vercel git connect` |
| 部署 | `deployments list/get/create/redeploy/cancel/delete/wait` |
| 项目域名 | `domains list/add/get/verify/remove`；verify/remove 必须给 `--project` |
| 环境变量 | `env list/add/update/remove/import` |
| 构建日志 | `logs get`；持续观察用 `vercel inspect <deployment> --logs --wait` |
| 运行时日志、函数检查 | `vercel logs`、`vercel inspect`，见 [官方 CLI 工作流](references/examples.md) |
| 别名、团队 | `aliases list/assign/remove`、`teams list/get/members/invite` |
| Edge Config | `edge-config list/create/get/set/delete/update` |
| Webhook | `webhooks list/create/get/delete`；创建时必须提供私有 `--secret-file` |
| Blob | 官方 `vercel blob`；存储凭证与 Vercel Access Token 不同 |
| Cron | 修改项目 `vercel.json` 的 `crons` 后部署；不能假设存在 cron CRUD API |
| 监控 | `vercel metrics schema` 后按实际指标调用 `vercel metrics` |
| 其它已确认 API | `api METHOD /path --data-file /private/body.json --query 'limit=10'` |

后四类由 skill 指导调用官方能力，不伪装成本地 Node 子命令。旧占位入口返回非零并指向真实工作流。
首次使用某个官方 CLI 命令先检查本机 `vercel <command> --help`；不要为例子自动升级 CLI。

## 常用操作

```bash
node "$SKILL_DIR/scripts/vercel-ops.js" projects list --json
node "$SKILL_DIR/scripts/vercel-ops.js" deployments list --project prj_xxx --limit 5 --json
node "$SKILL_DIR/scripts/vercel-ops.js" deployments create prj_xxx --ref main --target production --json
node "$SKILL_DIR/scripts/vercel-ops.js" deployments wait dpl_xxx --timeout 1800 --json
node "$SKILL_DIR/scripts/vercel-ops.js" logs get dpl_xxx --since 1h --limit 100 --json
node "$SKILL_DIR/scripts/vercel-ops.js" domains verify example.com --project prj_xxx --json
node "$SKILL_DIR/scripts/vercel-ops.js" env import prj_xxx --file /private/env.json --target production --json
node "$SKILL_DIR/scripts/vercel-ops.js" edge-config set ecfg_xxx --key feature --value false
node "$SKILL_DIR/scripts/vercel-ops.js" webhooks list --project prj_xxx
```

- `deployments create/redeploy` 默认 preview；生产必须显式 `--target production`。此默认只适用于通用脚本，私有项目包装器保留自己的发布约定。
- Git 部署使用远程 ref；未推送的本地修改不会被部署。无 Git 集成时改用既有 Deploy Hook 或官方 CLI，不盲目重试。
- 必须保存创建响应的部署 ID，用该 ID 等到 READY/ERROR/CANCELED；禁止拿“最近一条 READY”代替本次部署。READY 后按任务验证域名实际版本和页面/API。
- `env import` 支持单行 dotenv（引号、空值、export、注释）或键值均为字符串的 JSON 对象。多行 secret 用 JSON；不进行变量插值。先校验整份输入再 upsert；遇 API 失败立即非零退出，先前成功项可安全重跑。
- `env list --json` 也移除 value；不是明文备份。通用 `api` 是原始响应，调用敏感 endpoint 时将输出交给安全处理程序，不向会话回显。
- `edge-config --value` 接受 JSON，包括 false、0、null、数组、对象；字符串需 JSON 引号。update 的文件是 key/value 对象；delete 只删指定 key。
- `webhooks create --url https://example.com/hook --events deployment.created --secret-file /private/new-secret` 将签名密钥写入新建的 0600 文件，不覆盖已有文件、不回显密钥。失败后先检查远程状态和该文件再决定重试；不假设有公共 webhook test API。
- `domains remove` 只解绑指定项目域名，不删除账号下整个域名资产。

## 输出与错误

`--json` 的 stdout 是单个 JSON 文档；进度、诊断走 stderr。`--verbose` 仅记录方法与路径，不打印请求体、查询参数或认证头。
每个请求最长 30 秒；GET 最多尝试 3 次，写请求不自动重试，避免响应丢失时重复创建。API 错误保留 HTTP 状态，不打印可能包含密钥的响应体。
退出码：0 成功，1 参数/配置/部署失败或等待超时，2 API HTTP 错误，3 网络/请求超时。列表默认只返回一页；完整遍历用官方 pagination 游标，不能据一页输出执行全量清理。

## 维护与验证

```bash
bash "$SKILL_DIR/scripts/test.sh"
```

离线回归覆盖账号选择、参数解析、JSON 输出、凭证保护、写请求不重试、环境变量导入、部署终态、项目域名、Edge Config、Webhook。真实验证优先 verify/projects/deployments/logs 等只读操作；不为测试创建生产资源。

- [官方 CLI、Cron、部署示例](references/examples.md)：按实际操作读取。
- [API 契约与官方来源](references/vercel-api.md)：增改 endpoint 前查阅。
- [故障定位](references/troubleshooting.md)：认证、网络、日志和发布失败时读取。
