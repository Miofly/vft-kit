---
name: kaggle-ops
description: >-
  通用 Kaggle API 操作封装:kernel push/status/logs、dataset push、账号配额查询。
  基于 Kaggle CLI(kaggle 2.x),零额外依赖。多账号支持,credentials 从环境变量或配置文件读取
  (优先级:KAGGLE_USERNAME/KAGGLE_KEY 环境变量 > ~/.kaggle/kaggle.json > config file)。
  子命令:kernel push/status/logs、dataset push、quota。适合任何 Kaggle 账号,不含私有信息。
trigger: []
---

# kaggle-ops

通用 Kaggle API 操作封装。**可开源、不含私有信息。** 适合任何需要管理 Kaggle kernels/datasets 的项目。

## 特性

- ✅ **Kaggle CLI 封装**:kernel push/status/logs、dataset push,带重试和错误处理
- ✅ **多账号支持**:一脚本管理多个 Kaggle 账号,`--account <name>` 切换
- ✅ **零依赖**(除 Kaggle CLI):Node 18+,调用系统的 `kaggle` 命令
- ✅ **密钥外部化**:credentials 从环境变量或配置文件读,不 hardcode
- ✅ **重试逻辑**:网络瞬断自动重试,Kaggle API 偶发 500 也能扛住

## Prerequisites

### 1. Kaggle CLI

需要 `kaggle` 命令可用(2.x 版本):

```bash
# 安装(推荐 pipx 全局装)
pipx install kaggle

# 或 pip
pip install kaggle

# 验证
kaggle --version  # 应显示 2.x.x
```

### 2. Kaggle credentials

所有操作需要 Kaggle API credentials(username + API token)。**按优先级查找,用第一个找到的**:

```
1. 环境变量(最高优先级)
   export KAGGLE_USERNAME=your-username
   export KAGGLE_KEY=KGAT_xxxxxxxxxxxx

2. Kaggle CLI 标准位置
   ~/.kaggle/kaggle.json

3. 配置文件(见下方 "Optional config")
   读取 <account>.json 的 username + api_token 字段
```

**获取 API token**:
1. 登录 kaggle.com
2. Account → API → Create New Token
3. 下载 `kaggle.json`,包含 `{"username":"...","key":"KGAT_..."}`

**首次设置**:复制本目录下 `config.example.json` 到你选择的位置,填入 credentials:

```json
{
  "username": "your-username",
  "api_token": "KGAT_your-token-here"
}
```

### 3. Node.js 18+

```bash
node --version  # 确认 >= 18
```

### 4. Optional config

Credentials 配置文件**也可以**携带这些可选键:

| 键 | 作用 |
|----|------|
| `default_account` | 省略 `--account` 时用哪个账号 |
| `accounts` | 多账号映射:`{"alias": {"username": "...", "api_token": "..."}}` |

**多账号模式**:
```
~/.config/kaggle/
├── default.json      # 主账号
├── test.json         # 测试账号
└── backup.json       # 备用账号
```
脚本用 `--account test` 选择。

## 子命令

### kernel push
Push kernel 到 Kaggle:
```bash
# 基础用法(从当前目录读 kernel-metadata.json)
node scripts/kaggle-cli.mjs kernel push

# 指定目录
node scripts/kaggle-cli.mjs kernel push --dir /path/to/kernel

# 指定账号
node scripts/kaggle-cli.mjs kernel push --account test --dir /path/to/kernel

# 重试配置
node scripts/kaggle-cli.mjs kernel push --retries 5 --retry-delay 3000
```

**重试逻辑**:网络瞬断(connection reset/timeout)自动重试;Kaggle API 500 错误也重试;其他错误(404/权限)不重试。

### kernel status
查询 kernel 运行状态:
```bash
node scripts/kaggle-cli.mjs kernel status <username>/<kernel-slug>
node scripts/kaggle-cli.mjs kernel status <username>/<kernel-slug> --account test
```

返回:running / complete / error / queued 等。

### kernel logs
拉取 kernel 日志:
```bash
node scripts/kaggle-cli.mjs kernel logs <username>/<kernel-slug>
node scripts/kaggle-cli.mjs kernel logs <username>/<kernel-slug> --save logs.txt
```

### dataset push
Push dataset 到 Kaggle:
```bash
node scripts/kaggle-cli.mjs dataset push --dir /path/to/dataset
node scripts/kaggle-cli.mjs dataset push --dir /path/to/dataset --account test
```

需要目录下有 `dataset-metadata.json`。

### quota
查询账号 GPU 配额:
```bash
node scripts/kaggle-cli.mjs quota
node scripts/kaggle-cli.mjs quota --account test
```

返回:已用时长 / 剩余时长 / 周期重置时间。

## 配置文件示例

见 `config.example.json`。

## 与私有 skill 的关系

本 skill 是**通用基础**,只提供"给我 username/token,我帮你 push kernel"的能力,不知道你的:
- 具体 kernel 名称/slug
- 业务逻辑(如双账号分摊配额、数据库账号池)
- 特定部署拓扑

私有项目应:
1. 创建私有 skill(如 `my-kaggle-deployment`)
2. 在私有 config.json 定义 kernels 映射、accounts 映射
3. 私有 skill 读自己的配置,从 `.secrets` 读 token,export 环境变量,再调本 skill

## 常见问题

**Q: 为什么不直接用 `kaggle` CLI?**
A: 本 skill 封装了重试逻辑、多账号切换、错误处理,比直接调 CLI 方便。

**Q: KGAT token 和 kaggle.json 的 key 是一样的吗?**
A: 是。Kaggle 2.x 的 API token 格式是 `KGAT_xxxx`,存在 `kaggle.json` 的 `key` 字段。

**Q: kernel push 失败怎么排查?**
A: 1) 检查 `kernel-metadata.json` 格式;2) 确认 slug 符合 Kaggle 命名规范(`kaggle-xxx`);3) 看日志里的具体错误(权限/quota/网络)。

**Q: 多账号场景如何避免 token 串用?**
A: 每次操作前明确 export KAGGLE_USERNAME/KAGGLE_KEY,覆盖环境;或用 `--account` 参数让脚本自动切换。

## GPU 验证（高级功能）

### 为什么需要 GPU 验证？

**问题**:
- Token 能鉴权 ≠ 能使用 GPU
- `gpu_remaining_seconds=30h` 只是配额元数据
- Kaggle GPU 需要手机验证，未验证账号返回配额但实际不能用

**解决方案**: 推送最小测试 kernel，真实检测 `torch.cuda.is_available()`

---

### 工具说明

#### 1. probe-gpu.mjs（单进程版）

**功能**: 探测账号 GPU 真实可用性（自定义并发池）

**适用场景**: Node.js 环境、命令行脚本

**输入方式**（3 种）:

```bash
# 方式1：JSON 文件（推荐）
node scripts/probe-gpu.mjs --accounts accounts.json

# accounts.json 格式：
# [
#   {"username": "user1", "token": "KGAT_xxx"},
#   {"username": "user2", "token": "KGAT_yyy"}
# ]

# 方式2：单个账号
node scripts/probe-gpu.mjs --username user1 --token KGAT_xxx

# 方式3：环境变量
export KAGGLE_USERNAME=user1
export KAGGLE_API_TOKEN=KGAT_xxx
node scripts/probe-gpu.mjs
```

**参数**:
- `--accounts <file>` - JSON 账号列表文件
- `--username <name>` - 单个账号用户名
- `--token <token>` - 单个账号 token
- `--limit=N` - 只测试前 N 个账号
- `--concurrency=N` - 并发数（建议 3-5）
- `--accelerator <type>` - 指定 GPU 型号（默认 NvidiaTeslaT4）

**输出**:
- `gpu-probe-report.json` - 完整探测结果
- `gpu-probe-report.csv` - CSV 格式

---

#### 1.1 probe-gpu-agent.mjs（Agent 并发版）⭐

**功能**: 使用 Claude Code Agent 并发探测（推荐用于 Claude Code 环境）

**适用场景**: Claude Code 会话中、需要快速并发探测大量账号

**优势**:
- ⚡ **更快**: Agent 真正并发执行，充分利用多核
- 🔒 **隔离**: 每个 Agent 独立进程，互不干扰
- 📊 **可视**: Claude Code 中可实时看到每个 Agent 的进度

**快速开始**:

```bash
# 1. 准备账号文件 accounts.json
# [
#   {"username": "user1", "token": "KGAT_xxx"},
#   {"username": "user2", "token": "KGAT_yyy"}
# ]

# 2. 生成 Agent 任务
node scripts/probe-gpu-agent.mjs --accounts accounts.json --concurrency 8

# 3. 复制脚本输出的 Agent 代码到 Claude Code 执行
# （会输出类似下面的代码）
# const results = await Promise.all([
#   agent('探测账号 user1 GPU', { label: '账号1' }),
#   agent('探测账号 user2 GPU', { label: '账号2' })
# ]);

# 4. 收集结果
node scripts/collect-probe-results.mjs --dir .tmp-probe-accounts --output gpu-probe-report

# 5. 清理临时文件
rm -rf .tmp-probe-accounts
```

**工作流程**:
1. `probe-gpu-agent.mjs` 为每个账号创建临时文件，输出 Agent 调用代码
2. 在 Claude Code 中运行 Agent 并发任务（每个 Agent 调用 `probe-gpu-worker.mjs`）
3. `collect-probe-results.mjs` 收集所有结果，生成汇总报告

**性能对比**（10 个账号，每个 3 分钟）:
- 顺序执行: 30 分钟
- probe-gpu.mjs (并发=5): 6 分钟
- **probe-gpu-agent.mjs: 3-4 分钟** ⚡

**与 probe-gpu.mjs 的区别**:

| 特性 | probe-gpu.mjs | probe-gpu-agent.mjs |
|------|---------------|---------------------|
| 并发方式 | 自定义并发池（单进程） | Agent 多进程并发 |
| 适用环境 | 任何 Node.js 环境 | Claude Code 环境 |
| 速度 | 快 | 更快（真正并行） |
| 隔离性 | 共享进程 | 完全隔离 |
| 推荐场景 | 命令行、CI/CD | Claude Code 会话 |

**详细文档**: 参见 `README-AGENT-PROBE.md`

---

#### 2. mark-gpu-verified.mjs

**功能**: 解析 probe 报告，生成结构化结果文件

**用法**:

```bash
# 解析报告
node scripts/mark-gpu-verified.mjs --report gpu-probe-report.json

# 指定输出文件
node scripts/mark-gpu-verified.mjs --report gpu-probe-report.json --output result.json
```

**输出**: `gpu-verified-result.json` - 分类后的账号列表（可用/不可用）

---

### 完整工作流

```bash
# 第1步：准备账号文件
cat > accounts.json << EOF
[
  {"username": "user1", "token": "KGAT_xxx"},
  {"username": "user2", "token": "KGAT_yyy"}
]
EOF

# 第2步：探测 GPU
node scripts/probe-gpu.mjs --accounts accounts.json --concurrency=5

# 第3步：解析结果
node scripts/mark-gpu-verified.mjs --report gpu-probe-report.json

# 第4步：使用结果（由调用方决定）
# - 回写数据库
# - 更新 CSV
# - 发送通知
# - 同步到配置系统
```

---

### 账号来源集成

#### 场景1：从数据库读取

```bash
# 私有脚本：从 DB 导出账号
mysql ... -e "SELECT username, access_token as token FROM accounts" > accounts.json

# 调用公共工具
node scripts/probe-gpu.mjs --accounts accounts.json

# 私有脚本：回写结果
node private/write-to-db.mjs --input gpu-verified-result.json
```

#### 场景2：从 CSV 读取

```bash
# 私有脚本：CSV 转 JSON
node private/csv-to-json.mjs accounts.csv > accounts.json

# 调用公共工具
node scripts/probe-gpu.mjs --accounts accounts.json

# 私有脚本：JSON 转 CSV
node private/json-to-csv.mjs gpu-verified-result.json > verified.csv
```

---

### 架构分层

```
┌─────────────────────────────────────┐
│  私有层（业务逻辑）                 │
│  - 从 DB/CSV/Config 读取账号        │
│  - 调用公共工具                      │
│  - 回写结果到 DB/CSV/其他系统       │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│  公共层（纯工具）                   │
│  - probe-gpu.mjs                    │
│  - mark-gpu-verified.mjs            │
│  - 输入：JSON                        │
│  - 输出：JSON                        │
└─────────────────────────────────────┘
```

**关键原则**: 公共工具不知道账号来自哪里、结果去向哪里。分层清晰，可复用性强。
