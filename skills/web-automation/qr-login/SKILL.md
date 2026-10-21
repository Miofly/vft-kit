---
name: qr-login
description: "使用浏览器完成掘金、知乎、简书、头条、博客园、51CTO、CSDN、SegmentFault、小红书、少数派的扫码登录，并通过 PushPlus/ntfy 推送二维码。"
---

# 第三方平台扫码登录

用 ego-lite 隔离空间打开登录页，抓取微信 OAuth 码、公众号码、小程序码或站内 App 码，经 PushPlus（ntfy 附加）推给用户扫码，再接管同一空间复核登录态。

## 何时用

- 用户要登录掘金、知乎、简书、今日头条、博客园、51CTO、CSDN、SegmentFault、小红书（主站/创作平台）、少数派之一。
- 只支持这十个平台；其余平台不要自动套用。
- 给 ArtiPub/文章发布助手（Chrome 扩展）准备登录态时先确认目标，见 [policies.md](references/policies.md)。

## 浏览器到 API 的强制演进

本 skill 只要以浏览器执行远端业务动作，就必须先读并遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)。登录、验证码、2FA、纯视觉验收可保留浏览器；认证后的可接口化动作仍须抓取、复现、独立回验，并在同一任务自更新本 skill 与脚本。

## 核心流程

```js
const task = await useOrCreateTaskSpace('qr-login-<平台>')
```

1. 读 [policies.md](references/policies.md)（API 优先、自我演进、登录态边界）。
2. 查 [site-matrix.md](references/site-matrix.md) 定平台入口与分支；一个 `ego-browser nodejs` heredoc 完成整个浏览器阶段。
3. 强制刷新首页判定登录态；已登录直接报告。未登录时真实鼠标点击入口，按分支取码写 `imageFile`。
4. 对话里先说明 `正在执行：{action}；对象：{subject}；扫码后：{effect}`，再跑 `scripts/notify-qr.py` 推送。
5. 停止浏览器操作，等用户回复「继续」；复用同一 task space 按矩阵复核登录态。
6. 删除 `imageFile`，`completeTaskSpace(task.id, { keep: false })`。

逐步细则见 [main-flow.md](references/main-flow.md)。

## 硬规则

- 全程在 ego 隔离空间后台完成：不 `open_application`、不激活窗口、不弹桌面通知。
- 掘金、知乎默认码不是微信，必须按矩阵进入微信入口；今日头条保留默认 App 码并发完整扫码卡片。
- 触发 popup 的点击用 ego `click({ x, y })` 真实鼠标；禁止 DOM `el.click()`。
- 保留平台创建的原始 OAuth target，禁止复制 OAuth URL 到新 tab（掘金会报 `error_code: 4`）。
- 切换到普通码后必须确认 `.js_switchToNormal` 不可见且 `img.js_qrcode_img` 可见宽高不少于 100px。
- 不输出二维码内容、OAuth URL、图床链接、Cookie 或 Token。
- 二维码过期从登录页重新取得新 state，不刷新、不复制旧 URL，不推送旧码。
- 只有输出同时含 `upload: ok` 与 PushPlus `code: 200` 才算交付成功；ntfy failed 只报告不阻塞。
- 缺 `PUSHPLUS_TOKEN` 时不上传公网，改把本地二维码作为对话附件交给用户。
- 推送后不轮询、不 `handOffTaskSpace`；用户明确要求浏览器内接管才 handoff。
- 未实扫的分支只能写“二维码确认”；登录成功必须按矩阵多项同时满足。
- ego 登录成功不代表 Chrome 扩展已可用；两套登录态独立处理。

## 路由表

| 任务 | references | 执行脚本 |
|---|---|---|
| API 优先、抓包演进、扩展登录态边界 | [policies.md](references/policies.md) | — |
| 平台入口、选择器、码形态、成功判定 | [site-matrix.md](references/site-matrix.md) | — |
| 标准 OAuth 主流程（掘金、知乎、简书）与抓码代码 | [main-flow.md](references/main-flow.md) | `ego-browser nodejs` |
| 今日头条、SegmentFault、博客园/51CTO、CSDN、小红书、少数派分支 | [branches.md](references/branches.md) | `ego-browser nodejs` |
| 推送二维码、env 变量、ntfy 语义 | [notify-env.md](references/notify-env.md) | `scripts/notify-qr.py`（自测 `scripts/test_notify_qr.py`） |
