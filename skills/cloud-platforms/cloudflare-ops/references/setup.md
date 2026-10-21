# 特性、Token 与配置

## 特性

- ✅ **多 profile 支持**:一个脚本管理多个 CF 账号,`--profile <name>` 切换
- ✅ **零依赖**:Node 18+ 内置 fetch
- ✅ **密钥外部化**:token 从环境变量或配置文件读,不 hardcode
- ✅ **常见操作封装**:zones/cache-rules/purge,比直接调 API 方便
- ✅ **通用 API 透传**:任何 CF API endpoint 都能打(`api` 子命令)

## Prerequisites

### 1. CF_API_TOKEN

所有操作需要 Cloudflare API Token。**按优先级查找,用第一个找到的**:

```
1. 环境变量(最高优先级)
   export CF_API_TOKEN=your-token-here

2. 配置文件(见下方 "Optional config")
   读取 <profile>.json 的 api_token 字段
```

**Token 权限要求**(根据你的操作):
- 查 zones:Zone > Zone > Read
- DNS 记录:Zone > DNS > Edit
- 缓存规则 / ruleset:Zone > Cache Rules > Edit + Zone > Config Rules 等对应 phase 权限
- Zone 设置:Zone > Zone Settings > Edit
- 清缓存:Zone > Cache Purge

**首次设置**:复制本目录下 `config.example.json` 到你选择的位置(项目根或 `~/.config/cloudflare/`),填入 token:

```json
{
  "api_token": "your-token-here",
  "known_zones": {
    "example.com": "your-zone-id-here"
  }
}
```

### 2. Node.js 18+

脚本用 `fetch` API,需 Node 18+:
```bash
node --version  # 确认 >= 18
```

### 3. (可选)jq

格式化 JSON 输出时用:
```bash
brew install jq  # macOS
```

### 4. Optional config

Token 配置文件**也可以**携带这些可选键(如果存在,应用;如果不存在,跳过):

| 键 | 作用 |
|----|------|
| `known_zones` | 域名 → zone ID 映射。子命令可直接用域名,脚本自动解析成 zone ID |
| `default_profile` | 省略 `--profile` 时用哪个 profile(默认 `default`) |

**多 profile 模式**:
```
~/.config/cloudflare/
├── default.json      # 主账号
├── staging.json      # 测试账号
└── client-x.json     # 客户账号
```
脚本用 `--profile staging` 选择,每个文件格式相同(api_token + 可选 known_zones)。

## 配置文件示例

见 `config.example.json`。
