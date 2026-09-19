---
name: wxapkg-unpack
description: "反编译微信小程序：扫描本机微信缓存的 .wxapkg，按页面文字定位 wxid，解密解包并还原 WXSS 与页面 JS，用于样式复刻、交互参考或排查。触发词：小程序反编译、解包 wxapkg、小程序源码、抄小程序样式、1:1 复刻小程序、wux1an/wxapkg。"
---

# wxapkg-unpack：小程序反编译

基于 [wux1an/wxapkg](https://github.com/wux1an/wxapkg)。上游 v2 只提供 GUI，本 skill 复用它的 `wechat` Go 包，包装成 CLI `scripts/wxapkg.sh`，并补了按文字定位和 WXSS 还原。

> 只用于学习研究或复刻自己有权使用的设计。不要分发解出的源码，也不要用于绕过授权。

## 前置

- 需要 `git`、`go`（>= 1.25）和 `node`。首次运行时自动 clone 上游并编译到 `~/.cache/vft-kit/wxapkg/bin/wxapkg-cli`。
- clone 或 `go build` 超时时，先设代理再重试：`export https_proxy=http://127.0.0.1:7890 GOPROXY=https://goproxy.cn,direct`。
- 自检：`scripts/wxapkg.sh selftest`。这条命令会造一个最小 wxapkg，然后解包验证，输出 `selftest ok` 即可用。

## 流程

`S` 为本 skill 目录下的 `scripts/wxapkg.sh`，`OUT` 为临时产物目录（不要放进项目源码目录）。

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
   node <skill>/scripts/extract-wxss.mjs "$OUT/<wxid>"
   ```
   脚本会生成 `app.wxss`、`pages/**/x.wxss` 和 `components/**/index.wxss`。

## 解包产物怎么读

包解出来是**编译产物**，不是原始工程：

| 想要什么 | 去哪找 |
|---|---|
| 页面列表、tabBar、window 配置 | `app-config.json` |
| 样式 | 运行 `extract-wxss.mjs` 生成的 `.wxss`；原始数据是 `page-frame.html` 里的 `setCssToHead([...])` |
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

## 常见问题

| 现象 | 处理 |
|---|---|
| `scan` 列表里没有目标 | 在微信里重新打开小程序，然后运行 `$S paths` 查看探测到的缓存根目录。也可以用 `-root DIR` 手动指定 |
| `-grep` 搜不到 | 页面文案可能由接口下发，换一个写死在包里的文字搜索（标题、按钮、tab 名） |
| 解包报「加密文件」 | 传入的路径里缺少 wxid。加 `-wxid wx...` 显式指定 |
| 同一 wxid 下有多个版本目录 | CLI 自动取修改时间最新的目录。要指定版本，直接传版本目录路径 |
| 上游更新 | 运行 `$S --rebuild scan` 拉取上游并重新编译 |
