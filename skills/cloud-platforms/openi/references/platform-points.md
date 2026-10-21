# OpenI 平台事实与积分任务

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
| 运行计算任务（调试/训练/推理/评测任一） | 10 | 10 | `ai_task/create` 用一键模板参数，见下 |
| 创建或 Fork 公开项目 | 1 | 3 | Gitea API |
| commit | 1 | 3 | Gitea contents API |
| 提 issue / 提 PR / 发评论 | 1 | 3/3/2 | Gitea API（PR：contents 带 `new_branch` 建分支 → `POST .../pulls`） |
| 创建数据集 | 1 | 3 | `POST /api/v1/dataset/create`（往 repo 写文件不计分） |
| 创建模型（含迁移外部模型） | 1 | 3 | `POST /api/v1/hf_model/new` |
| 提交公开镜像 | 1 | 3 | 未接口化 |
| 数据集/模型/镜像被平台推荐 | 5 | 各 15 | 不可控 |
| 邀请好友 | 10/人 | 100/日 | `/user/invitation_tpl` |

日常任务合计约 33 分/天。平台点名舞弊判定：空评论、复制粘贴/重复灌水项目或数据集、删评——内容必须与仓库主题相关。
