---
name: cloudflare-ops
description: >-
  通用 Cloudflare API 操作封装:zones 查询、DNS 记录 CRUD、Cache Rules CRUD、purge 缓存(URL/tag/host/prefix)、Zone 设置 get/set、Ruleset 通用命令(redirect/transform/origin/waf 等所有 phase)、通用 API 透传。
  零依赖(Node 18+),多 profile 支持。token 从环境变量或配置文件读取(优先级:环境变量 > config file)。
  子命令:verify、zones、dns、cache、purge、settings、ruleset、api。
  适合任何 Cloudflare 账号,不含私有信息。Workers/R2/KV/Zero Trust 走官方 cloudflare MCP + wrangler,本 skill 专注 zone/HTTP 域名级运维。
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

## 子命令

> 每个命令都支持 `--profile <name>` 切账号、`--zone <域名或zone_id>` 指定 zone。

### verify — 验证 token
```bash
node scripts/cf-api.mjs verify
```

### zones — 列所有 zones(已分页,不再截断 50)
```bash
node scripts/cf-api.mjs zones
```

### dns — DNS 记录 CRUD
```bash
# 列出(可按类型过滤)
node scripts/cf-api.mjs dns list --zone example.com [--type A]
# 查单条
node scripts/cf-api.mjs dns get <record-id> --zone example.com
# 新增(A/AAAA/CNAME/TXT/MX/NS/SRV...);--proxied 走橙云,--ttl 1=自动
node scripts/cf-api.mjs dns add --zone example.com --type CNAME --name www --content example.com --proxied true
node scripts/cf-api.mjs dns add --zone example.com --type MX --name @ --content mail.example.com --priority 10
# 更新(只改传入字段)
node scripts/cf-api.mjs dns update <record-id> --zone example.com --content 5.6.7.8
# 删除
node scripts/cf-api.mjs dns delete <record-id> --zone example.com
```

### cache — 缓存规则 CRUD(cache phase)
```bash
# 新增:--edge 边缘 TTL,--browser 浏览器 TTL,--first 排最前
node scripts/cf-api.mjs cache add \
  --expr '(http.request.method eq "GET" and not starts_with(http.request.uri.path, "/admin-api"))' \
  --edge 86400 --browser 3600 --desc "cache-all-get" --zone example.com
#   --edge / --browser 取值:respect_origin | bypass | <秒数(override)>
# 列出
node scripts/cf-api.mjs cache list --zone example.com
# 更新(只改传入字段,规则 id 不变)
node scripts/cf-api.mjs cache update <rule-id> --zone example.com --edge 3600
# 删除
node scripts/cf-api.mjs cache delete <rule-id> --zone example.com
```

### purge — 清缓存
```bash
# 全站
node scripts/cf-api.mjs purge --zone example.com
# 指定 URL
node scripts/cf-api.mjs purge https://example.com/ https://example.com/blog --zone example.com
# 按 tag / host / prefix(企业版,逗号分隔)
node scripts/cf-api.mjs purge --zone example.com --tags tagA,tagB
node scripts/cf-api.mjs purge --zone example.com --hosts a.example.com,b.example.com
node scripts/cf-api.mjs purge --zone example.com --prefixes example.com/blog,example.com/docs
```

### settings — Zone 设置 get/set(通用,覆盖所有开关)
一对命令覆盖全部 zone 开关(ssl、min_tls_version、brotli、http3、always_online、development_mode、early_hints、websockets、0rtt…),不为每个开关写单独子命令。
```bash
# 读全部 / 读单个
node scripts/cf-api.mjs settings get --zone example.com
node scripts/cf-api.mjs settings get ssl --zone example.com
# 设置:value 是字符串直接写,是对象/数字用 JSON(注意 shell 引号)
node scripts/cf-api.mjs settings set ssl full --zone example.com
node scripts/cf-api.mjs settings set brotli on --zone example.com
node scripts/cf-api.mjs settings set min_tls_version '"1.2"' --zone example.com
```

### ruleset — 通用 Ruleset(覆盖 redirect/transform/origin/waf 等所有 phase)
一套命令覆盖 Redirect Rules、Transform Rules、Origin Rules、Config Rules、WAF Custom Rules、Rate Limiting——靠 `--phase` 别名切 phase,`--params` 吃任意 action_parameters JSON,不为每种 rule 写死字段。

phase 别名:`cache` / `redirect` / `transform` / `late-transform` / `origin` / `config` / `waf-custom` / `ratelimit`(也可直接写 CF 全名)。
```bash
# 列出该 zone 所有 ruleset
node scripts/cf-api.mjs ruleset list --zone example.com
# 查某 phase 的完整规则
node scripts/cf-api.mjs ruleset get --phase redirect --zone example.com
# 加一条动态重定向(该 phase 无 ruleset 时自动创建 entrypoint)
node scripts/cf-api.mjs ruleset rule add --phase redirect --action redirect \
  --expr '(http.host eq "old.com")' \
  --params '{"from_value":{"target_url":{"value":"https://new.com"},"status_code":301,"preserve_query_string":true}}' \
  --zone example.com
# 删一条规则
node scripts/cf-api.mjs ruleset rule delete <rule-id> --phase redirect --zone example.com
```

### api — 通用 CF API 透传(token 权限内任意 endpoint)
封装没覆盖到的 endpoint(Workers、SSL 证书、Load Balancer、Analytics 等)一律走这里。
```bash
node scripts/cf-api.mjs api GET /zones/<zone-id>/rulesets
node scripts/cf-api.mjs api POST /zones/<zone-id>/purge_cache '{"purge_everything":true}'
```

> **边界**:本 skill 专注 zone/HTTP 域名级运维。Workers/Pages/R2/KV/D1/Zero Trust/Tunnel 请用官方 `cloudflare` MCP plugin + `wrangler` CLI(你环境已装),别在这里重复造轮子;临时需要也可用 `api` 透传打。

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
