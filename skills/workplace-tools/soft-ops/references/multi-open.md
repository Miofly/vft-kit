# 双开 / 多开（给用户用的第 2、3… 个实例）

同一个桌面软件开多份、各登一个账号。AI 在后台隔离操作软件见 [background-gui.md](background-gui.md)；本文件只管「给用户自己用的副本」。下文「第 N 步」指 background-gui.md「Electron 独立实例」节的步骤。

## 选路线

| 情况 | 路线 | 结果 |
|---|---|---|
| 不是 Electron（无 `Contents/Frameworks/Electron Framework.framework`），如微信、QQ Mac 版 | 不做：复制改 Bundle ID 重签易出问题；要隔离就用虚拟机 | — |
| Electron，认 `--user-data-dir`，一个 Dock 图标就够 | A. `make-launcher.sh` 启动器 | 同一 App 的第二个进程，Dock/Cmd+Tab 合一，退出可能连坐 |
| Electron，但自己覆盖 `userData`、或数据/登录态按 `$HOME` 拼（WorkBuddy 国内版与 AI 版都是）；或用户要两个独立 App | B. `clone-app.sh` 整包复制 | 独立 bundle id、独立 Dock 图标、独立退出、私有 HOME |
| 副本登录要走网页授权 | B 加 `DUAL_EGO_PROFILE` | 副本打开的链接进指定 ego profile，不进带着第一个账号会话的默认浏览器 |

先判断数据是否跟着 `--user-data-dir` 走：用 A 起一个空目录实例，登录后看登录态文件落在哪（`~/.<app>`、`~/Library/Application Support/<厂商>/…` 有新写入即按 HOME 拼）；落不进新目录就改用 B。读 fuse 见第 1 步，B 加 ego 绑定需要 inspect fuse（第 4 个）开着。

## A. 启动器（`--user-data-dir`）

- 启动：`open -n -a /Applications/<App>.app --args --user-data-dir="$HOME/Library/Application Support/<app>-2"`。`-n` 强制新进程；`open -a` 不带 `-n` 会切到已开的实例。数据目录放 `~/Library/Application Support/` 下长期保留，不放会被清理的临时目录。
- 空目录 = 全新未登录实例，可登录另一个账号；要复用当前账号就按第 4 步复制 userData。给用户双开不加 `--inspect`（本机任意进程都能连该端口执行代码），只在 AI 后台操作时加。
- 要在「应用程序」里点开：用 [`scripts/dual-open/make-launcher.sh`](../scripts/dual-open/make-launcher.sh) `<源 .app> [编号=2] [输出目录=/Applications]` 生成 `<名称><编号>.app` 启动器（`DUAL_DATA_DIR` 改数据目录）。它只建启动器不启动应用；非 Electron 退出码 2，同名已存在退出码 3（启动器不含数据，重建时 `lsregister -u` 后直接删旧的；别把旧 .app 留在其他目录，Spotlight 会把每份都列成同名应用）。启动器逻辑：找「命令行以 `<源>/Contents/MacOS/<可执行> ` 开头、且含 `--user-data-dir=<目录>`」的进程（只提到这串文字的 shell/grep 不算，2026-11-05 自测曾误中测试 shell；也不能要求 `--user-data-dir` 紧跟可执行文件，带 `--inspect` 时它在后面，曾因此认不出已运行的副本而开出重复进程），已在运行就经 System Events 切前台，否则 `open -n`；不判断的话重复点击会对同一目录起第二个进程（第 10 步的损坏）。图标沿用原应用 `.icns`（脚本会删掉 osacompile 自带的 `Assets.car`/`CFBundleIconName`，否则盖住图标），`LSUIElement` 使启动器本身不进 Dock，ad-hoc 签名并 `lsregister -f`。终端 alias 指向同一个启动器：`alias <名>2='open -a /Applications/<名称>2.app'`。
- 隐藏副本的 Dock 图标：生成时加 `DUAL_HIDE_DOCK=1`。启动器用 `--inspect=127.0.0.1:<随机端口>` 启动，[`dock-hide.mjs`](../scripts/dual-open/dock-hide.mjs) 连上后改成 `setActivationPolicy('accessory')`，并把 `app.setActivationPolicy`、`app.dock.show` 改成空操作、`app.dock.isVisible` 恒返回 true，再 `inspector.close()` 关端口。只拦 `dock.show` 不够：有的应用自带 Dock 守护（Loomy `electron/windows/dock-controller.js` 每秒查 `dock.isVisible()`，不可见就 `setActivationPolicy('regular')` + `dock.show()`），图标会被恢复。2026-11-05 Loomy 实测：`ApplicationType` 为 `UIElement`，inspect 端口 2 秒内关闭，再点启动器不新增进程。代价：启动瞬间图标会闪一下；副本不进 Dock 和 Cmd+Tab，只能点启动器切回；调试端口在启动后几秒内对本机开放。核对：`lsappinfo info -only ApplicationType <pid>` 应非 `Foreground`，`lsof -nP -a -p <pid> -iTCP -sTCP:LISTEN` 无 inspect 端口。
- 回读：`pgrep -fl "user-data-dir=<目录>"` 有主进程，原实例 PID 仍在。

## B. 整包复制（`clone-app.sh`）

- 用户要求「两个独立 App」或应用自己覆盖数据路径时（2026-11-08 WorkBuddy AI 手工、WorkBuddy 国内版脚本实测）：`--user-data-dir` 和 applet 启动器都只得到「同一个 App 的第二个窗口」——`lsappinfo list` 里子进程仍注册为原 bundle id、原 bundle path，Dock/Cmd+Tab 只有一个条目，退出连坐。用 [`scripts/dual-open/clone-app.sh`](../scripts/dual-open/clone-app.sh) `<源 .app> [编号=2] [输出目录=/Applications]`：`cp -cR` 克隆 → 改 `CFBundleIdentifier`（原 id 加编号）/`CFBundleName`/`CFBundleDisplayName`/`CFBundleExecutable` → 同步改 `Contents/Frameworks/<名> Helper*.app` 的目录名、可执行文件名、`CFBundleExecutable`/`CFBundleName`/`CFBundleIdentifier`（helper 名取自 CFBundleName，漏改报 `FATAL ... electron_main_delegate_mac.mm:67 Unable to find helper app`）→ 新可执行文件是包装脚本，设私有 `HOME`（默认 `~/Library/Application Support/<名小写>-<编号>/home`，`DUAL_HOME` 覆盖）后 `exec` 原二进制 → ad-hoc 重签 + `lsregister -f`。数据按 `homedir()` 拼的应用只有改 `HOME` 才隔离；只写 `LSEnvironment` 时 `HOME` 不生效（2026-11-08 WorkBuddy AI 实测，只有应用自己的 `*_CONFIG_DIR` 变量生效，auth 仍共享）。

```bash
D=${VFT_KIT_DIR}/skills/workplace-tools/soft-ops/scripts/dual-open
DUAL_EGO_PROFILE="Profile 1" zsh $D/clone-app.sh "/Applications/<App>.app" 2      # 第 2 个
DUAL_EGO_PROFILE="Profile 3" zsh $D/clone-app.sh "/Applications/<App>.app" 3      # 第 3 个
DUAL_REPLACE=1 DUAL_EGO_PROFILE="Profile 1" zsh $D/clone-app.sh "/Applications/<App>.app" 2   # 重建
```

- 多开：编号递增，每份一个 HOME（默认 `~/Library/Application Support/<名小写、空格换 ->-<编号>/home`，`DUAL_HOME` 覆盖）。编号与 ego profile 的对应由使用者固定（私有层记录），同一个 profile 不要给同一网站的两个账号。
- 重建（源应用升级、改选项、给旧副本加 ego 绑定）：`DUAL_REPLACE=1`。副本在跑时拒绝（退出码 4），先正常退出它（`osascript -e 'tell application id "<新 id>" to quit'`）。包里不含用户数据，HOME 不动，重建后登录态沿用（2026-11-08 WorkBuddy AI2 实测：重建后仍是原第二账号，未弹钥匙串）。同名已存在且没给 `DUAL_REPLACE` 时退出码 3。
- 删除副本：先退出，`lsregister -u <副本>.app` 再删包；要连数据一起删，再删它的 HOME（不可恢复，先确认）。别把旧 .app 留在其他目录，Spotlight 会列出多个同名应用。
- 副本自带的 Squirrel 自动更新可能把改名覆盖掉；源应用升级后用 `DUAL_REPLACE=1` 重建。

### 网页登录绑定 ego profile

- 生成时加 `DUAL_EGO_PROFILE=<ego profile id>`（如 `Profile 1`），包装脚本带 `--inspect=127.0.0.1:<随机端口>` 启动，[`ego-external.mjs`](../scripts/dual-open/ego-external.mjs) 把主进程 `shell.openExternal` 的 http/https 改成在该 profile 新建 ego task space（名 `<副本名> web <时间>`）打开并 `handOff()` 给用户，随后关 inspector。不绑时链接走系统默认浏览器，它带着第一个账号的网页会话，网页一授权就把副本登成第一个账号。坑：`taskSpace(name,{profileId})` 对已存在的同名空间报 `profileId only applies when creating a new task space`，所以每次都用新名字；失败不回退默认浏览器（会登错账号），写 `<副本 HOME>/ego-external.log`。直接跑 `ego lite --profile-directory=…` 不会在运行中的 ego 里开页面，不能代替。限制：只拦 `shell.openExternal`，应用若自己 `spawn('open', url)` 则拦不到；inspect fuse 关闭的应用不能用（脚本不检查 fuse，启动后看 `ego-external.log` 或点一次登录核对）。
- 钩子的坑（2026-11-08 实测，已在 `ego-external.mjs` 处理）：① 连得太早时 `process.mainModule` 还没有，求值抛错就没装上、端口也没关（表现：`lsof` 仍看到 inspect 端口、`shell.openExternal.toString()` 仍是 `[native code]`），脚本现在返回 `wait` 并重试；② 注入代码是模板字符串里的 JS，里面不能写 `\n` 之类转义（会在求值时变真换行报 `SyntaxError`），用 `String.fromCharCode(10)`；③ 求值有 `exceptionDetails` 立即退出非零，不空等。
- 装没装上：启动后 inspect 端口几秒内消失即已返回 `ok`（只有成功分支才关端口）；端口一直在就是失败，可在端口还开着时手动 `HOME=$HOME node <副本>/Contents/Resources/ego-external.mjs <端口> "$(command -v ego-browser)" "<profileId>" "<副本名>"` 补装并看报错。

## 验收

- `lsappinfo info -only bundleid -only bundlepath "$(lsappinfo find pid=<副本 pid>)"` 为新 id 和副本路径、原 App 进程仍在；副本 HOME 下出现应用自己的数据目录（如 `.workbuddy`），原 `~/.<app>` 不被写；`lsof -nP -a -p <pid> -iTCP -sTCP:LISTEN` 无 inspect 端口；点副本登录后 `listTaskSpaces()` 里出现 `<副本名> web …` 且 `profileName` 是绑定的那个。
- 启动器路线：`pgrep -fl "user-data-dir=<目录>"` 有主进程，原实例 PID 仍在。

## 风险与限制

- 平台可能检测同设备多账号；同账号双开的限制见第 12 步；同一数据目录不能开两个进程（第 10 步）。
- 副本 HOME 的 `Documents` 是空的，应用产物不落在用户原工作区。
- Keychain 不随 HOME 隔离：Electron `safeStorage` 主密钥按应用名存在登录钥匙串，副本与原 App 共用；ad-hoc 重签后可能弹一次「允许访问」。
- 副本内部再起的子进程（如 WorkBuddy 用 `Electron` 以 RunAsNode 跑 `codebuddy` CLI）继承包装脚本的 `HOME`，一并隔离。
- 从 Dock 或菜单退出 A 路线的副本可能关掉同 bundle 的所有实例；B 路线各自独立。
