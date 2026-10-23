# OpenI GPU 训练任务：挂载、容器环境与踩坑（公共版）

训练任务（TRAIN）相当于 Kaggle push：指定仓库分支和启动文件，平台拉代码、挂数据，跑完自己结束。2026-10 在 A100 40GB 上多轮实测。

## 建任务

- 接口：`POST /api/v1/{owner}/{repo}/ai_task/create`，字段见 [api.md](api.md)。TRAIN 还要加：
  - `boot_file`：仓库内路径。
  - `image_url`：镜像的 registry 地址，取 `/api/v1/images/public` 返回的 `place`。只传 `image_name` 会报 1002。
- `has_internet=2` 才是联网。GPU 规格只有联网队列，传 1 也会报 1002。
- 挂公开模型：`pretrain_model_id_str` 填模型 id，多个用分号分隔，最多挂 7 个。
- 挂数据集：`dataset_uuid_str` 填数据集 uuid，多个用分号分隔。
- 挂载位置：模型在 `/tmp/pretrainmodel/<模型名>/`，数据集在 `/tmp/dataset/`。boot 开始前就已挂好，不用等 c2net `prepare()`。
- 输出写到 `/tmp/output`，再调 `c2net.context.upload_output()`。**任务结束后才能下载**：`GET /api/v1/ai_task/output/all?id=` 和 `/ai_task/output/download?id=&file_name=&parent_dir=`。中途调用 upload 也拿不到文件。
- 日志：`GET /api/v1/ai_task/log?id=`。

## 容器环境（A100 40GB 训练任务实测）

- 内存 754G，`/dev/shm` 378G，`/` 约 700G 可用，都远大于 GPU 显存。
- 出口：HuggingFace 连不上；ModelScope 有时能连（几 MB/s），有时完全连不上（`curl: (7)`）；`openi.pcl.ac.cn` 能连。**运行必需的文件（包括几十 MB 的 LoRA）都放进模型或数据集挂载**，不能指望现拉。
- 挂载盘读速取决于宿主机页缓存：热的时候 1-3.5 GB/s，冷的时候 76-160 MB/s。开机就开线程把要用的权重全部顺序读一遍（与装依赖并行），后面加载就是热读。
- pip 装依赖的时间因机器而异，实测 14-1077 s，大部分花在镜像源的元数据查询上，真正要装的可能只有一两个包。启动时间的波动主要来自这里，解决办法是自建镜像，见文末。

## 模型和数据集

- **迁移 HF 模型**（`POST /api/v1/hf_model/new`）在平台服务器上执行，不开任务、不耗积分。几点要注意：
  - 返回 `code -1 "failed to create model"` 时，迁移可能已经建好了，先查 `GET /api/v1/hf_model/status?hf_repo_id=<repo>` 的逐文件记录，再决定要不要重发。重发会得到 code 2「already exists」。
  - 偶尔遇到平台侧 `TLS handshake timeout`，重发一次就好。
  - 新迁移可能排队几个小时（status -1，`last_heartbeat` 为 0）。急用的话自己下载后传到数据集。
  - 单模型上限 200GB。可以先在 HF 上用 `POST /api/models/<src>/duplicate` 复制仓库，再用 commit API 批量 `deletedFile`，只留需要的文件，然后迁移。
- `/api/v1/aimodel/files` 列出的目录可能是「无限嵌套的空目录」，这是接口的显示问题，不代表模型坏了。判断模型可不可用：看 `hf_model/status` 里每个文件 status 是否为 1，或者挂一次看 `/tmp/pretrainmodel` 里的实际文件。
- 热门 HF 仓库多半已经在 `FoundationModel` 组织下，先 `GET /api/v1/aimodel?aimodel_name=FoundationModel%2F<名>` 查。Diffusers 分片格式的模型在 ComfyUI 里不用转换：把各分片的 state dict 合并后，交给 `comfy.sd.load_diffusion_model_state_dict`。
- 数据集：
  - 往已经挂载过的数据集里追加文件，新文件可能挂不进后续任务（挂载用的是旧文件列表）。新文件放进新建的数据集。
  - 上传后用 SDK `OpeniRouter.subject_filelist` 核对，要用**数据集所有者**的 token；私有数据集对别的账号返回 None。
- fork：`POST /repos/{o}/{r}/forks` 返回 500「Repository is already forked」时，fork 可能就是这次调用建出来的，回读 `GET /repos/{me}/{r}` 确认。

## ComfyUI 在 OpenI A100 上的坑

- 镜像 torch 2.9.1+cu130 + 较新的 ComfyUI 会报 `cuDNN Frontend error: No valid engine configs for Matmul_MUL_ADD_Reduction_SUB_EXP_...`。原因是 `comfy/ops.py` 用 `sdpa_kernel(..., set_priority=True)` 自己指定后端优先级，`torch.backends.cuda.enable_cudnn_sdp(False)` 会被覆盖。修法：在 import ComfyUI 之后执行 `comfy.ops.SDPA_BACKEND_PRIORITY.remove(SDPBackend.CUDNN_ATTENTION)`。
- DiT、TE、VAE 用线程池并行加载，加上开机预读，从开机到首图能压到 70-80 s（不含 pip 冷装）。
- 一轮要测的档位都放进同一个任务，每个档位单独 try/except，一个失败不影响其他。因为输出要等任务结束才能下载，拆成很多小任务反而更慢。

## 调试任务：接口执行代码与提交镜像

- JupyterLab 地址：`GET /api/v1/ai_task/debug_url?id=<task>`。
- 在浏览器里打开 `.../lab` 后，同源 fetch 带上 `X-XSRFToken`（取自 `_xsrf` cookie）就能用 `/api/kernels`、`/api/contents`、`/api/terminals`。用内核 `channels` websocket 发 `execute_request` 执行 Python，长命令用 `nohup` 后台跑再轮询日志。
- 只装依赖、提交镜像的话，选不带 GPU 的规格（1 分/时）就够了。
- 提交镜像的表单页是 `/notebook/<task>/commit_image`，下拉框默认值不可信，要逐个选成实际值。提交成功后用 `GET /api/v1/images/custom?q=&page=1&pageSize=30&cloudbrainType=-1` 查，返回的 `place` 就是训练任务要填的 `image_url`。`/tmp/code` 不会进镜像。
- 训练任务每次都 `pip install -r requirements.txt` 的话，即使只缺两个包，也可能因为镜像源元数据查询慢而花十几分钟。把依赖装进自建镜像。
