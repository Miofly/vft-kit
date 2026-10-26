# TikTok Minis 前端抓取（学习研究用）

只用于学习研究，不分发解出的源码，不调用其后端接口做业务操作。

## 判断类型

`https://www.tiktok.com/minis/<token>` 网页只是扫码落地壳（TikTok 4D Auth 的 React 页），没有小程序代码。真正信息在 link 接口：

```
GET https://www.tiktok.com/tiktok/minis/link/<token>
```

- 要 TikTok 登录态，无 cookie 返回 `status_code=8, "Login expired"`；curl 直接打首页也会 302 到 `/login`。
- 用 ego-browser 已登录 profile：`await page.fetch(url)`，返回 `{ok,status,headers,body}`，`body` 是字符串，没有 `.text()`/`.json()`。
- 关键字段：
  - `minis_link_meta.minis_url`：H5 静态站点根，如 `https://minis-<client_key>-<id>.tiktokminis.us`，公开可取，无需登录。
  - `minis_link_meta.minis_schema`：`aweme://minis/<client_key>/prod/...#/pages/xxx`，可看出落地路由。
  - `minis_meta.config`（JSON 字符串）：`build.htmlEntry` 存在说明是 H5 型；`domain.allowList` 就是它的后端接口与埋点域名。
  - `minis_meta.asset_type=0` 对应 H5 型；原生/游戏型包不在 web 上，要从 App 侧抓。

## 抓取

```bash
export HTTPS_PROXY=http://127.0.0.1:7890   # 境外直连常超时
python3 scripts/tiktok-minis/fetch.py <minis_url | link 接口 JSON 文件> <输出目录> --pretty
```

脚本先取 htmlEntry，再用 BFS 扫 JS/CSS 里的 `/assets/`、`/static/` 引用并下载，同时存下外部 SDK（`connect.tiktok-minis.com/drama/sdk.js`），`--pretty` 用 prettier 格式化到 `pretty/`。正则会误中库里的字符串，比如 `mux.js`、`qq.svg`，这些 404 属正常；判断标准只看 `js/css_fail`。

## 读代码

- 常见是 uni-app（Vue3 + Vite）H5 构建：`<div id="app"><!--app-html--></div>` 加 `coverSupport` viewport 脚本就是标志。
- 没有 sourcemap。页面按 `assets/pages-<目录>-<页面>.<hash>.js` 分包，入口 `index-<hash>.js` 里有路由表、pinia、i18n。
- 宿主能力看 `TTMinis.*`（`init`、`pay`、`reportEvent`、`enableCapture`/`disableCapture` 防录屏、`getMenuButtonBoundingClientRect` 做自定义导航栏避让）。
- 先用 `grep -ohE` 统计关键词频次定位重点页，再读 pretty 后的对应文件。

## 照着复刻页面

- 源码只能说明机制（路由、swiper、预加载），不能代替看页面。复刻前先在设备里打开对方小程序，进到目标页再截图；首页不能当详情页或播放页用。开了 `disableCapture` 的页面用 adb 截图是整屏全黑，要在宿主机截模拟器窗口（macOS 用 `screencapture -l <窗口 id>`）。
- 截图文件名标明来源（`competitor-<页面>.png` 和 `ours-<页面>.png`）。用户贴的图先问清是哪一方的，再拿来对照。
- 改之前先列对照表：先看区域结构（上下分区，还是浮层叠在视频上），再逐个控件记位置、尺寸、文字和显隐规则。改完截自己的同一页，和对方的图并排逐项核对。

## 案例：VesperDrama（短剧，token mN6Hn1SDJkj）

uni-app H5，16 个页面：首页、剧集列表、播放、排行、搜索、收藏、记录、订单、个人中心、登录/注册、语言、设置、反馈、客服、政策。播放页主要靠 swiper 竖滑切集，用 m3u8 + mux.js 转封装，带 preload/autoplay；剧集解锁同时支持激励广告（rewarded）、金币和订阅（`/payment/create-subscription`、`/payment/tiktok/server-create-order`，走 `TTMinis.pay`），播放时开 `enableCapture` 防录屏。
