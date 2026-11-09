---
name: ego-browser-ops
description: ego-browser（ego-lite）全功能操作手册：探测安装升级、profile 列举与指定、task space 生命周期（新建/续用/认领/接管/交还/结束）、Page 全 API（快照选择器、点击填表、键鼠、截图、iframe、弹窗对话框、上传下载、page.fetch、evaluate、CDP）、从 Chrome 导入 profile、书签管理（列/搜/增/改/移/删/导出，脚本 ego-bookmarks.sh）、清理状态、排障。用户要用 ego 浏览器打开网页、操作页面、截图、复用已登录账号、切 profile、管理 ego 书签或问 ego 怎么用时使用。公共层，不含个人账号。
---

# ego-browser-ops

ego-browser（ego lite，Chromium 内核，Agent 与用户共用的浏览器）的公共操作手册。本文按 ego lite 0.6.2.7 / 官方指南 v2.2.0 整理；**官方指南是真值**：`ego-browser skill` 打印当前版本指南（末行 `[ego-browser:skill] end of guide`，缺则被截断，存文件分段读）；`help()` / `help("page.click")` 在脚本内打印签名和少见选项。个人 profile、已登录账号等私有约定不在本层（见 vft-ai `ego-browser-ops-private`）。

> **入口**：`command -v ego-browser`，有就按本手册；没有或按 [install](references/install.md) 排障后仍连不上，才回退 Playwright。用户点名 ego 时直接跑真实浏览器命令，失败再诊断安装。
> **浏览器/API 边界**：远端业务读写遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)：登录、验证码、2FA、纯视觉验收留在浏览器；认证后的业务读写找实际接口（`page.fetch` 复用登录态），写后独立回读。

## CLI

| 命令 | 作用 |
|---|---|
| `ego-browser nodejs <<'EOF' … EOF` / `nodejs -e '…'` | 在内嵌 Node（ESM）里跑浏览器脚本；沙箱拦 heredoc 才用 `-e`（外层单引号、JS 内用双引号） |
| `ego-browser skill` | 打印当前版本官方指南；`upgrade` 后、或输出提示时重跑 |
| `ego-browser import list` / `import --browser chrome\|edge\|brave [--profile <目录名>]` | 列出 / 从本机其他浏览器导入 profile 数据（含书签、登录态） |
| `ego-browser upgrade` | 升级；输出出现 `[ego-browser:notice]` 时先完成任务，征得用户同意再升级 |
| `--ego-server-name=<name>` | 连指定名字的浏览器服务（多实例） |

脚本运行环境的硬约束：
- 跑在 Node 里，不是页面里：`window`/`document` 只能写在 `page.evaluate()` 回调内；回调读不到外层变量，只能传一个可 JSON 序列化的参数。
- 不继承 shell 的 cwd 和环境变量：读写文件一律绝对路径，参数直接写进脚本（脚本化时由外层 shell 拼进 heredoc，见 `scripts/ego-bookmarks.sh`）。内置模块用 `await import("node:fs/promises")`。
- `console.log` 输出走 **stderr**：要给管道解析的结果，写临时文件再 `cat`。
- 只用本文列出的 API，**不是 Playwright**：没有 `locator()`/`getByRole()`/`context()`/`expect()`/`route()`，不 import Playwright、不另起浏览器；不够用走 `evaluate()` / `cdp()`。
- `page.waitForFunction(fn, arg, opts)` 的 **arg 位置不能省**：写成 `waitForFunction(fn, { timeout })` 会报 `options are the third argument; pass undefined when omitting the callback argument`，必须 `waitForFunction(fn, undefined, { timeout })`（2026-11-08 实测，白跑一轮）。
- 时间单位一律毫秒。

## Task space

一个用户目标 = 一个 task space，建一次、打印 `spaceId`，后续轮次续用。每轮是新 Node 进程：space、tab、Page label 持久，JS 变量不持久，每轮重新 `taskSpace(id)` / `task.page("p1")`。

| API | 说明 |
|---|---|
| `await profiles()` | 列 profile：`{id, name, isDefault}`（`id` 如 `Default`/`Profile 3`，`name` 是菜单里显示的名字） |
| `await taskSpace(nameOrId, { profileId? })` | 同名则续用自己的 space；`profileId` **只在新建时生效**。名字被用户 space 占用报 `EGO_TASK_SPACE_NAME_IN_USE`：问用户是否 `claimTaskSpace`，或换名 |
| `await listTaskSpaces()` | 列所有 space：`{id, name, ownership, createdBy, profileId, profileName, recentTabTitles}`（注意是 `id`，不是 `spaceId`） |
| `await claimTaskSpace(id)` | 认领用户的 / 不活跃的 / 已 finish 但 keep 了页面的 space，**仅用户明确要求时** |
| `await takeOverTaskSpace(id)` | 用户处理完（handOff 后）接回自己的 space；`task.userPage()` 拿交接时用户的活动 tab |
| `task.spaceId` `name` `ownership` | 状态 |
| `task.page(label)` | 取已存在的 Page 句柄，**不创建、不校验存在**（句柄永远 truthy）；新 space 自带 `p1` |
| `await task.newPage()` / `pages()` / `tabs()` | 新开空白 Page / 列托管 Page / 列全部 tab `{label?, page, targetId, title, url, active, openedBy}` |
| `await task.adopt(page, { as? })` / `release(label)` | 接管无 label 的 tab / 把来源未知的 Page 还给用户（不关） |
| `await task.waitForControl({ interval?, timeout? })` | 原地等控制权（少用） |
| `await task.handOff()` | 把控制权交给用户（验证码、2FA、扫码、权限弹窗、设备选择），本轮结束并告诉用户做什么 |
| `await task.finish({ keep })` | 结束：默认 `keep: []`；结果要留给用户看才 `keep: ["p2"]` 或 `"all"`。只调一次、放最后一轮最后一句，之后不再碰任何 Page；因用户接管或报错停下时不调 |
| `await task.cdp(method, params?, { timeout? })` | Target / Browser 域 CDP |

规则：卡住、超时、页面异常都在**原 space** 内恢复，不新开 space；续不下去就停下问用户。用户接管或 space 失活就停，不绕路。`openedBy: "unknown"` 的 tab 视为用户的，不关。用户建的 / 来源未知的 tab 在时 `keep: []` 不会关掉整个 space。结束时列要保留的页面，不逐个 close。

## Page API

| 类别 | API |
|---|---|
| 状态 | `label` `spaceId` `openedBy` `targetId`（不跨轮保存） `url()` `title()` `info()` |
| 观察 | `snapshot()` / `snapshot({ scope: "full_page" })` / `snapshot({ scope: "subtree", root: "@12" })`（iframe）`screenshot({ path? })` |
| 导航 | `goto(url, { referer?, timeout?, waitUntil? })`（`commit`/`domcontentloaded`/`load`/`networkidle`）`reload()` |
| 等待 | `waitForURL()` `waitForSelector(sel, { state })` `waitForLoadState()` `waitForFunction(fn, arg, opts)` `waitForEvent("popup"\|"download")` `waitForTimeout()` |
| 元素 | `click()` `dblclick()` `hover()` `dragAndDrop()` `fill()` `selectOption()` `focus()` `press()` `setInputFiles()` `waitForFileChooser()` `close()` |
| 对话框 | `acceptDialog(promptText?)` `dismissDialog()` |
| 鼠标 | `mouse.click()` `move()` `down()` `up()` `wheel()` |
| 键盘 | `keyboard.down()` `up()` `press()` `type()` `insertText()` `paste(text \| { text, html })` |
| 代码/协议 | `evaluate(fn, arg)` `fetch(url, options)` `cdp(method, params, options)` `events()` |

### 观察与定位

- 每次只取够下一步决策的最便宜状态：DOM 页用 `snapshot()`（语义/定位真值），canvas、富文本、表格、地图用 `screenshot()` + 坐标；默认不两个都取。
- 选择器：快照 ref `@21` / `ref=21`、`text=...`（不加引号=忽略大小写子串，加引号=精确）、`loc=css:` / `loc=role:button[name='Sign in']` / `loc=role:...[name*="..."]` / `loc=href:`、`xpath=...`、裸 CSS；另支持 `css=`、结尾 `:has-text()` / `:text-is()`、`>> nth=N`。选择器必须**恰好匹配一个**可操作元素。CSS 穿透开放 shadow root；动作先找顶层文档再找 iframe。
- 一轮内能规划好的多个动作放同一次调用，末尾等最终状态并**最后打印新快照**，下一轮直接用；页面变了就重拍快照，旧 `@N` 失效。
- `snapshot()` 只截视口，末尾出现 `[more content below the viewport: ...]` 表示下方被省略，不是不存在；用 `full_page` 或滚动再下结论。
- 动作不达预期先看当前页真实状态，不盲目重试、不急着降级到坐标或 CDP。结果已明确就停，不多处重复确认。

### 动作细节

- `click`/`fill`/`hover`/`dragAndDrop` 自动滚到可见，不用预先滚动。目标晚出现先 `waitForSelector`；有可观察条件就不用固定延时。
- 只有 `click`/`dblclick`/`hover`/`dragAndDrop`/`mouse.click`/`mouse.move`/`mouse.wheel` 接受 `{ label: "3-6 词描述" }`（显示在 agent 光标旁）；其他方法传 `label` 会报错。`selectOption(sel, { label: "October" })` 的 label 是选项文字，另一回事；传 `null`/`[]` 清空。
- 鼠标坐标为 CSS 像素；`mouse.wheel` 前先在目标区域 move/click。快捷键用 Playwright 写法，跨平台用 `ControlOrMeta`。`keyboard.paste` 在 macOS/Windows 用系统粘贴并恢复剪贴板。
- 截图 `path` 必须绝对路径；省略则写系统临时目录并返回路径。
- 链接点击后导航未提交时，其他调用等一个有限周期后报 `EGO_PAGE_UNRESPONSIVE`；`goto`/`reload` 超时会停掉未提交的导航，页面保持在旧文档，加大 `timeout` 重试。

### 弹窗、对话框、上传、下载

```js
const popupP = page.waitForEvent("popup");          // 先布置等待再触发
await page.click('a[target="_blank"]');
const popup = await popupP; await popup.waitForLoadState();
// 或：receipt = await page.click(...); task.page(receipt.popups[0].label)

await page.acceptDialog("prompt 内容");              // receipt.dialog / page.info() 里出现同步对话框时先处理

await page.setInputFiles("input[type=file]", ["/abs/a.pdf"]);
const chooserP = page.waitForFileChooser({ timeout: 10_000 });
await page.click("button.upload");
await (await chooserP).setFiles("/abs/a.pdf");

const dlP = page.waitForEvent("download", { timeout: 30_000 });
await page.click("button.download");
await (await dlP).saveAs("/abs/out/report.pdf");      // 同一脚本内 saveAs，轮次结束临时文件即删；不要用 CDP 改下载目录
```

### 页内代码、请求、CDP

- `page.evaluate(fn, arg)`：批量提取、复杂页内逻辑；无 timeout 选项，安全超时后看 `executionStopped` / `mayHaveLateEffects` 决定是否先 reload。
- `page.fetch(url, { method, headers, body, timeout, saveAs? })`：在页面里跑 `window.fetch`，带该页 cookie、受 CORS 约束，返回 `{ok, status, statusText, url, headers, body}`；二进制用 `saveAs` 落盘。不需要登录态的后台请求用 Node 自带 `fetch()`。
- `page.cdp()`：Page/Runtime/DOM/Network/Input 等域，用于包装 API 不够时；用后旧 ref 失效。`await page.events()` 取并清空缓冲的协议事件（不是 EventEmitter）。
- 默认隐藏页面 console 防检测；调试要看 `Runtime.consoleAPICalled`：先 `page.cdp("egoAutomated.disable")` 再 `Runtime.enable`（此时站点可再次检测到 CDP）。

## Profile

- 默认不选 profile（新 space 落在默认 profile）。用户点名某个 profile、或任务要另一套登录态/干净环境时：`profiles()` 按 `name` 找 `id`，用**新的 space 名**建 space：`taskSpace("<任务> <profileId>", { profileId })`。同名 space 已存在时 `profileId` 被忽略，会落在旧 space 的 profile 上。
- 数据目录（macOS）：`~/Library/Application Support/Citro Labs/ego lite/<profileId>/`（`Bookmarks`、`Cookies` 等都在此）。
- 细节见 [references/profiles.md](references/profiles.md)。

## 书签管理

用 `scripts/ego-bookmarks.sh`：在目标 profile 开临时 space，打开 `chrome://bookmarks`，调页内 `chrome.bookmarks` API（与书签管理器同一通道），跑完自动 `finish`。浏览器运行中也安全；**不要直接改 `Bookmarks` 文件**，运行中的浏览器会覆盖它。

```bash
B=${VFT_KIT_DIR}/skills/web-automation/ego-browser-ops/scripts/ego-bookmarks.sh
$B <profile名或id> tree [文件夹]            # 全部书签 id/path/url（JSON 到 stdout）
$B <profile> ls [文件夹]                     # 一层子项
$B <profile> search <关键词>
$B <profile> add <文件夹> <标题> <url>       # 文件夹不存在逐级创建
$B <profile> mkdir <文件夹>
$B <profile> mv <id> <目标文件夹> [index]
$B <profile> rename <id> <新标题> [新url]
$B <profile> rm <id>...                      # 文件夹连子项删，输出被删内容
$B <profile> export <绝对路径.json>          # 整棵树备份
```

- 文件夹写数字 id 或标题路径 `书签栏/AI/tools`；根别名 `bar`=书签栏、`other`=其他书签。
- 批量删改前先 `export` 备份；删除前用 `search`/`ls` 确认 id。整批从 Chrome 搬书签用 `ego-browser import --browser chrome --profile <目录>`。
- 跨 profile 复制：源 `tree` 拿 JSON，逐条对目标 `add`。

## 参考

| 主题 | 文件 |
|---|---|
| 安装 / 升级 / 连通验证 | [references/install.md](references/install.md) |
| profile 列举、指定、导入、数据目录 | [references/profiles.md](references/profiles.md) |
| 清 cookie / 缓存 / 存储（可能影响整个 profile） | [references/clearing-state.md](references/clearing-state.md) |
| 排障（连不上、超时、旧 ref、stderr 输出、埋点抓包） | [references/troubleshooting.md](references/troubleshooting.md) |
