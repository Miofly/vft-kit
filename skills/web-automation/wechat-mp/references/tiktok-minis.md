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

## 竞品源码调研（代码优先）

研究登录、游客、广告、支付、预加载这类机制时，先抓 H5 源码读代码；模拟器只在两种情况用：复刻视觉布局，或代码看不出运行时行为（宿主弹窗、真实时序、广告填充）。

### 找链接

1. 搜索引擎：`"tiktok.com/minis" <品牌>`、`tiktokminis.us <品牌>` 等多换几种说法批量搜，把结果里的 `tiktok.com/minis/<token>` 和 `minis-<client_key>-<id>-3.tiktokminis.us` 全部收集起来。站点体检类网站（如 scamadviser）会收录 `*.tiktokminis.us` 主机名，`curl -s https://<host>/ | grep -o '<title>[^<]*'` 就能认出品牌。
2. 用 link 接口批量解析，按 `minis_meta.name` 认品牌（ego-browser 已登录 TikTok 的 profile）：

```js
const page = (await taskSpace("minis-links")).page("p1");
await page.goto("https://www.tiktok.com/explore");
for (const t of ["<token1>", "<token2>"]) {
  const r = await page.fetch("https://www.tiktok.com/tiktok/minis/link/" + t);
  const j = JSON.parse(r.body), m = j.minis_meta || {};
  // 存 r.body 到 <输出目录>/_links/<token>.json，给 fetch.py 用
  console.log(t, j.status_code, m.name, m.asset_type, j.minis_link_meta?.minis_url);
}
```

3. 判读：`status_code=8` 是未登录；`200002 "The corresponding minis link does not exist"` 表示链接不存在；`status_code=0` 但 body 约 218B、`minis_meta` 只有 `{"minis_status":4}` 表示链接还在、小程序不可用（推测已下架）；`asset_type=1` 加 `*-minigame.tiktokminis.us/vpkg/` 是游戏型包，web 上抓不到。
4. 网页端找不到入口：TikTok web 的搜索接口（`/api/search/general/full/`）、作品详情、主页简介都不返回 Minis 卡片或锚点，品牌主页的 bio 链接一般跳原生 App 的 onelink。这种情况只能在 App 里搜品牌名，到「综合」页的 TikTok Minis 卡片点「打开」，再用右上角 More → Copy link 拿 token。

### 批量抓取

```bash
export HTTPS_PROXY=http://127.0.0.1:7890
for t in <token1> <token2>; do
  python3 scripts/tiktok-minis/fetch.py <输出目录>/_links/$t.json <输出目录>/<竞品名> --pretty 2>&1 | tail -3
done
```

`js/css_fail` 不为 0 时，逐条用 `grep -rn <文件名>` 查引用出处：出现在注释里，或者是打包进 bundle 的 `node_modules/...` 路径字符串，就是误报；只有 html 或 JS 真实加载的路径 404 才算没抓全。

### 分析清单

先统计宿主能力：`grep -rohE "TTMinis\.[a-zA-Z]+" pretty *.html | sort | uniq -c | sort -rn`。

| 维度 | grep 关键词 | 看什么 |
|---|---|---|
| 登录与鉴权 | `TTMinis\.(login\|authorize)`、`LoginBy\|tiktok-login\|/auth/`、`guest\|visitor\|anonym\|deviceId` | 调用点在启动 boot 里还是按钮点击里；首屏数据请求是不是 `await` 在登录后面；有没有超时（`Promise.race`、`setTimeout`）和冷却 |
| 会话存储 | `localStorage\.(get\|set)Item\|sessionStorage\|setStorageSync`、`token` | token 和用户信息存在哪些键；「本会话已尝试静默登录」这类标记；401 或业务码过期时是重试、清 token 还是跳登录页 |
| 强制登录 | `isLoggedIn\|login\.html\|navigateTo.*login`、`LOGIN_REQUIRED` | 哪些页面或操作必须登录（收藏、评论、下单），公共浏览页遇到 401 是否跳转 |
| 付费墙/支付 | `TTMinis\.pay\|requestPayment\|createSubscription`、`CreateOrder\|create-order\|order`、`needsReauth` | 下单接口 → `pay` → 回查（轮询次数和间隔），取消和超时分支，启动时是否补单 |
| 激励广告 | `createRewardedVideoAd`、`onClose\|offClose\|onError\|onLoad\|isEnded`、`setTimeout` | 实例是预建复用还是每次新建，`load()` 的时机，单飞锁，`isEnded` 判定，超时兜底，关闭后何时预加载 |
| 播放预加载 | `m3u8\|mux\|hls\|xgplayer\|preload\|autoplay`、`swiper` | 首帧来源，播放器是否复用，下一集何时预加载，切集方式 |

非 Vite 的多页站（每页一个 `*.html` 加 `js/*.js`）把页面逻辑写在 html 内联脚本里，grep 要连 `*.html` 一起搜。

### 本次踩坑

- `config.build.htmlEntry` 写的可能是源码路径（`public/index.html`，配 `outputDir: dist`），线上真实入口在站点根目录的 `index.html`，按 htmlEntry 拼 URL 会 404。fetch.py 现在会依次回退到 basename 和 `index.html`。
- 多页原生 JS 站的引用写成 `js/api.js`，页面跳转写在 JS 里（`location.href = 'play.html?...'`），只扫 `/assets/` 会漏掉大部分页面。fetch.py 现在会收 html 里的全部本站引用，并解析 JS 里出现的 `*.html`；这些 html 按文档根解析，不按 JS 文件所在目录。
- 逐个文件调 `npx prettier` 在代理环境下每次都去查 registry，几十个文件要卡十几分钟。fetch.py 改成只调一次 `npx`，并且调用时不带代理变量。

## 案例：VesperDrama（短剧，token mN6Hn1SDJkj）

uni-app H5，16 个页面：首页、剧集列表、播放、排行、搜索、收藏、记录、订单、个人中心、登录/注册、语言、设置、反馈、客服、政策。播放页主要靠 swiper 竖滑切集，用 m3u8 + mux.js 转封装，带 preload/autoplay；剧集解锁同时支持激励广告（rewarded）、金币和订阅（`/payment/create-subscription`、`/payment/tiktok/server-create-order`，走 `TTMinis.pay`），播放时开 `enableCapture` 防录屏。
