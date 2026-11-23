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
- `references/tiktok-minis.md` — TikTok Minis：link 接口取 minis_url、判断 H5 型、抓前端产物、读码要点与案例
- `scripts/wxapkg/wxapkg.sh` — wxapkg 扫描 / 解包 CLI（带 `selftest`）；`scripts/wxapkg/extract-wxss.mjs` — 还原 WXSS；`scripts/wxapkg/split-service.mjs` — 拆 `app-service.js` 并导出数据 JSON（带 `--selftest`）
- `scripts/wxapkg/export-game.py` — 小游戏归档：原始 wxapkg、已解包发布代码、桌面 define 模块、已访问 Cocos 资源、可选远端 bundle 配置；SHA-256 清单，`--selftest`，不执行目标 JS、不改微信数据
- `scripts/tiktok-minis/fetch.py` — TikTok Minis H5 前端产物抓取（minis_url 或 link 接口 JSON 输入，`--pretty` 格式化）

## 桌面微信发送（原 wechat-bridge）

- `scripts/wechat_bridge.py` — 回环 HTTP 桥（`serve`、`send`、`receipt`）、本机只读 `desktop-mcp`、`desktop-tui`、官方组件接入与协议自检；后端 noop / exec / desktop / upstream
- `scripts/verify_release.py` — 凭可信的发布包 SHA-256，在 macOS 离线核验八个官方组件的清单、哈希和签名；不执行包内程序、不安装
- `scripts/verify_desktop.py` — 对照 CLI、HTTP、MCP、终端控制台的会话与文件助手查询；`--badge-only`、`--contacts-only`、`--moments-only` 分别对照总角标、通讯录和朋友圈可见标签；只报告验收状态和检查数量，不发消息
- `scripts/message_archive.py` / `scripts/test_message_archive.py` — 显式 JSONL 导入、离线历史和搜索、基线与游标补读；不访问微信私库，跨进程回归只使用合成记录
- `references/capability-scope.md` — 上游能力清单、缺口与逐项验收状态
- `references/upstream-notes.md` — wechat-use 上游机制、激活与 build 前置
- `references/qt-native-send-derivation.md` — 从本机微信自算原生发送 profile 的端到端流程与坑
- `references/handoff-2026-11-11.md` — 原生发送研究暂停时的状态交接（仅恢复研究用）
- `scripts/derive_profile.py` — 一条命令从本机微信算出 `profile.json`（版本、切片 sha256、各类 metacall/vtable RVA）
- `scripts/ghidra_macos_bootstrap.sh` — macOS arm64 装出含原生反编译器的 Ghidra
- `scripts/macho_chained_fixups.py` — 解 Mach-O chained fixup
- `scripts/ghidra/*.java` — Ghidra 侧扫元对象/方法表/继承链并吐 JSON
- `scripts/native/wechat_probe.c` — 外部只读探测（核对镜像、vtable、成员归属、filehelper 字段）
- `scripts/native/native_executor.py`、`scripts/native/lldb_runner.py` — 限定 build 的实验发送器（默认仅 filehelper，带 resolve/preflight 与防重发）
- `scripts/native/wechat_send.c`、`scripts/native/build_dylib.sh` — 实验 dylib 底座与编译（发送永久拒绝，不覆盖已加载 dylib）
- `scripts/native/make_clone.sh` — 只准备副本和签名，不自动启动或登录
- `scripts/test_derive_profile.py`、`scripts/native/test_native_executor.py`、`scripts/native/test_native.py` — 离线回归，不附着微信、不发送
