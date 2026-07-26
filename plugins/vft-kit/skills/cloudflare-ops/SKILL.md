---
name: cloudflare-ops
description: >-
  通用 Cloudflare API 操作封装:zones 查询、Cache Rules CRUD、purge 缓存、通用 API 透传。
  零依赖(Node 18+),多 profile 支持。token 从环境变量或配置文件读取(优先级:环境变量 > config file)。
  子命令:verify(验证 token)、zones(列 zones)、cache add/list/delete(缓存规则)、purge(清缓存)、api(通用透传)。
  适合任何 Cloudflare 账号,不含私有信息。
trigger: []
---

# cloudflare-ops

通用 Cloudflare API 操作封装。**可开源、不含私有信息。** 适合任何需要管理 CF zones/cache-rules/purge 的项目。

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
- 缓存规则:Zone > Cache Rules > Edit + Account Rulesets > Edit
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

## 子命令

### verify
验证 token 是否有效:
```bash
node scripts/cf-api.mjs verify
node scripts/cf-api.mjs verify --profile staging
```

### zones
列出所有 zones:
```bash
node scripts/cf-api.mjs zones
node scripts/cf-api.mjs zones --profile staging
```

### cache add
新增一条缓存规则:
```bash
# 缓存所有 GET 请求(非 /admin-api),边缘 TTL 1天
node scripts/cf-api.mjs cache add \
  --expr '(http.request.method eq "GET" and not starts_with(http.request.uri.path, "/admin-api"))' \
  --edge 86400 \
  --desc "cache-all-get" \
  --zone example.com

# --edge 选项:
#   respect_origin  = 遵循源站 Cache-Control
#   bypass          = 有 cache-control 才缓存
#   <秒数>          = 强制边缘缓存 N 秒(override_origin)

# --first: 把新规则排到最前(position.before)
```

### cache list
列出某 zone 的所有缓存规则:
```bash
node scripts/cf-api.mjs cache list --zone example.com
```

### cache delete
删除一条缓存规则:
```bash
node scripts/cf-api.mjs cache delete <rule-id> --zone example.com
```

### purge
清缓存:
```bash
# 全站清(purge_everything)
node scripts/cf-api.mjs purge --zone example.com

# 只清指定 URL
node scripts/cf-api.mjs purge https://example.com/ https://example.com/blog --zone example.com
```

### api
通用 CF API 透传(token 权限内任意 endpoint):
```bash
node scripts/cf-api.mjs api GET /zones/<zone-id>/rulesets
node scripts/cf-api.mjs api POST /zones/<zone-id>/purge_cache '{"purge_everything":true}'
```

## 配置文件示例

见 `config.example.json`。

## 与私有 skill 的关系

本 skill 是**通用基础**,不知道你的私有配置(zone ID/域名/业务场景)。私有项目应:
1. 创建私有 skill(如 `my-project-cdn`)
2. 在私有 skill 的 config.json 里定义 zone ID/域名
3. 私有 skill 的 SKILL.md 说明触发场景 + 如何调用本 skill

示例:私有 skill 说"清缓存",它读自己的 config.json 拿到 zone ID,从 `.secrets` 读 token,export 成环境变量,再调本 skill 的 `purge` 子命令。

## 常见问题

**Q: Token 放哪最安全?**
A: 环境变量(临时) > 配置文件在 `.secrets/` 并 gitignore(持久)。不要 hardcode 在脚本里。

**Q: 多账号怎么管理?**
A: 一账号一配置文件,`--profile <name>` 切换。文件名 = profile 名。

**Q: 为什么不用官方 Cloudflare MCP plugin?**
A: 官方 plugin 是通用 API 透传,本 skill 封装了"缓存规则 CRUD"这类高频操作的便利层,减少重复代码。两者可共存。

**Q: known_zones 必须配吗?**
A: 不必须。如果没配,脚本会调 API 自动解析域名 → zone ID(需 Zone Read 权限)。配了能减少 API 调用。
