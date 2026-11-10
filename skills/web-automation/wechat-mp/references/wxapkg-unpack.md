# 小程序反编译（wxapkg）

基于 [wux1an/wxapkg](https://github.com/wux1an/wxapkg)。上游 v2 只提供 GUI，本 skill 复用它的 `wechat` Go 包，包装成 CLI `scripts/wxapkg/wxapkg.sh`，并补了按文字定位和 WXSS 还原。

> 只用于学习研究或复刻自己有权使用的设计。不要分发解出的源码，也不要用于绕过授权。

## 前置

- 需要 `git`、`go`（>= 1.25）和 `node`。首次运行时自动 clone 上游并编译到 `~/.cache/vft-kit/wxapkg/bin/wxapkg-cli`。
- clone 或 `go build` 超时时，先设代理再重试：`export https_proxy=http://127.0.0.1:7890 GOPROXY=https://goproxy.cn,direct`。
- 自检：`scripts/wxapkg/wxapkg.sh selftest`。这条命令会造一个最小 wxapkg，然后解包验证，输出 `selftest ok` 即可用。

## 流程

`S` 为 wechat-mp skill 目录下的 `scripts/wxapkg/wxapkg.sh`，`OUT` 为临时产物目录（不要放进项目源码目录）。

1. **在电脑版微信里打开目标小程序**，把目标页面都点一遍，让分包也缓存下来。
2. **定位 wxid**。用页面上看得见的文字搜索，搜索时会自动解密包内容：
   ```bash
   $S scan -grep "页面上的一句独特文案"     # 多个关键词分别试
   $S scan -n 10                              # 或按最近修改时间列出，刚打开的排最前
   ```
   输出格式为 `wxid  修改时间  大小  包数量  [encrypted]  版本目录`。
3. **解包**。按 wxid 解包时自动取最新版本目录，解密密钥就是 wxid：
   ```bash
   $S unpack wx0123456789abcdef -o "$OUT"     # 解到 $OUT/<wxid>/
   ```
   也可以直接传版本目录或单个 `.wxapkg` 文件。加 `-no-beautify` 跳过 JS/HTML/JSON 美化。
4. **还原 WXSS**：
   ```bash
   node <wechat-mp>/scripts/wxapkg/extract-wxss.mjs "$OUT/<wxid>"
   ```
   脚本会生成 `app.wxss`、`pages/**/x.wxss` 和 `components/**/index.wxss`。新版基础库把每页样式放在 `pages/**/x.html` 里，而不是 `page-frame.html`，脚本两处都扫。
5. **拆分逻辑与导出数据**：
   ```bash
   node <wechat-mp>/scripts/wxapkg/split-service.mjs "$OUT/<wxid>"
   ```
   `app-service.js` 按 `define()` 拆到 `_modules/<原路径>`；纯数据模块（城市表、话术、文章等 `module.exports = {...}`）导出到 `_data/<路径>.json`。移植数据时从 JSON 生成 TS，不要让 LLM 手抄，长段中文法条手抄必然漏字改字。

## 小游戏代码与资源归档

小游戏没有 `app-service.js` 时，不跑 `split-service.mjs`。电脑版 Cocos 包常在主包及分包的 `game.js` 中使用 `define("path", function(require, module, exports){…})`；用 `scripts/wxapkg/export-game.py` 归档，保留 wrapper 原文，不执行第三方 JS。

```bash
python3 "$WECHAT_MP_SKILL_DIR/scripts/wxapkg/export-game.py" --selftest
python3 "$WECHAT_MP_SKILL_DIR/scripts/wxapkg/export-game.py" \
  --packages "$WX_PACKAGE_VERSION_DIR" --user-dir "$WX_APP_LOCAL_DIR" \
  --wxid "$WX_APPID" --output "$GAME_ARCHIVE_DIR" \
  --remote-configs --proxy http://127.0.0.1:7890
```

以上变量均由调用方设为绝对路径；先用 `wxapkg.sh` 确保 CLI 已构建。`--packages` 是包含 `.wxapkg` 的版本目录，`--user-dir` 是同一账号和 AppID 的 `applet/local/<wxid>`，`--output` 必须是全新的归档目录。不同账号不可混用。省略 `--remote-configs` 时完全离线；配置下载走 `wget -c`，失败非零退出并在 manifest 中保留错误。

- `packages/`：原始缓存包；`unpacked/<wxid>/`：解包的发布产物。
- `modules/`：按原路径拆开的桌面 `define` 模块；保留打包 wrapper，不是原始 TypeScript，也不自动还原 Cocos 工程。
- `resources/<host>/<path>`：按 `usr/gamecaches/cacheList.json` 将已访问资源映射回远端路径；只复制资源，不复制账号 storage 或 token。
- `manifest.json`：文件大小、SHA-256、模块与缓存数量、缺失资源及可选下载的 bundle 配置。`complete=true` 仅表示本次声明的缓存导出范围完整，不代表全游戏资源完整。

**桌面 wrapper 坑**：入口 `define("game.js", …)` 可能紧跟 loader 的 `};` 在同一行；只匹配行首会漏掉主包及分包入口。拆分后核对每个包的 wrapper 数量，并对所有模块跑 `node --check`。脚本的 `--selftest` 覆盖同行入口、路径穿越/软链逃逸、缓存缺失和 query URL 拒绝。

**范围**：远端配置只是索引，不等于全量纹理、音频、场景下载。先实际游玩所需场景，随后导出新快照；未访问的关卡明确列为未下载。仅处理无 query 的公开 HTTPS 资源，不保存带签名或认证参数的 URL。对外不分发解包产物。

**试玩记录**：依次观察首屏引导、核心经营循环、货币收支、升级/招聘、任务奖励、存档恢复；截图标出对应动作与结果。未解锁、付费、广告和长周期系统分开列为未验证，不拿代码中出现的类名当实际玩过。

## 解包产物怎么读

包解出来是**编译产物**，不是原始工程：

| 想要什么 | 去哪找 |
|---|---|
| 页面列表、tabBar、window 配置 | `app-config.json` |
| 样式 | 运行 `extract-wxss.mjs` 生成的 `.wxss`；原始数据是 `page-frame.html` 或 `pages/**/x.html` 里的 `setCssToHead([...])` |
| 页面逻辑、data、文案、事件 | `app-service.js` 里的 `define("pages/xxx/xxx.js", function(...){ ... })` |
| 结构（WXML） | `page-frame.html` 里的 `$gwx` 编译函数，不能直接读。先从 JS 的 data 和 WXSS 类名推结构，再对照截图 |
| 图片素材 | `assets/` 等原路径 |
| 分包 | 解到同一目录，路径带分包前缀 |

WXSS 编码规则：`[1]` 是组件作用域前缀，还原时删掉；`[0, N]` 表示 `N rpx`。很多项目直接写 `vw`，还原后保持原样。

## 复刻到 Taro 或 H5 的要点

- **先抄设计 token**。`app.wxss` 的 `body{--ink:...;--paper:...}` 就是整套配色，直接搬成 CSS 变量。
- **单位**：参考包用 `vw` 时可以原样照搬。用 `rpx` 时，按目标项目的 Taro 设计稿宽度换算。
- **`wx-view`、`wx-text`、`wx-button` 是标签选择器**，要改写成目标项目的 class 或元素选择器。
- **原包通常会重置 `wx-button::after{border:0}`**。Taro H5 的 `<button>` 默认带边框，复刻时要重置样式，或者改用 `view`。
- `@media (min-width:600px)` 是大屏兜底，一起抄。

## 换 UI 复刻的做法（2026-10-06 离职赔偿计算器实测）

1. 解包 → `extract-wxss.mjs` → `split-service.mjs`，读完 `_modules/pages/**` 的页面逻辑，列出功能清单（每个 bindXxx / 弹窗 / 跳转都算一项）。
2. 计算逻辑抽成不依赖框架的纯函数文件，写一份 `node --experimental-strip-types` 能跑的自测；原版的算法 bug（如法规口径错误）在这一步修，并在回复里说明改了什么。
3. 数据从 `_data/*.json` 生成，条目数与原版逐项对比。
4. 换 UI 时只保留功能，不保留原版的强制广告、公众号组件和对方的广告位 ID、AppID。
5. 用 miniprogram-automator 在模拟器里走一遍：输入、弹层、跳转、保存恢复，每步截图并核对金额（见 `miniprogram-devtools.md`）。NutUI `nut-popup` 的 `update:visible` 处理里只在值为 `false` 时关闭，否则弹层会一打开就关。

## 常见问题

| 现象 | 处理 |
|---|---|
| `scan` 列表里没有目标 | 在微信里重新打开小程序，然后运行 `$S paths` 查看探测到的缓存根目录。也可以用 `-root DIR` 手动指定 |
| `-grep` 搜不到 | 页面文案可能由接口下发，换一个写死在包里的文字搜索（标题、按钮、tab 名） |
| 解包报「加密文件」 | 传入的路径里缺少 wxid。加 `-wxid wx...` 显式指定 |
| 同一 wxid 下有多个版本目录 | CLI 自动取修改时间最新的目录。要指定版本，直接传版本目录路径 |
| `extract-wxss` 输出 `restored 0` | 旧版脚本只扫 `page-frame.html`；当前版本已同时扫 `pages/**/x.html`，确认用的是最新脚本 |
| 上游更新 | 运行 `$S --rebuild scan` 拉取上游并重新编译 |

## 小程序反编译（复刻参考）

要复刻别人的小程序样式或交互时，用 `scripts/wxapkg/wxapkg.sh` 扫本机微信缓存、按页面文字定位 wxid、解密解包，再用 `scripts/wxapkg/extract-wxss.mjs` 还原 WXSS、`scripts/wxapkg/split-service.mjs` 拆逻辑并导出数据。完整流程、换 UI 复刻的步骤、产物怎么读、复刻到 Taro 的要点见 `references/wxapkg-unpack.md`。只用于学习研究或复刻自己有权使用的设计，不分发解出的源码。
