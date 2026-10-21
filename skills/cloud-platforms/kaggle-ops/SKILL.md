---
name: kaggle-ops
description: "通过 Kaggle CLI/API 管理任意账号的 kernel 提交、状态、日志、dataset 上传与配额；支持多账号，凭据由环境变量或配置供给。"
---

# kaggle-ops

通用 Kaggle API 操作封装。**可开源、不含私有信息。** 适合任何需要管理 Kaggle kernels/datasets 的项目。

下文 `<skill-dir>` 指当前 `SKILL.md` 所在目录的绝对路径，由 Claude Code 或 Codex 从已加载 skill 位置解析；不要按当前工作目录猜测。

## 何时用

- 推送、查询、拉日志：Kaggle kernel；推送 dataset；查 GPU 配额。
- 多个 Kaggle 账号切换操作，凭据由环境变量或配置文件供给。
- 批量探测账号 GPU 是否真实可用（手机验证）。

## 核心流程

1. 装 Kaggle CLI 2.x 与 Node 18+，准备凭据，见 [setup.md](references/setup.md)。
2. 按需调用 `node "<skill-dir>/scripts/kaggle-cli.mjs" <kernel push|kernel status|kernel logs|dataset push|quota> [--account <name>]`。
3. push 后轮询 `kernel status` 到终态，再 `kernel logs` 取日志。
4. 需确认 GPU 可用时跑 `probe-gpu.mjs`，再用 `mark-gpu-verified.mjs` 解析报告。

## 硬规则

- 凭据按优先级取：环境变量 → `~/.kaggle/kaggle.json` → 配置文件；不 hardcode。
- 多账号操作前明确 export 或传 `--account`，避免 token 串用。
- 只对网络瞬断和 API 500 重试；404/权限错误不重试。
- Token 能鉴权不等于能用 GPU；以 probe kernel 检测 `torch.cuda.is_available()` 为准。
- 探测用临时 `HOME` 注入凭据并清掉宿主 `KAGGLE_*` 变量，防止记到宿主账号。
- 探测默认删除远端 probe kernel；只有 `--keep-remote` 才保留。
- 本 skill 不含业务逻辑；账号池、kernel 映射、回写结果放私有 skill。

## 路由表

| 任务 | references | 执行脚本 |
|---|---|---|
| 特性、安装 CLI、凭据优先级、多账号配置 | [setup.md](references/setup.md) | `config.example.json` |
| kernel push/status/logs、dataset push、quota | [commands.md](references/commands.md) | `scripts/kaggle-cli.mjs` |
| 私有层封装方式、常见问题 | [private-layer-faq.md](references/private-layer-faq.md) | — |
| GPU 真实可用性探测、报告解析、账号来源集成、分层 | [gpu-verify.md](references/gpu-verify.md) | `scripts/probe-gpu.mjs`、`scripts/mark-gpu-verified.mjs` |
