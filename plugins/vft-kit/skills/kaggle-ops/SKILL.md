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
