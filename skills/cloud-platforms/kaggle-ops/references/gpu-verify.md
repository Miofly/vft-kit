# GPU 验证

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
node "<skill-dir>/scripts/probe-gpu.mjs" --accounts accounts.json

# accounts.json 格式：
# [
#   {"username": "user1", "token": "KGAT_xxx"},
#   {"username": "user2", "token": "KGAT_yyy"}
# ]

# 方式2：单个账号
node "<skill-dir>/scripts/probe-gpu.mjs" --username user1 --token KGAT_xxx

# 方式3：环境变量
export KAGGLE_USERNAME=user1
export KAGGLE_API_TOKEN=KGAT_xxx
node "<skill-dir>/scripts/probe-gpu.mjs"
```

**参数**:
- `--accounts <file>` - JSON 账号列表文件
- `--username <name>` - 单个账号用户名
- `--token <token>` - 单个账号 token
- `--limit=N` - 只测试前 N 个账号
- `--concurrency=N` - 并发数（建议 3-5）
- `--accelerator <type>` - 指定 GPU 型号（默认 NvidiaTeslaT4）
- `--poll-max=N` - 单账号等待终态的最长秒数（默认 300，最小 120）
- `--output <prefix>` - 报告文件名前缀（默认 `gpu-probe-report`）
- `--slug-prefix <p>` - probe kernel 的 slug 前缀（默认 `kaggle-`）。账号池规范要求 Kaggle 资源一律 `kaggle-` 开头，改这里适配其他约定
- `--keep-remote` - 探测后保留远端 probe kernel（默认删除，否则每轮探测会在每个账号留下一个垃圾 kernel）

**凭据隔离**: 探测时用临时 `HOME` + `KAGGLE_API_TOKEN` 注入凭据，并显式清掉宿主的
`KAGGLE_USERNAME` / `KAGGLE_KEY` / `KAGGLE_CONFIG_DIR`。否则 kaggle CLI 2.x 会回落到
`~/.kaggle/kaggle.json`，用宿主账号去 push，探测结果记到别人头上。

**输出**:
- `<仓库根>/other/temp/kaggle/<prefix>[-<accelerator>].json` / `.csv`
- 仓库根用「从脚本目录向上找第一个含 `other/` 的祖先」定位，不数固定层数：本脚本在插件树里的
  深度会变，硬编码层数曾把报告写到 `project/other`，导致下游汇总脚本读不到。找不到 `other/`
  时回落到系统临时目录。

#### 2. mark-gpu-verified.mjs

**功能**: 解析 probe 报告，生成结构化结果文件

**用法**:

```bash
# 解析报告
node "<skill-dir>/scripts/mark-gpu-verified.mjs" --report gpu-probe-report.json

# 指定输出文件
node "<skill-dir>/scripts/mark-gpu-verified.mjs" --report gpu-probe-report.json --output result.json
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
node "<skill-dir>/scripts/probe-gpu.mjs" --accounts accounts.json --concurrency=5

# 第3步：解析结果
node "<skill-dir>/scripts/mark-gpu-verified.mjs" --report gpu-probe-report.json

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
node "<skill-dir>/scripts/probe-gpu.mjs" --accounts accounts.json

# 私有脚本：回写结果
node private/write-to-db.mjs --input gpu-verified-result.json
```

#### 场景2：从 CSV 读取

```bash
# 私有脚本：CSV 转 JSON
node private/csv-to-json.mjs accounts.csv > accounts.json

# 调用公共工具
node "<skill-dir>/scripts/probe-gpu.mjs" --accounts accounts.json

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
