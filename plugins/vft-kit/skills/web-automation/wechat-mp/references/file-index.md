# 文件清单

## 参考文件

- `references/console.md` — 开发者平台控制台：tab URL 规则、AppSecret/IP 白名单位置、接口权限与额度的抓取脚本
- `references/mp-backend.md` — 公众平台后台：页面清单、素材库/发表记录/用户管理的读取方式、编辑器 DOM 结构备忘
- `scripts/md-to-mp-html.mjs` — Markdown → 公众号 inline-style HTML（带 `--selftest`）
- `references/miniprogram-release.md` — 小程序：CLI 上传、体验版、提审流程、隐私选项、`/wxamp` 接口与 API 化进度
- `scripts/wxamp-version-status.mjs` — 小程序版本状态（只读）
- `scripts/wxamp-submit-audit-api.mjs` — 小程序提交审核（接口版，首选）
- `scripts/wxamp-submit-audit.mjs` — 小程序提交审核（页面流程兜底，真实点击；默认拦住，接口版失败时在脚本前加 `globalThis.FORCE_PAGE = true` 才运行）
- `references/miniprogram-devtools.md` — 小程序开发者工具 CLI、模拟器自动化、连本地后端、广告与分享规则
- `scripts/mp-ci.mjs` — miniprogram-ci 上传 / 预览（无界面，带 `--selftest`）
- `scripts/miniprogram-automator-helpers.cjs` — automator 测试公共函数：请求打桩、插屏计数、断言汇总（带 `--selftest`）
- `references/wxapkg-unpack.md` — 小程序反编译：扫描缓存、定位 wxid、解包、还原 WXSS、复刻要点
- `scripts/wxapkg/wxapkg.sh` — wxapkg 扫描 / 解包 CLI（带 `selftest`）；`scripts/wxapkg/extract-wxss.mjs` — 还原 WXSS；`scripts/wxapkg/split-service.mjs` — 拆 `app-service.js` 并导出数据 JSON（带 `--selftest`）
