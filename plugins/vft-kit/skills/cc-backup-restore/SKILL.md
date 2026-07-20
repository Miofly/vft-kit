---
name: cc-backup-restore
description: 备份、恢复或彻底清理本机 Claude Code。备份/恢复覆盖全局 CLAUDE.md 及其 @ 引用、settings、插件清单与 marketplace、项目 memory、hooks、skills、agents、commands 和 Playwright MCP 配置；清理覆盖 Claude Code 进程、安装包、命令入口、配置/缓存、shell 环境变量及 npm 缓存。用于换账号、重装 CC、换机器前后，或用户说“备份 cc 配置”“恢复 cc 配置”“清除 cc 信息”“卸载 Claude Code”“检查 Claude 残留”等场景。备份默认不搬登录授权；跨机器迁移 token/身份/代理用 cc-auth-migrate，恢复个人基线用 cc-bootstrap。清理具有破坏性，必须先展示范围并由用户交互确认。
---

# Claude Code 配置备份 / 恢复 / 清理

备份或恢复 `~/.claude` 下的配置与数据；需要重置环境时，先生成脱敏备份，再交互清理并检查残留。

## 职责边界（先分清，别用错）

| | 本 skill | cc-auth-migrate | cc-bootstrap |
|---|---|---|---|
| 干什么 | 搬配置 + 数据；按确认彻底清理 CC | 搬登录授权（token / 身份 / 代理） | 装个人基线（权限白名单 / RTK / 常用 MCP） |
| 场景 | 换号 / 重装 / 换机；清空本机 CC 信息 | 目标机不方便走浏览器 OAuth | 新机器 / 新号想要「默认就绪」的环境 |
| 副作用 | 备份/恢复只拷文件；清理会卸载软件并删除数据 | 写入登录态 | **装软件、改权限模式** |

**本 skill 刻意不做基线安装**：一个「恢复备份」的动作不该顺手改你的 `defaultMode`、`brew install` 二进制、全局 `npm i -g`。那些是「初始化新环境」的语义，拆在 cc-bootstrap 里。三者可按需先后使用。

## 清理前固定顺序

用户同时要求备份和清理时，严格按以下顺序执行，不能并行：

1. 运行 `cc-backup.sh`，确认输出目录存在且包含 `MANIFEST.txt` 和 `cc-restore.sh`。
2. 向用户报告备份目录；只有用户明确继续清理后，才启动 `claude-cleaner.sh`。
3. 在清理工具中选择 `[2] 清理环境`，让工具展示删除范围，并由用户在终端输入 `Y` 确认。
4. 清理完成后重新运行工具，选择 `[3] 检查残留`。

不要代替用户输入清理确认，不要用管道自动喂 `Y`。清理会结束 Claude 相关进程，当前 Claude Code 会话可能随之中断；执行前必须先把备份路径报告给用户。

## 备份（换号 / 重装前）

```bash
bash "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/cc-backup-restore/scripts/cc-backup.sh"
```

产出 `~/cc-backups/cc-backup-<时间戳>/`（可用 `CC_BACKUP_ROOT` 环境变量改目标目录），**自包含**：内含 `cc-restore.sh` + `README.md` + `MANIFEST.txt`，整个目录拷到任何机器都能独立恢复，不依赖本仓库。

备份内容：

- 顶层 md——`CLAUDE.md` **以及它 `@` 引用的同级 md**（如 `RTK.md`）。只拷 CLAUDE.md 会让 `@RTK.md` 引用悬空。
- `settings.json` / `settings.local.json`，**备份时即剔除 `env` / `oauthAccount` / `oauthToken`**。恢复本来就不用它们，留着只是把代理凭据 / OTEL 端点摊在磁盘上。
- 插件：`installed_plugins.json` **+ `known_marketplaces.json`**。**两者缺一不可**——清单只记「装了哪些插件」，来源在 marketplace 里；少了来源，自建 / 私有 marketplace 的插件恢复时无从下载。另出一份人读的 `plugin-list.txt`。
- 各项目 `memory/`、`hooks/`、`skills/`、`agents/`、`commands/`。
- Playwright MCP 的 `.mcp.json` 留档（插件重装会覆盖它，留个档好把 `--output-dir` 手动补回）。

## 恢复（换号 / 重装 / 换机后）

新账号登录后，进备份目录跑恢复脚本。**默认带 `-y` 非交互执行，全程零点击**——恢复只搬文件、覆盖前都留 `.pre-restore-*.bak` 回滚点，无破坏性，不需要用户逐步确认：

```bash
cd ~/cc-backups/cc-backup-<时间戳>
bash cc-restore.sh -y       # 默认：非交互，零点击
```

也可以不 cd，直接指定备份目录（推荐这种，一条命令搞定）：

```bash
bash "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/cc-backup-restore/scripts/cc-restore.sh" ~/cc-backups/cc-backup-<时间戳> -y
```

> 不加 `-y` 时脚本会 `read` 一句 `继续？(y/N)` 等你敲回车——那是**脚本自身**的交互，跟 Claude Code 的权限模式无关。想要零点击就始终带 `-y`（本 skill 默认如此）。
>
> **关于「dangerously-skip-permissions」**：它是 CC 的**启动 flag**（`claude --dangerously-skip-permissions`），只在进程启动时生效，skill 在已运行的会话里**无法为当前进程开启它**，也不该去改。它对应的持久化配置是 `settings.json` 的 `permissions.defaultMode: "bypassPermissions"`——若已设该值，恢复期间 CC 本就不会问 yes；剩下唯一的「点击」就是上面脚本的 `y/N`，用 `-y` 消掉即可。所以本 skill 用 `-y` 达成零点击，不去碰权限配置。

恢复行为要点：

- **settings.json 是合并不是覆盖**：以当前 live 配置为底，用备份覆盖结构项，并再次 `del(.env, .oauthAccount, .oauthToken)` 兜底——即使拿到的是老格式备份，也绝不把旧 token / 代理注回新号。
- **覆盖前留回滚点**：每个被覆盖的文件另存 `*.pre-restore-<时间戳>.bak`。
- **directory 型 marketplace 会做存在性校验**：自建插件仓库（本地 directory 型）在 `known_marketplaces.json` 里是绝对路径引用，换机后路径不存在就装不回来。脚本会逐个查、缺的直接点名，而不是让你在启动时静默少几个插件。
- **hook 引用的本地脚本会做存在性校验**：`settings.json` 里 hook 的 `command` 能指向任意本地脚本（不止 `hooks/` 目录，如公司监控 `cc-otel/*.js`、`~/.cc-helper/*.sh`）。备份只搬固定几个资产目录，换机 / 换号后这些「目录外」脚本可能不在——CC 每次触发该事件就 `MODULE_NOT_FOUND` / command not found 刷屏。脚本恢复后扫 `.hooks` 的 command，抠出带脚本扩展名的路径逐个查、缺的点名，让你当场决定「补脚本」还是「删掉那条 hook」。
- memory / hooks / skills / agents / commands 按原路径还原；插件在下次启动 CC 时自动重装。
- Playwright 的 `--output-dir` 需插件装好后手动补（脚本会提示，目标目录见全局 CLAUDE.md 的 Playwright 段落）。

### 恢复完成后：自动核对基线（cc-baseline）

`cc-restore.sh` 跑完后，**紧接着自动执行 cc-baseline 的核对脚本**，把「换机 / 重装后哪些还没恢复到位」一次性亮出来。恢复只搬配置与数据、**不装软件**（见职责边界），所以换机后 CLI（codegraph / node）、全局 npm 包、MCP 注册、插件二进制这些大概率还缺——恢复完立刻核对，正好接上这道缺口，不用用户再手动想起来跑一次。

```bash
bash "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/cc-baseline/scripts/check.sh"
```

- 这一步**纯只读**，不改任何配置，可无条件自动跑（不需要用户点头）。
- 核对结果按 cc-baseline 自己的规矩回报：缺失项用「项 | 作用」两列表格讲清每项干什么、缺了什么影响，**不要把修复命令罗列给用户**。
- **补齐仍走 cc-baseline 的确认流程**——除 `ponytail` 缺失可静默补齐（常设授权）外，其余 `✗` 项都要等用户点头再照脚本内嵌命令补。恢复动作本身绝不顺手补基线。
- 若插件是「下次启动 CC 才自动重装」，此刻核对可能仍报若干插件 `✗`，属正常；回报时提示用户「重启会话后插件会自动装回，可再跑一次核对」。

## 清理与残留检查

启动 Skill 内置的交互式清理工具：

```bash
bash "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/cc-backup-restore/scripts/claude-cleaner.sh"
```

菜单用途：

- `[2] 清理环境`：展示目标后再次确认，随后停止进程、卸载 brew/npm/apt/dnf/apk 包、删除命令入口与常见配置/缓存，并清理 shell 环境变量和 npm 缓存。
- `[3] 检查残留`：只读检查进程、命令、常见路径和环境变量；清理后必须运行。
- `[1] 备份` / `[4] 恢复备份`：来自清理工具的通用能力，会保留更广的原始数据，可能包含 token、API key 和本地路径。常规备份/恢复优先使用本 Skill 的 `cc-backup.sh` / `cc-restore.sh`，它们会脱敏并保留插件来源。

脚本支持 macOS、Linux 和 WSL；WSL 只处理 Linux 侧，不清理 Windows AppData。清理不扫描项目目录。

依赖 `jq`（macOS `brew install jq`）。没有 `jq` 时脚本不中断，但会**跳过 settings 脱敏与合并**并打印警告——此时备份里含敏感 `env`，务必注意下面的红线。

## 恢复脚本只有一份

`cc-backup.sh` 把同目录的 `cc-restore.sh` 原样 `cp` 进备份目录，实现自包含。**不要**改回「在备份脚本里内嵌一份 heredoc 副本」——那样同一份逻辑要维护两处，必然漂移（历史上已经漂过）。

## 安全红线

- 备份**默认不含**登录态与 `env`。但 `hooks/` / `skills/` / `memory/` 里可能有你自己写进去的敏感内容，仍**不要提交进 git、不要贴聊天 / 截图**。
- 备份默认落在 `~/cc-backups/`（不在 iCloud 可能同步的 `~/Documents` 下）。要改位置用 `CC_BACKUP_ROOT`，注意别放进会自动同步 / 上传的目录。
- 恢复会覆盖当前配置（有 `.bak` 可回滚）。`-y` 跳过确认前，请自行确认目标机是想被覆盖的那台。
