---
name: cc-baseline
description: 一键核对本机 Claude Code 是否符合「装配基线」——逐项核对 CLI 工具（codegraph / rtk / node / claude）、全局 npm 包（lighthouse-mcp / codegraph）、MCP 注册（codegraph / lighthouse-mcp）、默认必备插件精简集（superpowers / skill-creator / code-review / frontend-design / playwright / claude-hud / remember）、系统配置（RTK hook、claude-hud 状态栏、cc-switch App）、以及配置基线（bypassPermissions、bypass 警告已接受、~ 目录已信任、codegraph 白名单、全局规范含「始终中文回复」「代码位置用可点短链」、默认关闭自动更新）。缺什么直接打印对应修复命令。可选 --health 参数额外实连核对核心 MCP（含 playwright）。用户说"cc-baseline"、"核对下基线"、"检查我的 cc 工具装齐了没"、"工具链体检"、"cc-doctor"（旧称）、"哪些工具没装"、"环境自检"、"看看必备插件/MCP 全不全"、"换机器后核对一下 cc 装配"、"重装后哪些没恢复"、"claude code 环境检查"等场景时触发。即使只说"体检一下"或"我的 cc 配置全吗"，且上下文是 Claude Code 工具链时，也用本 skill。纯只读，不改任何配置。
---

# cc-baseline —— Claude Code 装配基线核对

对照「本机装配基线」逐项核对安装/注册/启用状态，缺什么给什么修复命令。**只读**，不改任何配置。

基线 = 一台机器上 Claude Code「该长什么样」的规格：必备 CLI、全局 npm 包、MCP 注册、插件精简集、系统配置、权限与规范基线。清单本身就是资产——本 skill 既是核对器，也是这份规格的落地处。

## 怎么用

直接跑脚本：

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/cc-baseline/scripts/check.sh
```

输出是分六类的 ✓/✗/○ 清单 + 汇总。退出码：必需项齐全=0，有必需项缺失=1（可选项缺失不影响退出码）。

- `✓` 绿 = 已装/已启用
- `✗` 红 = **必需**项缺失，行尾直接给修复命令
- `○` 黄 = 可选项未装（brew / jq / cc-switch App），不算故障

跑完把结果回报给用户；有 `✗` 就把对应修复命令一并列出，问用户要不要补齐。

## 检查六类（数据来源）

| 类别 | 检查项 | 数据来源 |
|---|---|---|
| CLI 工具 | node / npm / claude / **rtk** / **codegraph** / brew / jq | `command -v` |
| 全局 npm 包 | `@colbymchenry/codegraph` / `@danielsogl/lighthouse-mcp` | `$(npm root -g)/<pkg>` 目录 |
| MCP 注册 | codegraph / lighthouse-mcp | `~/.claude.json` 的 `mcpServers`（含各 project scope） |
| 插件（必备集 + 可选） | 必备：superpowers / skill-creator / code-review / frontend-design / playwright / claude-hud / remember / typescript-lsp / jdtls-lsp / security-guidance / claude-md-management / context-mode；可选：context7 / vercel | `~/.claude/plugins/installed_plugins.json`（确定性文件读，覆盖 user/project/local 全 scope） |
| 系统配置 | RTK hook / **RTK 压缩豁免（cat/diff/find）** / claude-hud 状态栏 / cc-switch App | `settings.json` 的 `hooks`、`statusLine`；`~/Library/Application Support/rtk/config.toml` 的 `[hooks].exclude_commands`；`/Applications/CC Switch.app` |
| 配置基线 | **bypassPermissions** / **bypass 警告已接受** / **~ 目录已信任** / codegraph 只读白名单 / 全局 CLAUDE.md（必需）/ **全局规范含「始终中文回复」**（必需）/ **全局规范含「代码位置用可点短链」**（必需）/ **默认关闭自动更新**（必需）；通知 hook / skill-symlink hook / memory 目录（可选） | `settings.json` 的 `permissions`、`hooks`、`env.DISABLE_AUTOUPDATER`；`~/.claude.json` 的 `bypassPermissionsModeAccepted`、`projects[$HOME].hasTrustDialogAccepted`；`~/.claude/CLAUDE.md`（含正文 grep）、`~/.claude/projects/` |

## 关键实现细节（改脚本前必读）

- **插件用 `~/.claude/plugins/installed_plugins.json` 判断，不要用 `claude plugin list`，也不要只读 `settings.json` 的 `enabledPlugins`**。三个坑叠加：① 插件可以装在**项目** scope（`.claude/settings.json`，team 共享进 git），这类插件在用户全局 `enabledPlugins` 里根本没有 → 只查全局会误报「缺失」；② `claude plugin list` 慢（逐个实连 MCP 做健康检查，十几秒）、输出不稳定（同一状态多次跑条目数会变），**且实测跑它本身会触发 CC 重建 `installed_plugins.json`**，越查越乱；③ `installed_plugins.json` 是磁盘上的安装事实（含 scope、marketplace、version），一次文件读，快且确定，覆盖所有 scope。所以本 skill 只读这个文件。
- **默认必备插件集是「精简集」（可按需增删，见 scripts/check.sh 顶部清单）**：superpowers / skill-creator / code-review / frontend-design / playwright / claude-hud / remember / typescript-lsp / jdtls-lsp / security-guidance / claude-md-management / context-mode。其中 `typescript-lsp`（前端 Vue/TS）与 `jdtls-lsp`（后端 Java）是分语言 LSP，`security-guidance` 是官方内联安全审查（改码时扫命令注入/反序列化/XSS 并当场修）。这是一份「够用就好」的精简集，不追求把装过的插件全列进来。要加/减默认集，改 `check.sh` 里第 4 类的第一个 `for p in ...` 清单即可。多数走 `*)` 默认命令 `claude plugin install $p@claude-plugins-official`；来源不同的要加专属 case：`context-mode` 来自第三方 marketplace `mksglu/claude-context-mode`（本体是 Context Mode MCP，插件方式装完自带 hooks + 11 个 ctx_* 工具），`claude-hud` 来自 `jarrodwatts/claude-hud`。自建的本地插件按需自行加 case。
- **可选插件（装了显示 ✓，不装显示 ○ 不算故障）**：context7 / vercel（均来自 `claude-plugins-official`）。在第 4 类必备集循环后另有一个 `for p in context7 vercel` 循环，用 `opt` 而非 `bad`，缺失不影响退出码。要加/减可选插件改这个循环。
- **MCP 注册要扫所有 scope**：`~/.claude.json` 顶层 `mcpServers` 之外，各 `projects[<path>].mcpServers` 也要并进来（否则 project scope 注册的 MCP 会漏报）。
- **npm 全局包查目录不查 `npm ls -g`**：`npm ls -g <pkg>` 慢且对子依赖会误判；直接 `[ -d "$(npm root -g)/<pkg>" ]` 又快又准。
- **codegraph 的 target id 是 `claude` 不是 `claude-code`**：修复命令 `codegraph install -t claude -l global -y`。
- **文件夹信任弹窗（"Is this a project you trust?"）由 `~/.claude.json` 的 `projects[<dir>].hasTrustDialogAccepted` 控制**，不是 `settings.json`。`~`（`$HOME`）默认是 `false`，在家目录起 CC 会弹确认；设为 `true` 免弹。本 skill 检查 `$HOME` 是否已信任。
- **「始终中文回复」规范查的是全局 `~/.claude/CLAUDE.md` 的正文（grep 关键字），不是文件存不存在**：用户硬性要求所有项目一律简体中文回复，这条必须写进全局 CLAUDE.md 才对所有会话生效。`claudemd_has_chinese` 用 `grep -Eq '中文回复|简体中文|一律中文|reply.*[Cc]hinese'` 探测，缺失=必需项 `✗`，修复命令直接 `printf ... >> ~/.claude/CLAUDE.md` 把规范追加进去。加/改关键字或规范文案，改 `check.sh` 的 `claudemd_has_chinese` 函数与对应 `bad` 行。
- **「代码位置用可点短链」同理查全局 `~/.claude/CLAUDE.md` 正文**：用户主要在 **IDEA 的 CC 插件**里用，裸文件名 / 纯相对路径（`config.ts`、`utils.ts:310`）点击定位不到会报 `Cannot open file`，所以引用代码位置必须写成 markdown 链接 `[短名:行](绝对路径:行)`——显示短、href 是绝对路径+行号才跳得动。这条也是跨所有会话恒定的输出规范，与「中文回复」并列写进全局 CLAUDE.md。`claudemd_has_shortlink` 用 `grep -Eq '可点短链|短链|markdown 可点|Cannot open file'` 探测，缺失=必需项 `✗`。加/改关键字改 `check.sh` 的 `claudemd_has_shortlink` 函数与对应 `bad` 行。
- **自动更新默认关（`env.DISABLE_AUTOUPDATER=1`）**：基线要求 CC 版本由人工掌控，不让 auto-updater 静默改动工具链。**关闭方式只有环境变量一条路**——`settings.json` 没有顶层 `autoUpdates`/`autoUpdaterStatus` 键（只有 `autoUpdatesChannel`，那是选渠道不是开关），`/config` 里也没有交互开关，只能写进 `env` 块。两个坑：① `env` 是**整体替换不是深合并**，若优先级更高的 `settings.local.json` 也写了 `env`，会把 user 层整个 `env` 顶掉（连代理、OTEL 一起失效），排查"设了没生效"先看 local 层有没有 `env` 键；② 关掉后**升级要按 CC 的实际安装方式来**——`npm i -g` 只对 npm 全局装的有效，若 `claude` 是 Volta/nvm 等版本管理器托管的（`command -v claude` 落在 `~/.volta/` 等路径下），得用对应工具升级（如 `volta install @anthropic-ai/claude-code@latest`），用 npm 装了不生效。
- **bypass 权限警告弹窗（"WARNING: running in Bypass Permissions mode / Yes, I accept"）由 `~/.claude.json` 顶层的 `bypassPermissionsModeAccepted` 控制**（未公开字段，官方文档查不到）。设 `permissions.defaultMode=bypassPermissions` 后每次启动都会弹此警告；把 `bypassPermissionsModeAccepted` 设为 `true`（即点过 "Yes, I accept" 后 CC 自己写的值）可永久免弹。字段名可从 CC 原生二进制 `grep -a bypassPermissionsModeAccepted` 确认（注意 `strings` 读不到，二进制里 JS 是压缩的，要用 `grep -a`）。
- **RTK 压缩豁免（`[hooks].exclude_commands`）防止「静默错误结果」**：`rtk hook claude` 挂在 PreToolUse[Bash] 上，会把有代理的命令改写成 `rtk <cmd>` 过压缩——**连管道和重定向也改**（`cat f | jq` → `rtk read f | jq`、`cat f > out` 把过滤后内容写进文件）。对多数命令（git/grep/ls/tree/build）这是省 token 的主战场、低风险；但三条命令的压缩会造成**静默的错误结果**，必须原样透传：① `cat`→`rtk read` 大文件截断 / 重定向损坏文件复制 / 管道喂下游残缺内容；② `diff`→`rtk diff` 输出浓缩成非标准格式，没法当 patch；③ `find`→`rtk find` 结果截断成 tree，喂 xargs 漏文件。基线要求 `~/Library/Application Support/rtk/config.toml` 的 `[hooks].exclude_commands` 至少含 `cat`/`diff`/`find`。`rtk_excludes_verbatim` 用 grep 那一行 + 逐个匹配 `"cmd"` 判断，缺任一即 `bad`，修复命令 `rtk config --create` + `sed` 填数组。要加/减豁免命令改这个函数的 `for cmd in ...` 与配置。**注意 RTK 不碰的命令**（逆向类 `otool`/`nm`/`lldb`/`objdump`/`xxd`、还有 `codesign`/`python3`/`echo`）本就是「No rewrite」透传，不用加进豁免；真正会被压缩的只有 RTK 有代理的那批。保留压缩的命令若临时要原始输出，单次用 `rtk proxy <原命令>`。另注 `grep`/`rg` 压缩会截断到 `[limits].grep_max_results`（默认 200/文件 25），做「穷尽式全量搜索」时同理用 `rtk proxy grep` 或直接 `/usr/bin/grep`。

## 各工具标准安装命令（脚本里也内嵌为修复提示）

```bash
# MCP 载体（全局 npm 包）
npm i -g @colbymchenry/codegraph @danielsogl/lighthouse-mcp

# 注册进 CC（codegraph 用自带命令自动接入；lighthouse node 直跑 dist 绕 npx 冷启）
codegraph install -t claude -l global -y
claude mcp add lighthouse-mcp      -s user -- node "$(npm root -g)/@danielsogl/lighthouse-mcp/dist/index.js"

# RTK（省 token 命令代理）
brew install rtk && rtk init -g --auto-patch

# 插件 marketplace + 安装（缺 marketplace 时先 add）
claude plugin marketplace add jarrodwatts/claude-hud
claude plugin install claude-hud@claude-hud             # 装完在 CC 里跑 /claude-hud:setup 配状态栏

# cc-switch（多账号切换 App，可选）
brew install --cask cc-switch

# 默认关闭自动更新（版本由人工掌控；关闭开关只有 env 这一条路）
jq '.env.DISABLE_AUTOUPDATER="1"' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

> 装完 MCP / 插件 / 状态栏后**必须重启 CC 会话**才生效。补齐后重跑 `check.sh` 复核。
