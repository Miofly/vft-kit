# OpenI API 能力与 API 化进度

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

### 浏览器兜底（已有 API，见「API 化进度」；页面变更或接口失效时才用）

- **迁移外部模型**：`/repo/model_migrate`，Element UI 表单。`input.el-input__inner` 第 0 个 = HuggingFace 模型名、第 1 个 = 框架下拉（PyTorch…）、radio = 公开；提交按钮文本「迁移模型」。用 HF tiny 测试模型（如 `sshleifer/tiny-gpt2`）秒级完成。
- **创建调试任务（+10/日，实测创建即到账，无需 RUNNING）**：一键模板 `https://openi.pcl.ac.cn/cloudbrains/create?tmpl=ed82f65c-14a6-4542-a8c1-506a210659e0`（NPU 调试 MNIST 样例，预填全部参数），打开后直接点「新建任务」；手填空白表单会被前端静默拦截。提交后立刻到 `/cloudbrains` 停止，排队几秒即停 0 消耗。

## API 化进度

2026-10-12：日常积分任务全部接口化（除公开镜像），全部接受 Gitea token（`Authorization: token <t>`）：

| 动作 | 接口 | 备注 |
|---|---|---|
| 余额 | `GET /api/v1/ai_task/creation/required?job_type=DEBUG&compute_source=NPU&cluster_type=C2Net&app_name=` → `data.point_account` | `/reward/point/account`、`/reward/point/record/list` 只认会话 cookie |
| 迁移 HF 模型 | `POST /api/v1/hf_model/new`，body `{aimodel_type:2, externalName, hf_repo_id, name, url:"", version:"0.0.1", engine:0, label:"", license:"", isPrivate:false, hf_token:""}` | `code` 1 成功；2 = 全站已有人迁过（按 hf_repo_id 去重）；-1 迁移失败 |
| 一键模板参数 | `GET /api/v1/ai_task_template?id=<tmpl>` | 返回仓库、镜像、数据集、HasInternet |
| 建计算任务 | `POST /api/v1/{RepoOwnerName}/{RepoName}/ai_task/create`，body `{repoOwnerName, repoName, job_type, cluster, compute_source, template_id, display_job_name, description, branch_name, image_id, image_name, dataset_uuid_str, pretrain_model_id_str, params:"{\"parameter\":[]}", has_internet, spec_id}` | `display_job_name` 与可选 `specs` 取自 `creation/required`；`code` 0 成功 |
| 停任务 / 列表 | `POST /api/v1/ai_task/stop?id=`；`GET /api/v1/ai_task/my_list` | centerCreating 阶段 stop 返回 code 99；PREPARING 阶段返回 code 0 但不生效。只认回读到 `STOPPED`，否则反复 stop |
| 建数据集 | `POST /api/v1/dataset/create`，body `{name, alias, is_private, tags:[...], tasks:[...], licenses, owner_id, description}` | 名称 `^[a-zA-Z0-9][a-zA-Z0-9-_.]{0,98}[a-zA-Z0-9]$`；文件用 SDK `openi_upload_file(repo_type="dataset")` |
| fork | `POST /api/v1/repos/{o}/{r}/forks` | 同步执行常 >30s：别靠客户端重试，用回读 `GET /repos/{me}/{r}` 判成败 |

发现方法：下载页面 bundle（`/js/vp-*.js`）静态搜 `url:"/api/v1/..."` 与 submit 函数里的字段赋值，再用 token 直调并以余额差值验证。待接口化：提交公开镜像（需运行中的任务）。
