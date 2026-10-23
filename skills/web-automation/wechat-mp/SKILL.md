---
name: wechat-mp
description: "公众号后台与微信开发者控制台：登录、草稿排版、发布、素材、IP 白名单、40164/48001；小程序：开发者工具 CLI、automator 自测、miniprogram-ci 上传体验版、提审发布、版本状态、广告分享规则、反编译 wxapkg 复刻样式；TikTok Minis（tiktok.com/minis 链接）抓 H5 前端学习。"
---

# 微信公众号 / 开发者平台自动化

用 ego-lite 复用登录态操作公众平台（草稿、素材、发表）与开发者平台（密钥、白名单、接口权限），并用 CLI/接口完成小程序上传、提审、版本查询和反编译复刻。

## 何时用

- 公众号：Markdown 转草稿、配图与封面、发表、素材/发表记录/用户管理读取。
- 开发者平台：AppID/AppSecret、IP 白名单、接口权限与额度，排查 `40164`/`48001`。
- 小程序：开发者工具 CLI、automator 自测、miniprogram-ci 上传体验版、提审与发布、版本状态、广告分享规则、wxapkg 反编译复刻。

## 浏览器到 API 的强制演进

本 skill 只要以浏览器执行远端业务动作，就必须先读并遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)。登录、验证码、2FA、纯视觉验收可保留浏览器；认证后的可接口化动作仍须抓取、复现、独立回验，并在同一任务自更新本 skill 与脚本。

## 核心流程（发文到草稿箱）

1. 读 [policies.md](references/policies.md)；`useOrCreateTaskSpace('wechat mp <做什么>')` 复用登录态，见 [login.md](references/login.md)。
2. 从当前页面 URL 现取 `token`，确认右上角账号名。
3. `node scripts/md-to-mp-html.mjs article.md --json` 转 inline-style HTML。
4. 开 `isNew=1` 新编辑器页，等编辑器初始化；标题 `insertText`，正文合成 paste。
5. 关弹窗后点「保存为草稿」，URL 出现 `appmsgid=` 即成功。
6. 用户明确要求发表时才走发表流程，以发表记录精确命中标题为准。

逐步代码见 [publish-article.md](references/publish-article.md)。

## 硬规则

- 改密钥、白名单、看接口权限一律去开发者平台；公众平台那页只剩迁移通知。
- 不去 `.secrets` 找密码；只有实际出现扫码/确认步骤才 `handOffTaskSpace`。
- `token` 每次登录都变，永远从当前页面 URL 现取，不复用旧 token。
- 每篇文章开 `isNew=1` 新编辑器；不在已有内容页重复 paste。
- 正文用合成 paste 写入，不直接写 `innerHTML`；成功看 `chars`/`h2` 数。
- 图片只走本地上传；封面是发表硬前置，判据是 `.js_cover_preview_new` 背景图含 `mmbiz`。
- 动手前把视口调到 1100 高，或用 `elementFromPoint` 确认命中。
- 除非用户明确说发布/群发，一律停在草稿。
- 发表成功只认发表记录 `publish_list` 按完整标题命中并拿到 `content_url`。
- 管理员验证二维码 `img.qrcode.js_qrcode` 不在 dialog 内，别漏掉。
- 接口能不能调只看开发者平台「接口权限与额度」，不靠记忆。
- AppSecret 重置后旧值立即失效，先确认能同步配置。
- 解除授权、重置密钥、发表、删文、提审与发布动手前先确认。
- 凭据不写进本 skill 或仓库；多账号先核对 `.weui-desktop-account__info`。
- 反编译只用于学习研究或有权使用的设计，不分发解出的源码。

## 路由表

| 任务 | references | 执行脚本 |
|---|---|---|
| API 优先、安全边界、确认规则 | [policies.md](references/policies.md) | — |
| 登录、handoff、远程扫码二维码交付 | [login.md](references/login.md) | `ego-browser nodejs` |
| 两个后台分工、token、公众平台页面清单、编辑器 DOM | [mp-backend.md](references/mp-backend.md) | — |
| Markdown 发草稿、插图、封面、视口、草稿箱发表、管理员扫码 | [publish-article.md](references/publish-article.md) | `scripts/md-to-mp-html.mjs`（`--selftest`） |
| 开发者平台 tab、AppSecret、白名单、接口权限与额度 | [console.md](references/console.md) | `ego-browser nodejs` |
| `40164`、`48001`、粘贴重复、发表无反应等报错 | [troubleshooting.md](references/troubleshooting.md) | — |
| 小程序上传、预览、版本状态、提审 | [miniprogram-release.md](references/miniprogram-release.md) | `scripts/mp-ci.mjs`、`scripts/wxamp-version-status.mjs`、`scripts/wxamp-submit-audit-api.mjs`（兜底 `scripts/wxamp-submit-audit.mjs`） |
| 小程序开发者工具 CLI、automator 自测、本地后端、广告与分享 | [miniprogram-devtools.md](references/miniprogram-devtools.md) | `scripts/miniprogram-automator-helpers.cjs` |
| 反编译 wxapkg、还原 WXSS、复刻到 Taro | [wxapkg-unpack.md](references/wxapkg-unpack.md) | `scripts/wxapkg/wxapkg.sh`、`scripts/wxapkg/extract-wxss.mjs`、`scripts/wxapkg/split-service.mjs` |
| TikTok Minis 链接抓 H5 前端产物学习 | [tiktok-minis.md](references/tiktok-minis.md) | `scripts/tiktok-minis/fetch.py` |
| 全部文件说明 | [file-index.md](references/file-index.md) | — |
