---
name: openi
description: "Operate OpenI (openi.pcl.ac.cn, 鹏城实验室启智社区): Gitea-style repos/issues/commits via REST API, points (积分) economy for free NVIDIA/Ascend compute, dataset upload via official SDK, model migration and cloudbrain debug tasks via browser. Use when creating repos, earning daily points, or running free GPU/NPU jobs on OpenI."
---

## 浏览器到 API 的强制演进

本 skill 只要以浏览器执行远端业务动作，就必须先读并遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)。登录、验证码、2FA、纯视觉验收可保留浏览器；认证后的可接口化动作仍须抓取、复现、独立回验，并在同一任务自更新本 skill 与脚本。

# OpenI 启智社区（公共版）

平台 https://openi.pcl.ac.cn ，Gitea 改造的 AI 协作平台（鹏城实验室云脑 + 中国算力网）。Access token 在 `用户设置 → 应用`（`/user/settings/applications`）生成，40 位 hex 只显示一次；调用带 `Authorization: token <token>`。

## 平台事实（2026-10-11 核实，政策可能变动）

- 积分规则：`/reward/point/rule`；余额/明细：`/reward/point`
- 算力单价：A100 9 分/卡时、V100 6、RTX3090 4、T4 2、昇腾 910/910B 2、海光 K100_AI 3；燧原 GCU、寒武纪 MLU290、海光 DCU/Z100L、天数智芯、沐曦、壁仞均 1 分/卡时。
- 计费粒度 6 分钟，不满 6 分钟不扣；调试任务关浏览器不会停止，必须手动停。
- 单日积分获取上限 100 分；积分只用于算力；免费存储配额 100 GiB。
- PyTorch/CUDA 工作流只能用 NVIDIA 卡；国产卡需 torch_npu 等适配。

## 积分任务与获取方式

| 任务 | 单次 | 每日上限 | 实现方式 |
|---|---|---|---|
| 运行计算任务（调试/训练/推理/评测任一） | 10 | 10 | 浏览器一键模板，见下 |
| 创建或 Fork 公开项目 | 1 | 3 | Gitea API |
| commit | 1 | 3 | Gitea contents API |
| 提 issue / 提 PR / 发评论 | 1 | 3/3/2 | Gitea API |
| 创建数据集 | 1 | 3 | openi SDK `upload_file` |
| 创建模型（含迁移外部模型） | 1 | 3 | 浏览器 `/repo/model_migrate` |
| 提交公开镜像 | 1 | 3 | 未接口化 |
| 数据集/模型/镜像被平台推荐 | 5 | 各 15 | 不可控 |
| 邀请好友 | 10/人 | 100/日 | `/user/invitation_tpl` |

日常任务合计约 33 分/天。平台点名舞弊判定：空评论、复制粘贴/重复灌水项目或数据集、删评——内容必须与仓库主题相关。

## API 能力（实测结论）

### Gitea REST API（`/api/v1` 前缀，全部可用）

- 验证：`GET /api/v1/user`
- 建 repo：`POST /api/v1/user/repos`，body `{"name","description","private":false,"auto_init":true,"default_branch":"master"}`
  - **坑：不要传 `readme` 参数**——OpenI 把它当模板文件路径，传内容报 500。
- 新文件 commit：`POST /api/v1/repos/{owner}/{repo}/contents/{path}`，body `{"content":"<base64>","message"}`；改文件用 `PUT` 且带原文件 `sha`。
- issue：`POST /api/v1/repos/{owner}/{repo}/issues`；评论：`POST .../issues/{index}/comments`；fork：`POST .../forks`。
- 网页 fork 表单 `/repo/fork/{id}` 中 `#alias`（显示名）是必填，只填 `#repo_name` 会被静默拦截。

### openi 官方 SDK（`pip install openi`；系统 Python 有 PEP 668 限制，用 venv）

- 可用：`openi.login(token)`、`openi.whoami()`、`openi.upload_file(repo_id, file)`（数据集文件上传）、`upload_model`、download 系。
- 不可信：`OpenIApi.create_repo`（路由缺 `/api/v1` 报 500）、`create_model`（路由与现网不符 404）、`get_user_info`（dataclass 字段不匹配）。repo/model 管理走 Gitea API 或浏览器。

### 浏览器专属（无公开 API）

- **迁移外部模型**：`/repo/model_migrate`，Element UI 表单。`input.el-input__inner` 第 0 个 = HuggingFace 模型名、第 1 个 = 框架下拉（PyTorch…）、radio = 公开；提交按钮文本「迁移模型」。用 HF tiny 测试模型（如 `sshleifer/tiny-gpt2`）秒级完成。
- **创建调试任务（+10/日，实测创建即到账，无需 RUNNING）**：一键模板 `https://openi.pcl.ac.cn/cloudbrains/create?tmpl=ed82f65c-14a6-4542-a8c1-506a210659e0`（NPU 调试 MNIST 样例，预填全部参数），打开后直接点「新建任务」；手填空白表单会被前端静默拦截。提交后立刻到 `/cloudbrains` 停止，排队几秒即停 0 消耗。

## API 化进度

- 已确认接口：Gitea 全套（见上）、openi SDK upload_file、模型迁移与云脑任务页面交互。
- 待抓步骤：云脑任务创建的 POST 报文（当前走一键模板 + 浏览器点击，已够用）；公开镜像提交。

## 安全边界

- 写接口只在本次任务的目标对象上验证；会触发写入的 GET 不预取。
- token 只从环境变量或凭据文件读取，不进命令行参数、不打印、不写进公开仓库。
- 删除/停止任务类操作保持人工确认或明确授权。
