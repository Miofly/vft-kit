---
name: temp-mail
description: "用 tempmail.ing 生成随机临时邮箱、查看收件箱和邮件正文，并提取验证码与验证链接；纯 HTTP 接口，无需登录和浏览器。用户要求随机邮箱、临时邮箱、一次性邮箱、换一个新邮箱、收注册验证码或激活链接时使用。"
---

# 临时邮箱（tempmail.ing）

站点 `https://tempmail.ing/` 的前端直接调 `https://api.tempmail.ing`，接口无鉴权，所以全程用脚本走 HTTP，不开浏览器。

## 脚本

```bash
TM="${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT}}}/skills/web-automation/temp-mail/scripts/tempmail.mjs"

node "$TM" new --duration 30          # 换一个新邮箱，返回 address / expiresAt
node "$TM" inbox <address>            # 收件列表（含 code、links，不含正文）
node "$TM" inbox <address> --json     # 带正文 text（HTML 已转纯文本，截 4000 字）
node "$TM" wait <address> --timeout 180 --subject "verify|验证" --from github
node "$TM" delete <address> <emailId>
node "$TM" selftest                   # 离线检查验证码/链接提取
```

Node 18+，零依赖。结果 JSON 打到 stdout，日志打到 stderr；`wait` 超时退出码 2。

## 接口（2026-10-12 实测）

| 用途 | 方法与路径 | 请求 | 返回 |
|---|---|---|---|
| 换新邮箱 | `POST /api/generate` | `{"duration":10}`，可选 5/10/15/20/30/60 分钟 | `{success, email:{address, expiresAt, createdAt, durationMinutes}}` |
| 看收件箱和正文 | `GET /api/emails/<urlencode(address)>` | 可带 `If-None-Match` 走 304 | `{success, emails:[{id, from_address, subject, text, content, received_at, is_read}]}` |
| 删一封邮件 | `DELETE /api/emails/<id>` | `{"emailAddress":"<address>"}` | `{success}` |

- 收件列表直接带全文：`text` 是纯文本，`content` 是 HTML（网页端把 `content` 当 HTML 渲染）。没有单独的“读一封”接口。
- 地址由服务端随机生成，形如 `mv4uhx3gf37y@imgfx.art`，域名会轮换（见过 `ve0ai.com`、`imgfx.art`），不能自选用户名或域名。
- 到期后地址作废，旧地址的邮件无法再取；要长一点就 `--duration 60`。
- 收件箱没有密码，知道地址的人都能读。不要用它收重要账号或含隐私的邮件。
- `subject` 原样是 RFC 2047 编码（`=?utf-8?B?...?=`），脚本已解码，`--subject` 过滤按解码后的明文匹配。
- 不少大站拉黑这些域名：Notion 报“无效的电子邮件域名”，Substack 报“请输入有效的电子邮件地址”。Perplexity 能收（2026-10-12 实测，发信后约 10 秒到达，验证码和登录链接都提取正确）。被拒时换一个 `new` 拿不同域名再试，仍被拒就说明该站屏蔽临时邮箱。

## 限流与请求头

- 必须带 `Origin: https://tempmail.ing` 和 `Referer`。不带时 Cloudflare 直接返回 429 HTML 页面。
- `generate` 限 10 次/60 秒（响应头 `X-RateLimit-Limit/Remaining/Reset`）。连发太快也会 429，JSON 里带 `retryAfterSeconds`。脚本遇到 429 自动等待后重试，最多 4 次。
- 轮询收件箱间隔不低于 3 秒，默认 5 秒。

## 验证码与链接提取

`code`：先找“验证码/code/OTP/verification”等关键词后面含数字的 4–8 位串，找不到再取正文里唯一的 6 位数字。纯字母验证码不识别，看 `--json` 的 `text` 自己找。

`links`：从 `href` 和正文 URL 去重，含 verify/confirm/activate/token/login/reset 的排在前面，最多 10 条。

改提取规则后跑 `selftest`，并把新样例补进 `selftest()` 的用例表。
