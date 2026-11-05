# profile 列举、指定与导入

## 机制

ego lite 是 Chromium，每个 profile 一套独立的 cookie、登录态、书签、扩展。复用某账号的登录态，就是让 task space 建在登录了该账号的 profile 上。

## 列举

```js
console.log(await profiles());
// [{ id: "Default", isDefault: true, name: "<菜单显示名>" }, { id: "Profile 3", isDefault: false, name: "..." }, ...]
```

- `name` 对应 ego 菜单栏「个人资料」里的名字，`id` 是数据目录名。
- 现有 space 落在哪个 profile：`listTaskSpaces()` 每项带 `profileId` / `profileName`。
- `ego-browser import list` 列的是**本机其他浏览器**（Chrome/Edge/Brave 等）可导入的 profile，不是 ego 自己的 profile。

## 指定

```js
const p = (await profiles()).find((x) => x.name === "<名字>");
const task = await taskSpace("<任务短名> " + p.id, { profileId: p.id });
```

- `profileId` 只在**新建** space 时生效；同名 space 已存在会直接续用、忽略 `profileId`。所以 space 名带上 profile id，或先 `listTaskSpaces()` 确认。
- 用户没指定 profile 时不要去查、去选，默认 profile 即可。

## 导入

`ego-browser import --browser chrome|edge|brave [--profile <目录名，如 Default / "Profile 1">]`：把其他浏览器的数据（书签、密码、登录态等）导进 ego。先 `import list` 看源 profile 目录名。

## 数据目录（macOS）

`~/Library/Application Support/Citro Labs/ego lite/<profileId>/`，含 `Bookmarks`、`Cookies`、`Preferences` 等。只读分析可以直接读；**写入一律走浏览器内 API**（书签用 `scripts/ego-bookmarks.sh`），运行中的浏览器会覆盖对文件的外部修改。

## 登录态约定

一个用户目标一个 task space；已有登录态不重新登录；登录态缺失才走该平台登录流程，验证码 / 2FA / 扫码用 `task.handOff()` 交用户，不代登录。
