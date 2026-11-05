# 后台 GUI 操作

目标：AI 操作桌面软件时不抢用户的鼠标、键盘和焦点。按隔离程度从强到弱选择，能用 API/CLI 就不碰界面。

| 路线 | 隔离 | 适用 | 代价 |
|---|---|---|---|
| macOS 虚拟机（cua `lume`、cirruslabs `tart`） | 整机隔离 | 任意软件、要求零干扰 | 十几 GB 镜像、8GB+ 内存、虚拟机内重新登录 |
| Electron 独立实例 + `--inspect` | 进程与 profile 隔离、窗口隐藏 | `--inspect` fuse 未关的 Electron 应用 | 只对 Electron；DOM 选择器随改版失效 |
| `cua-driver` MCP | 同一桌面，后台投递 | 任意原生应用、需操作用户正在用的窗口 | 需授予辅助功能和屏幕录制；用户能看到窗口变化 |

## Electron 独立实例

1. 读 fuse：在 `Electron Framework` 二进制里找哨兵 `dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX`，其后 1 字节版本、1 字节长度、再是每个 fuse 一字节（`0x31` 开、`0x30` 关）。顺序：RunAsNode、EnableCookieEncryption、EnableNodeOptionsEnvironmentVariable、EnableNodeCliInspectArguments、EnableEmbeddedAsarIntegrityValidation、OnlyLoadAppFromAsar、LoadBrowserProcessSpecificV8Snapshot、GrantFileProtocolExtraPrivileges。
2. 生产包常在主进程删掉 `--remote-debugging-port`，看启动日志确认，不要只看端口不通就放弃。第 4 个 fuse（inspect）开着时 `--inspect=<port>` 仍可用。
3. 启动第二实例：`<App>.app/Contents/MacOS/<App> --inspect=<port> --user-data-dir=<独立目录>`。不同 user-data-dir 不抢单例锁。
4. 复用登录：正常退出无关，直接 `rsync` 用户的 userData 目录到独立目录，排除 `*Cache`、`Singleton*`、日志和大运行时目录。登录态是快照，用户重新登录后需重拷。
5. 控制：用 [`scripts/electron-inspect/insp.mjs`](../scripts/electron-inspect/insp.mjs)（`ELECTRON_INSPECT_PORT` 指端口，有 HTTP 代理时加 `NO_PROXY='*'`）。`node insp.mjs '<主进程表达式>'`，`node insp.mjs -r '<渲染进程表达式>'`；每次调用自动注入 `main-setup.js` 与 `helpers.js`，提供 `W`、`run()`、`stealth()`、`tap(文本)`、`tapSel(选择器)`、`type()`、`key()`、`NET`。窗口未创建时报 `no BrowserWindow yet`，等几秒重试。
6. 必须全程不上前台。只在启动后调 `stealth()` 不够：窗口创建到调用之间（约 10 秒）会正常弹出并抢焦点，用户可见（2026-11-05 用户纠正）。已验证无效：`NODE_OPTIONS="--require <预加载>"`，打包应用报 `Most NODE_OPTIONs are not supported in packaged apps` 并忽略。**尚无已验证的无闪现启动方法**；候选（未验证）：`--inspect-brk=<port>` 让主进程停在第一行，连上后先 `app.setActivationPolicy('accessory')` 并改写 `BrowserWindow.prototype.show/focus` 与 `app.focus`，再 `Debugger.resume`。在验证前，启动隔离实例会闪现：先告诉用户并取得同意，启动前后各读一次前台应用（`osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'`），变了就 `osascript -e 'tell application "<原前台应用>" to activate'` 还给用户。
   `stealth()`：透明、鼠标穿透、不可聚焦、`showInactive`，并关后台节流。不要用 `hide()`：隐藏窗口不出帧，CSS 退出动画的 `animationend` 不触发，Radix 等组件的弹窗关不掉、旧浮层一直留在 DOM。已卡住时 `W.webContents.reload()` 清状态。
7. 点击输入：`tap`/`tapSel` 走 CDP `Input.dispatchMouseEvent`，是可信事件，只进渲染进程，不动系统光标；`type` 走 `Input.insertText`，React 受控输入能收到。脚本里 `el.click()` 或合成 `MouseEvent` 打不开 Radix 下拉。
8. 下拉/菜单：`main-setup.js` 已开 `Emulation.setFocusEmulationEnabled`，否则不可聚焦窗口里的菜单刚开就因失焦关闭。仍打不开时先查 `disabled`、`elementFromPoint` 命中，再用 `focus()` + `key(' ')` 打开（实测比鼠标稳）；子菜单项点 `role=menuitem` 本身。
9. 网络：`NET` 只看得到渲染进程请求（只记 method、path、query/body 字段名、status）。主进程 `fetch` 不在其中；业务接口和触发条件直接读源码：`npx -y @electron/asar extract <App>.app/Contents/Resources/app.asar <目录>`，搜 `ipcMain.handle`、`/api/` 和界面文案。页面上 `window.electronAPI.*`（preload 暴露的 IPC）常可直接读状态做独立回读。
10. 同一 user-data-dir 同时只能有一个进程：两个进程抢同一目录会让 IndexedDB/LevelDB 加锁失败（日志 `Failed to open LevelDB database`），应用显示「本地数据或登录状态未能及时恢复」，该目录的数据即视为损坏。启动前 `ps -axo pid,command | grep -F -- "--user-data-dir=<目录>"` 确认无占用；应用退出后先查原因，不要立刻重启。
   从 Dock 或菜单栏退出会关掉同一 bundle 的所有实例（含隔离实例）；隔离实例「自己退出」时先怀疑这个，回报用户，不要重启。
11. 副作用：应用的「分享/复制链接」会写系统剪贴板；定时任务类功能可能写 `~/Library/LaunchAgents/*.plist`。做完核实并撤销不需要的注册（停用任务、`launchctl list` 回读）。
12. 风险：同账号双开时定时任务可能重复执行、额度共用；应用若有固定工作目录（如 `~/Documents/<App> Workspace`）会被两实例共享。隔离实例里建的本地数据（技能、人设、任务）只在该 profile，用户实例看不到。结束用主进程 `app.quit()` 正常退出，核实无残留进程。

## 双开（给用户用的第二个实例）

- 判断：`<App>.app/Contents/Frameworks/` 下有 `Electron Framework.framework` 即 Electron，基本都认 `--user-data-dir`（Chrome/Edge、VS Code/Cursor 同样认）。原生应用（如微信、QQ Mac 版）没有这个参数，复制 `.app` 改 Bundle ID 重签的做法易出问题，不作为默认方案。部分 Electron 应用自己写死单实例或数据目录，逐个实测。
- 启动：`open -n -a /Applications/<App>.app --args --user-data-dir="$HOME/Library/Application Support/<app>-2"`。`-n` 强制新进程；`open -a` 不带 `-n` 会切到已开的实例。数据目录放 `~/Library/Application Support/` 下长期保留，不放会被清理的临时目录。
- 空目录 = 全新未登录实例，可登录另一个账号；要复用当前账号就按上节第 4 步复制 userData。给用户双开不加 `--inspect`（本机任意进程都能连该端口执行代码），只在 AI 后台操作时加。
- 常用的写成 shell alias；回读：`pgrep -fl "user-data-dir=<目录>"` 有主进程，原实例 PID 仍在。
- 平台可能检测同设备多账号；同账号双开的限制见上节第 12 步；同一数据目录不能开两个进程（第 10 步）。

## cua-driver

trycua/cua 的 `libs/cua-driver`，MIT，stdio MCP，自身不调用任何模型：由调用它的 agent 决定动作，也可用 `cua-driver call <tool> '<json>'` 写无模型脚本。

- 安装：`/bin/bash -c "$(curl -fsSL https://cua.ai/driver/install.sh)"`。装 `/Applications/CuaDriver.app` 并链接 `~/.local/bin/cua-driver`；`raw.githubusercontent.com` 不通时先下载脚本再走代理执行。
- 授权：`cua-driver permissions grant` 弹出辅助功能与屏幕录制授权，必须用户本人在系统设置里允许；超时后再跑一次核验。`cua-driver permissions status` 查看。未授权时工具返回 `permissions_pending`。
- 接入：`cua-driver mcp-config --client claude|codex|...` 打印注册命令，同时往该客户端的 skills 目录装官方 skill 包（`--no-skills` 跳过）。Claude Code：`claude mcp add-json --scope user cua-driver '{"command":"<绝对路径>/cua-driver","args":["mcp"]}'`；多实例客户端要在各自 `CLAUDE_CONFIG_DIR` 下分别注册。
- 遥测默认开启：`cua-driver telemetry disable`。
- 读状态用 `get_window_state`（控件树+截图）、`get_desktop_state`；没有单独的 screenshot 工具。
- 官方矩阵（`docs/action-support.md`）里 macOS Electron 后台可用：左/右/双击、输入、按键、热键、子窗口；拖拽要应用 inspector 开着；后台滚动返回 `background_unavailable`，改用键盘翻页或切前台。
- `cua-perception` 扩展是 AGPL，按需单独安装。
