# 排障

## 连不上 / 命令不存在

`command -v ego-browser` 为空或 `import list` 失败：按 [install.md](install.md) 装 / 升级，重跑 `ego-browser skill`。

## 脚本输出拿不到

`ego-browser nodejs` 里 `console.log` / `console.error` 都走 **stderr**，`$(...)` 或管道拿到的是空。要给后续命令解析：脚本内 `fs.writeFile` 写临时文件，外层 `cat`（参考 `scripts/ego-bookmarks.sh`）。脚本也读不到 shell 的环境变量和 cwd，参数由外层拼进 heredoc（用 `json.dumps` 编码，防引号和 `$` 注入），路径写绝对路径。

## 页面动作超时、click 不生效

先重新拍快照或截图看真实状态，再决定下一步；不要拿旧的 `@N` 原样重试（页面变化后旧 ref 失效，raw CDP 之后也失效）。导航未提交时其他调用报 `EGO_PAGE_UNRESPONSIVE`，按报错提示处理；`goto` 超时就加大 `timeout`。

## 卡住 / blocked / 超时不要新开 space

在原 space 内恢复（Page label 持久）；确实续不下去就停、问用户。

## space 名被占用

`EGO_TASK_SPACE_NAME_IN_USE`：该名字属于用户的 space。问用户是否认领（`claimTaskSpace(id)`），或换名。

## 落到了错误的 profile

`taskSpace(name, { profileId })` 遇到同名已存在的 space 会续用它、忽略 `profileId`。space 名带上 profile id，或换新名。

## 变量不跨调用

每次 `ego-browser nodejs` 是新进程：每轮重新 `taskSpace(id)`、`task.page("p1")`。`task.page()` 不校验存在，用 `await task.pages()` 或上一轮打印的 label。

## 抓网络请求 / 埋点精确控制

Network 事件不会推给脚本：用 `page.cdp("Network.enable")` 后 `await page.events()` 取缓冲事件，或 `page.cdp("Page.addScriptToEvaluateOnNewDocument", { source })` 在页面主世界 hook `fetch`/`XMLHttpRequest`/`sendBeacon`。看页面 console 先 `page.cdp("egoAutomated.disable")` 再 `Runtime.enable`。`page.click()` 可能触发 `visibilitychange` 等副作用，测「切后台」类埋点要留意。

## 需要更新

输出出现 `[ego-browser:notice]`：先完成当前任务，告诉用户有更新，经同意后 `ego-browser upgrade`，再重跑 `ego-browser skill`。
