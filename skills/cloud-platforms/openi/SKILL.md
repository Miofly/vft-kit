---
name: openi
description: "Operate OpenI (openi.pcl.ac.cn, 启智): repos/issues via REST API, daily points (积分) for free GPU/NPU compute, dataset upload, cloudbrain debug tasks."
---

## 浏览器到 API 的强制演进

本 skill 只要以浏览器执行远端业务动作，就必须先读并遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)。登录、验证码、2FA、纯视觉验收可保留浏览器；认证后的可接口化动作仍须抓取、复现、独立回验，并在同一任务自更新本 skill 与脚本。

# OpenI 启智社区（公共版）

用 Gitea REST API、官方 SDK 和平台接口操作 OpenI（openi.pcl.ac.cn）：仓库、issue、每日积分、数据集上传与云脑调试任务。

## 何时用

在 OpenI 建仓库、commit、提 issue/PR、评论，做每日积分任务，上传数据集、迁移模型，或创建、停止免费 GPU/NPU 调试任务。

## 硬规则

- 调用带 `Authorization: token <token>`；token 在 `/user/settings/applications` 生成，只显示一次。
- 每日积分任务已接口化，优先走 API；浏览器只在页面变更或接口失效时兜底。
- 调试任务关浏览器不会停止，必须手动停；停止只认回读到 `STOPPED`。
- 积分相关内容必须与仓库主题相关；空评论、重复灌水、删评会被判舞弊。
- 建 repo 不传 `readme` 参数。

## 安全边界

- 写接口只在本次任务的目标对象上验证；会触发写入的 GET 不预取。
- token 只从环境变量或凭据文件读取，不进命令行参数、不打印、不写进公开仓库。
- 删除/停止任务类操作保持人工确认或明确授权。

## 路由

| 任务 | references |
|---|---|
| 平台事实、算力单价、积分任务表 | [platform-points.md](references/platform-points.md) |
| Gitea API、官方 SDK、浏览器兜底、API 化进度接口表 | [api.md](references/api.md) |
| GPU 训练任务：挂模型/数据集、容器环境、HF 迁移、ComfyUI 坑 | [gpu-tasks.md](references/gpu-tasks.md) |

本 skill 没有脚本；按 [api.md](references/api.md) 的接口直接发 HTTP 请求，SDK 用 venv 安装。
