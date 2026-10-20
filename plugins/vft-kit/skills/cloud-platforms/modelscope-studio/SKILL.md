---
name: ms-studio-deploy
description: "Deploy or repair ModelScope Studio, manage secrets and Notebook/PAI-DSW CPU/GPU runtimes and workspace transfers, and publish or re-sync ModelScope Skills from a public GitHub repository. Excludes Hub repositories, training and evaluation."
---

## 浏览器到 API 的强制演进

本 skill 只要以浏览器执行远端业务动作，就必须先读并遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)。登录、验证码、2FA、纯视觉验收可保留浏览器；认证后的可接口化动作仍须抓取、复现、独立回验，并在同一任务自更新本 skill 与脚本。

# ModelScope Studio Deployment and Notebook Operations

> Studio OpenAPI verified 2026-06-29; authenticated Notebook web API verified 2026-08-18.

Deploy a local project to a ModelScope Studio. **This Skill uses OpenAPI as the source of truth**, with the `ms` CLI as an equivalent convenience alias, `modelscope_hub.HubApi` as the API-first Python client, and MCP tools as optional.

## 何时用

- 部署、更新、修复 Studio；管理明文变量与 secrets；看 build/run 日志。
- 查看、启动、停止 Notebook / PAI-DSW CPU/GPU 实例，做 workspace 文件传输与执行。
- 把公开 GitHub 仓里的 `SKILL.md` 目录发布或回源同步到 ModelScope Skills。
- 不用于：Hub 仓库文件、模型、数据集、训练、评测（交给 ms-hub）。

## Quick Decision Guide

```
User wants to...
│
├── Deploy a local project to a Studio
│   └── Follow the 10 steps in "Full Deployment Workflow" below
│
├── Update an already-deployed Studio
│   └── Modify code → git push → POST /studios/{o}/{r}/deploy (or ms deploy)
│
├── View Studio status/logs
│   └── GET /studios/{o}/{r}/logs/run (or ms logs --log-type run)
│
├── Manage variables
│   ├── Plaintext variables: GET/POST/PUT/DELETE /studios/{o}/{r}/variables
│   └── Secrets: GET/POST/PUT/DELETE /studios/{o}/{r}/secrets (or ms secret ...)
│
├── Inspect/start/stop a Notebook or PAI-DSW environment
│   └── Follow "Notebook / PAI-DSW" and references/notebook-dsw.md
│
└── Repository file management / model & dataset operations
    └── hand off → ms-hub
```

"Full Deployment Workflow" 全文在 [references/deploy-workflow.md](references/deploy-workflow.md)，"Notebook / PAI-DSW" 入口规则在 [references/notebook-dsw.md](references/notebook-dsw.md) 开头。

## 核心流程骨架（部署）

0. 有可选 config 就先套用：别名展开、个人默认值、自定义 pipeline。
1. 查本地 Git 是否已有 Studio remote；有就取 `owner/repo`，跳到第 3 步。
2. 判定 SDK 类型（gradio / streamlit / docker / static），`GET /users/me` 取 owner。
3. 先查 `hardware`、`sdk-versions`、`base-images`；不存在就 `POST /studios`（先问公开或私有，默认私有），存在就 `PATCH .../settings`。
4. 扫描硬编码敏感信息，改成读环境变量，列出变量与 secrets 清单。
5. Git 同步代码到 `master`（唯一非 API 步骤）。
6. 配置明文变量与 secrets。
7. `POST .../deploy`。
8. 轮询 `logs/build`（docker）与 `logs/run`，直到 `Running` 或出错。
9. 按日志诊断，修复后 push 并重新部署。
10. 给出 `$MODELSCOPE_ENDPOINT/studios/${owner}/${repo}`；私有空间询问是否公开。

## 硬规则

- API 优先：已确认的接口或脚本先用；浏览器只用于登录、验证码/2FA 交接、接口未知步骤、最终核验。
- 仍只能点页面的步骤：边做边抓写请求（不记 Cookie、Token、密码），复现并回验后写回本 skill 与脚本。
- Token 按顺序取：`MODELSCOPE_API_KEY` 环境变量 → Git remote → 本地 config 文件；不打印。
- 站点由 `MODELSCOPE_ENDPOINT` 决定（默认 `https://modelscope.cn`），token 必须属于同一站点。
- 默认分支是 `master`；禁止 force push；超过 100MB 的文件用 Git LFS。
- 付费硬件（`paid/<InstanceType>` 或 `resource_type=paid`）先说明会向绑定的阿里云账号计费，拿到明确授权再用。
- 代码禁止硬编码敏感信息：敏感值进 secrets，非敏感配置进明文变量。
- 删除变量或 secret 用 `DELETE .../variables|secrets`，body 传 `{"key":"..."}`，不用路径形式。
- secrets 改动在容器重启后才生效，改完对每个 Studio `POST .../deploy`。
- Docker：监听 `0.0.0.0:7860`，禁用 8080；应用不用 `Authorization`、`X-modelscope-*`、`X-studio-*` 请求头；需先绑定阿里云并实名。
- 控制面 `Running` 不等于可用，必须验证真实推理结果（`scripts/probe-runtime.py`）。
- Studio 无法通过程序删除，只能 stop；删除只能走网页控制台。
- Notebook 接口需要网页登录 Cookie；只有 `MODELSCOPE_API_KEY` 会得到 `401 user not logged in`。
- 不得省略、伪造、重放、记录或持久化 `CaptchaVerify`；验证码交给用户，在同一浏览器会话完成后再继续。
- 浏览器：有 `ego-browser` 就用 ego-lite 独立 task space，没有才用 Playwright，不另起 Chrome。
- `/mnt/workspace` 能跨重启保留数据，但不能直接当数据库盘；Studio 转移或改名会丢数据。
- Skills 发布默认 dry-run，`--apply` 才写；回源同步只看已 push 的提交。

## 路由表

| 任务 | 先读 | 执行脚本 |
|---|---|---|
| API 优先规范、API 化进度维护 | [references/api-first.md](references/api-first.md) | — |
| Token、运行环境、可选个性化 config、主备 failover 判定、MCP 工具首次接入 | [references/setup-and-config.md](references/setup-and-config.md) | — |
| 部署全流程 Step 0–10、批量更新 secrets、常见报错表 | [references/deploy-workflow.md](references/deploy-workflow.md) | — |
| OpenAPI ↔ CLI ↔ HubApi ↔ MCP 对照；`references/openapi-studio-endpoints.md` — detailed Studios OpenAPI endpoint parameters (source-of-truth specification) | [references/openapi-studio-endpoints.md](references/openapi-studio-endpoints.md) | — |
| `references/docker-templates.md` — Dockerfile templates for the Docker type (FastAPI, Node.js, Golang, etc.)；私有空间运行时回验、数据持久化 | [references/docker-templates.md](references/docker-templates.md) | `scripts/probe-runtime.py` |
| `references/troubleshooting.md` — deployment-failure troubleshooting process, common errors, and fixes；平台限制 Notes | [references/troubleshooting.md](references/troubleshooting.md) | — |
| `references/notebook-dsw.md` — authenticated Notebook / PAI-DSW endpoints, start payload, states, and captcha boundary | [references/notebook-dsw.md](references/notebook-dsw.md) | `scripts/dsw-jupyter.mjs` |
| `references/skills-publish-api.md` — ModelScope Skills create/sync endpoints, payload fields, and verification reads；发布命令与行为 | [references/skills-publish-api.md](references/skills-publish-api.md) | `scripts/publish-skills.mjs` |

## Reference Documentation

Consult when you run into problems or need more detail: 见上面路由表。

## Related Skills

- Hub repository management / models & datasets / MCP / skill management → ms-hub
