---
name: cloudflare-ops
description: "通过 Cloudflare API 管理任意账号的 zone、DNS、缓存规则、purge、域名设置与 Ruleset。Workers/R2/KV/Zero Trust 使用官方 MCP 或 wrangler。"
---

## 浏览器到 API 的强制演进

本 skill 只要以浏览器执行远端业务动作，就必须先读并遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)。登录、验证码、2FA、纯视觉验收可保留浏览器；认证后的可接口化动作仍须抓取、复现、独立回验，并在同一任务自更新本 skill 与脚本。

# cloudflare-ops

通用 Cloudflare API 操作封装。**可开源、不含私有信息。** 适合任何需要管理 CF zones/cache-rules/purge 的项目。

## 何时用

- 管理任意 Cloudflare 账号的 zone、DNS 记录、缓存规则、清缓存、Zone 设置、Ruleset（重定向、Transform、Origin、WAF、限流）。
- 封装没覆盖的 zone 级 endpoint 用 `api` 透传。
- 不用于 Workers/Pages/R2/KV/D1/Zero Trust/Tunnel：改用官方 `cloudflare` MCP plugin 与 `wrangler`。

## 核心流程

1. 准备 `CF_API_TOKEN`（环境变量或 profile 配置文件），见 [setup.md](references/setup.md)。
2. `node "<skill-dir>/scripts/cf-api.mjs" verify` 确认 token 有效。
3. 执行子命令：`zones`、`dns`、`cache`、`purge`、`settings`、`ruleset`、`api`，带 `--zone` 与可选 `--profile`。
4. 写操作后用对应 `list`/`get` 回读确认结果。

## 硬规则

- Token 按优先级取：环境变量 → profile 配置文件；不 hardcode 在脚本里。
- Token 只授予本次操作需要的权限（Zone Read、DNS Edit、Cache Rules Edit、Cache Purge 等）。
- 多账号一账号一配置文件，`--profile <name>` 切换。
- `update` 只改传入字段；规则 id 不变。
- Zone 开关一律走 `settings get/set`，不为单个开关写子命令。
- 各类规则一律走 `ruleset --phase`，不为每种 rule 写死字段。
- 本 skill 不含私有 zone 与业务配置；这些放私有 skill 并 export 环境变量后调用。

## 路由表

| 任务 | references | 执行脚本 |
|---|---|---|
| 特性、Token 权限、配置文件、多 profile、`known_zones` | [setup.md](references/setup.md) | `config.example.json` |
| verify、zones、dns、cache、purge、settings、ruleset、api 透传 | [commands.md](references/commands.md) | `scripts/cf-api.mjs` |
| 私有层封装方式、常见问题 | [private-layer-faq.md](references/private-layer-faq.md) | — |
