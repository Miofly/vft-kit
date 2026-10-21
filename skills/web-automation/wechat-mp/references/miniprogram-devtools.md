# 小程序开发与自测（微信开发者工具 CLI + miniprogram-automator）

本文件记录开发阶段的通用操作：用命令行驱动开发者工具，在模拟器里自动化测试，以及广告组件的规则。上传、提审和发布见 `miniprogram-release.md`。

## 开发者工具 CLI

CLI 路径：`/Applications/wechatwebdevtools.app/Contents/MacOS/cli`。前提是开发者工具的「设置 → 安全设置 → 服务端口」已开启。

| 动作 | 命令 |
|---|---|
| 是否已登录 | `cli islogin` |
| 打开项目并开放自动化端口 | `cli auto --project <dir> --auto-port 9420`（命令返回后端口持续可用） |
| 上传开发版 | `cli upload --project <dir> -v <版本号> -d "<描述>"` |
| 预览二维码 | `cli preview --project <dir> --qr-format image --qr-output <png>` |

- `<dir>` 是 `project.config.json` 所在目录。Taro 项目的 `miniprogramRoot` 指向 `dist/weapp`，所以要先构建。
- **开发者工具升级后，服务端口会被重置为关闭**：数据目录换成新的 hash（CLI 报 `initialize error: ENOENT … <hash>/Default/.cli` 或 `IDE service port disabled`，`echo y |` 也开不了）。不用点界面，按下面做，全程不抢用户的鼠标和焦点：
  1. 结束开发者工具主进程：`pkill -f "/Applications/wechatwebdevtools.app/Contents/MacOS/"`。
  2. 在报错里那个 hash 目录下，改 `WeappLocalData/localstorage_*.json` 里的 `security.enableServicePort` 为 `true`（先备份；有好几个 localstorage 文件时，改带 `security` 键的那个）。
  3. 后台隐藏启动：`open -g -j -a /Applications/wechatwebdevtools.app`，再用 `cli islogin` 验证。
- **登录不点界面**：`cli login --qr-format image --qr-output <png>`（后台运行，等用户手机扫码），扫完 `cli islogin` 回读 `{"login":true}`。登录窗口里的「微信快捷登录」要真实点击，会抢用户的鼠标，不用它。
- **桌面应用的通用原则**：能改配置、走 CLI 或接口的，就不点界面。确实要点时，用 AppleScript 的 `click menu item` 操作原生菜单，它不移动鼠标；不要用 cliclick 或坐标点击，那会抢走用户正在用的鼠标和焦点。
- 不要在 `dist` 目录或项目目录里执行 `cli upload`，在 `/tmp` 下执行可以避开 CLI 偶发读取 cwd 配置的问题。

## 模拟器自动化（miniprogram-automator）

**不要用模拟鼠标或 cliclick 点模拟器**：点击不生效，还会误点到其他窗口。统一用 automator 连接 `cli auto` 开出的端口。

依赖：在临时目录 `npm i miniprogram-automator`。`scripts/miniprogram-automator-helpers.cjs` 封装了下面这些常用动作，测试脚本可以 `require` 它。

```js
const automator = require('miniprogram-automator');
const mp = await automator.connect({ wsEndpoint: 'ws://localhost:9420' });
const page = await mp.reLaunch('/pages/xxx/index');   // 重新进入页面
const items = await page.$$('.tab-item');              // 只认 class 选择器
await items[2].tap();
await mp.pageScrollTo(2000);
await mp.screenshot({ path: '/abs/path.png' });
mp.disconnect();
```

常用技巧：

- **桩掉弹窗**：`mp.mockWxMethod('showModal', { confirm: true, cancel: false, errMsg: 'showModal:ok' })`，用完 `restoreWxMethod`。
- **改写网络请求**：在 `mp.evaluate` 里保存 `wx.__origRequest = wx.request`，再按 URL 返回假数据或故意失败，测试结束后恢复。用它测加载中状态、接口失败兜底、长列表和边界数据，不依赖后端真有这些数据。
- **广告不可测时打桩**：`wx.createInterstitialAd = () => ({ onLoad(){}, onError(){}, onClose(){}, destroy(){}, show(){ wx.__adShows++; return Promise.resolve(); } })`，再读计数，确认触发时机和限频逻辑。必须在 `reLaunch` 之前打桩，页面会缓存广告实例。
- **读写 storage**：`mp.callWxMethod('getStorageSync', key)`、`setStorageSync`、`removeStorageSync`。
- **模拟选头像**：对 `<button open-type="chooseAvatar">` 调用 `element.trigger('chooseavatar', { avatarUrl })`。
- **元素文本**：`await el.text()`；读输入框的值用 `await el.property('value')`。
- **断言要宽一点**：`[class*=xxx]` 这种模糊选择器容易匹配到无关节点，测试时尽量用组件自己的 BEM class。

## 连本地后端测试

- 构建时用环境变量把接口地址换成本机，例如 Taro：`VITE_GLOB_API=http://localhost:<port>/<prefix> NODE_ENV=production npx taro build --type weapp --env-prefix VITE_`。
- 本机 `http://localhost` 不在合法域名里，要在 `project.private.config.json` 里临时设置 `"urlCheck": false`。**测完改回 `true`**，再做一次不带覆盖的生产构建，避免把 localhost 产物上传。
- `wx.login` 拿到的 code 在本地后端也能换 openid，前提是本地后端配了同一个 AppID 和 AppSecret。

## 广告组件规则

| 类型 | 用法 | 要点 |
|---|---|---|
| 原生模板 `<ad-custom unit-id>` | 声明式，放在页面底部 | 只在 weapp 渲染；没填充时不占位 |
| Banner `<ad unit-id>` | 声明式 | 宽度跟随容器 |
| 插屏 `wx.createInterstitialAd` | 命令式，`show()` 返回 Promise | 小程序启动后短时间内、距上次插屏间隔不足时，`show()` 会 reject，必须 `catch`，不能影响主流程；页面卸载时 `destroy()` |
| 激励视频 `wx.createRewardedVideoAd` | 命令式 | 看 `onClose(res)` 的 `res.isEnded` 判断是否看完 |

- 插屏在业务动作（比如保存、打卡）之后弹出时，要等成功提示结束再 `show()`，约 1.2～1.5 秒。业务侧自己再加限频（比如几分钟一次），避免连续操作时每一步都弹。
- 广告位 ID 在小程序后台「流量主 → 广告管理」里新建。多个页面共用一个广告位也能展示，但收益统计会混在一起。

## 分享

- `onShareAppMessage` 的 `imageUrl` 必须是包内文件或临时文件路径，不接受 base64。Taro 用 `import` 引入图片会被内联成 base64，需要把图片原样拷贝进产物再用绝对路径引用。
- 要动态生成分享图，用 `<canvas type="2d">` 离屏绘制，再 `canvasToTempFilePath`。画布不能 `display:none`，要移出可视区。
- `useShareAppMessage` 可以返回 `promise`，微信最多等 3 秒，超时用同一对象里的 `imageUrl` 兜底。
- 分享标题建议带上产品名，在群聊里一眼能认出是什么。
- **分享成功没有回调**：微信不告诉页面用户是否真的转发了。需要“分享后”做事（比如弹插屏），就在 `onShareAppMessage` 里记一个标记，等关闭转发面板回到页面触发 `onShow` 时再处理。测试时在 `mp.evaluate` 里取 `getCurrentPages()` 的最后一页，依次调 `onShareAppMessage()` 和 `onShow()`。automator 的 `page.callMethod('onShareAppMessage')` 不一定走到页面自己的实现。
- **Taro（vite）监听构建会丢分享开关**：`taro build --watch` 增量重编页面时，产物里会丢掉 `component.enableShareAppMessage = true`，页面分享退回全局默认（如果有全局 Page 补丁）或不能转发。根因是 `@tarojs/vite-runner` 输出页面 JSON 时直接 `delete` 了缓存配置里的这个字段。根治办法是在页面组件上也声明：`defineOptions({ enableShareAppMessage: true })`，Taro 运行时会读组件上的这个标记，不受构建缓存影响。
