---
name: lark-cli
description: "使用 lark-cli 操作 Lark/飞书的多维表格、云文档、云盘、电子表格、任务和知识库；排查认证问题或调用未封装的 OpenAPI 时使用。"
---

# lark-cli 路由器

这个 Skill 只依赖官方 `lark-cli`。它适用于 Lark、飞书或兼容部署；
账号、区域和权限由用户当前配置决定，不在 Skill 中写死。

## 首次使用预检

```bash
command -v lark-cli >/dev/null 2>&1 || npx @larksuite/cli@latest install
lark-cli auth status
```

如果尚未登录，按 CLI 输出的官方流程完成 OAuth；不要把 App Secret、Token、
Cookie 或授权码贴到对话里。CI 使用环境变量或平台 Secret 注入凭据。

## 领域路由

| 用户意图 | CLI 前缀 |
|---|---|
| 多维表格、字段、记录、视图和表单 | `lark-cli base` |
| 云文档内容创建、读取和更新 | `lark-cli docs` |
| 云盘文件、版本、权限和评论 | `lark-cli drive` |
| 原生 Markdown | `lark-cli markdown` |
| 电子表格和单元格 | `lark-cli sheets` |
| 任务、清单和提醒 | `lark-cli task` |
| 知识空间和节点 | `lark-cli wiki` |
| CLI 未封装的接口 | `lark-cli api` |

先运行对应命令的 `--help`，再按官方文档确认参数和资源 token 类型：

```bash
lark-cli base --help
lark-cli docs --help
lark-cli api --help
```

## URL 和资源 token

- `/wiki/` 路由到 `wiki`，`/sheets/` 路由到 `sheets`。
- `/docx/` 路由到 `docs`，云盘 file/folder/bitable/slides 路由到 `drive`。
- 已知对象 token 后再进入对象内部操作；不要把 URL、document ID、spreadsheet token 和 file token 混用。
- 本地文件导入后先回读资源 ID，再进行后续编辑。

## 安全和完成条件

- 只读查询可以直接执行；创建、更新、移动、删除、导入和权限变更前确认目标、范围和是否可回滚。
- 不把凭据放在命令行参数、日志或仓库；优先使用 CLI 登录态、环境变量或忽略的本地配置。
- API 返回成功或 CLI 打印完成不等于业务完成；写操作后重新读取资源、版本或权限状态。
- 遇到 401/403、404 或资源不存在，先读取 `lark-cli <domain> --help` 和官方错误说明，核对当前账号、租户、区域和 scope，不要重复创建资源。
