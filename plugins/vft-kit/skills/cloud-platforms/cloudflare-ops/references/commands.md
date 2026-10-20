# 子命令（cf-api.mjs）

## 子命令

下文 `<skill-dir>` 指当前 `SKILL.md` 所在目录的绝对路径，由 Claude Code 或 Codex 从已加载 skill 位置解析；不要按当前工作目录猜测。

> 每个命令都支持 `--profile <name>` 切账号、`--zone <域名或zone_id>` 指定 zone。

### verify — 验证 token
```bash
node "<skill-dir>/scripts/cf-api.mjs" verify
```

### zones — 列所有 zones(已分页,不再截断 50)
```bash
node "<skill-dir>/scripts/cf-api.mjs" zones
```

### dns — DNS 记录 CRUD
```bash
# 列出(可按类型过滤)
node "<skill-dir>/scripts/cf-api.mjs" dns list --zone example.com [--type A]
# 查单条
node "<skill-dir>/scripts/cf-api.mjs" dns get <record-id> --zone example.com
# 新增(A/AAAA/CNAME/TXT/MX/NS/SRV...);--proxied 走橙云,--ttl 1=自动
node "<skill-dir>/scripts/cf-api.mjs" dns add --zone example.com --type CNAME --name www --content example.com --proxied true
node "<skill-dir>/scripts/cf-api.mjs" dns add --zone example.com --type MX --name @ --content mail.example.com --priority 10
# 更新(只改传入字段)
node "<skill-dir>/scripts/cf-api.mjs" dns update <record-id> --zone example.com --content 5.6.7.8
# 删除
node "<skill-dir>/scripts/cf-api.mjs" dns delete <record-id> --zone example.com
```

### cache — 缓存规则 CRUD(cache phase)
```bash
# 新增:--edge 边缘 TTL,--browser 浏览器 TTL,--first 排最前
node "<skill-dir>/scripts/cf-api.mjs" cache add \
  --expr '(http.request.method eq "GET" and not starts_with(http.request.uri.path, "/admin-api"))' \
  --edge 86400 --browser 3600 --desc "cache-all-get" --zone example.com
#   --edge / --browser 取值:respect_origin | bypass | <秒数(override)>
# 列出
node "<skill-dir>/scripts/cf-api.mjs" cache list --zone example.com
# 更新(只改传入字段,规则 id 不变)
node "<skill-dir>/scripts/cf-api.mjs" cache update <rule-id> --zone example.com --edge 3600
# 删除
node "<skill-dir>/scripts/cf-api.mjs" cache delete <rule-id> --zone example.com
```

### purge — 清缓存
```bash
# 全站
node "<skill-dir>/scripts/cf-api.mjs" purge --zone example.com
# 指定 URL
node "<skill-dir>/scripts/cf-api.mjs" purge https://example.com/ https://example.com/blog --zone example.com
# 按 tag / host / prefix(企业版,逗号分隔)
node "<skill-dir>/scripts/cf-api.mjs" purge --zone example.com --tags tagA,tagB
node "<skill-dir>/scripts/cf-api.mjs" purge --zone example.com --hosts a.example.com,b.example.com
node "<skill-dir>/scripts/cf-api.mjs" purge --zone example.com --prefixes example.com/blog,example.com/docs
```

### settings — Zone 设置 get/set(通用,覆盖所有开关)
一对命令覆盖全部 zone 开关(ssl、min_tls_version、brotli、http3、always_online、development_mode、early_hints、websockets、0rtt…),不为每个开关写单独子命令。
```bash
# 读全部 / 读单个
node "<skill-dir>/scripts/cf-api.mjs" settings get --zone example.com
node "<skill-dir>/scripts/cf-api.mjs" settings get ssl --zone example.com
# 设置:value 是字符串直接写,是对象/数字用 JSON(注意 shell 引号)
node "<skill-dir>/scripts/cf-api.mjs" settings set ssl full --zone example.com
node "<skill-dir>/scripts/cf-api.mjs" settings set brotli on --zone example.com
node "<skill-dir>/scripts/cf-api.mjs" settings set min_tls_version '"1.2"' --zone example.com
```

### ruleset — 通用 Ruleset(覆盖 redirect/transform/origin/waf 等所有 phase)
一套命令覆盖 Redirect Rules、Transform Rules、Origin Rules、Config Rules、WAF Custom Rules、Rate Limiting——靠 `--phase` 别名切 phase,`--params` 吃任意 action_parameters JSON,不为每种 rule 写死字段。

phase 别名:`cache` / `redirect` / `transform` / `late-transform` / `origin` / `config` / `waf-custom` / `ratelimit`(也可直接写 CF 全名)。
```bash
# 列出该 zone 所有 ruleset
node "<skill-dir>/scripts/cf-api.mjs" ruleset list --zone example.com
# 查某 phase 的完整规则
node "<skill-dir>/scripts/cf-api.mjs" ruleset get --phase redirect --zone example.com
# 加一条动态重定向(该 phase 无 ruleset 时自动创建 entrypoint)
node "<skill-dir>/scripts/cf-api.mjs" ruleset rule add --phase redirect --action redirect \
  --expr '(http.host eq "old.com")' \
  --params '{"from_value":{"target_url":{"value":"https://new.com"},"status_code":301,"preserve_query_string":true}}' \
  --zone example.com
# 删一条规则
node "<skill-dir>/scripts/cf-api.mjs" ruleset rule delete <rule-id> --phase redirect --zone example.com
```

### api — 通用 CF API 透传(token 权限内任意 endpoint)
封装没覆盖到的 endpoint(Workers、SSL 证书、Load Balancer、Analytics 等)一律走这里。
```bash
node "<skill-dir>/scripts/cf-api.mjs" api GET /zones/<zone-id>/rulesets
node "<skill-dir>/scripts/cf-api.mjs" api POST /zones/<zone-id>/purge_cache '{"purge_everything":true}'
```

> **边界**:本 skill 专注 zone/HTTP 域名级运维。Workers/Pages/R2/KV/D1/Zero Trust/Tunnel 请用官方 `cloudflare` MCP plugin + `wrangler` CLI(你环境已装),别在这里重复造轮子;临时需要也可用 `api` 透传打。
