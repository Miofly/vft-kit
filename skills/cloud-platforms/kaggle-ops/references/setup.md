# 特性、安装与凭据

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

## 配置文件示例

见 `config.example.json`。
