---
name: cc-backup-restore
description: 备份 / 恢复本机 Claude Code 的配置与数据（全局 CLAUDE.md 及其 @ 引用的 md、settings.json、插件清单 + marketplace 来源、各项目 memory、hooks、skills、agents、commands、Playwright MCP 配置留档），用于换账号、重装 CC、换机器前后。用户说"备份 cc 配置"、"备份 claude code"、"换号前先备份"、"重装 claude code 前保存配置"、"恢复 cc 配置"、"把之前备份的 cc 配置恢复回来"、"换账号后配置没了"、"cc 记忆/插件/hooks 恢复"等场景时触发。本 skill 只搬「配置与数据」，不装任何软件、不改权限模式、不搬登录授权——跨机器免登录搬 token/身份/代理用 cc-auth-migrate；恢复后想要个人基线（权限白名单 / RTK / 常用 MCP）用 cc-bootstrap。
---

# Claude Code 配置备份 / 恢复

把 `~/.claude` 下的**配置与数据**打包成一个自包含备份目录，换号 / 重装 / 换机后一键恢复。

## 职责边界（先分清，别用错）

| | 本 skill | cc-auth-migrate | cc-bootstrap |
|---|---|---|---|
| 干什么 | 搬配置 + 数据 | 搬登录授权（token / 身份 / 代理） | 装个人基线（权限白名单 / RTK / 常用 MCP） |
| 场景 | 换号 / 重装 / 换机后恢复「我的规范、记忆、插件」 | 目标机不方便走浏览器 OAuth | 新机器 / 新号想要「默认就绪」的环境 |
| 副作用 | 只拷文件，覆盖前留 `.bak` | 写入登录态 | **装软件、改权限模式** |

**本 skill 刻意不做基线安装**：一个「恢复备份」的动作不该顺手改你的 `defaultMode`、`brew install` 二进制、全局 `npm i -g`。那些是「初始化新环境」的语义，拆在 cc-bootstrap 里。三者可按需先后使用。

## 备份（换号 / 重装前）

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/cc-backup-restore/scripts/cc-backup.sh"
```

产出 `~/cc-backups/cc-backup-<时间戳>/`（可用 `CC_BACKUP_ROOT` 环境变量改目标目录），**自包含**：内含 `cc-restore.sh` + `README.md` + `MANIFEST.txt`，整个目录拷到任何机器都能独立恢复，不依赖本仓库。

备份内容：

- 顶层 md——`CLAUDE.md` **以及它 `@` 引用的同级 md**（如 `RTK.md`）。只拷 CLAUDE.md 会让 `@RTK.md` 引用悬空。
- `settings.json` / `settings.local.json`，**备份时即剔除 `env` / `oauthAccount` / `oauthToken`**。恢复本来就不用它们，留着只是把代理凭据 / OTEL 端点摊在磁盘上。
- 插件：`installed_plugins.json` **+ `known_marketplaces.json`**。**两者缺一不可**——清单只记「装了哪些插件」，来源在 marketplace 里；少了来源，自建 / 私有 marketplace 的插件恢复时无从下载。另出一份人读的 `plugin-list.txt`。
- 各项目 `memory/`、`hooks/`、`skills/`、`agents/`、`commands/`。
- Playwright MCP 的 `.mcp.json` 留档（插件重装会覆盖它，留个档好把 `--output-dir` 手动补回）。

## 恢复（换号 / 重装 / 换机后）

新账号登录后，进备份目录跑恢复脚本：

```bash
cd ~/cc-backups/cc-backup-<时间戳>
bash cc-restore.sh          # 交互确认
bash cc-restore.sh -y       # 非交互
```

也可以不 cd，直接指定备份目录：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/cc-backup-restore/scripts/cc-restore.sh" ~/cc-backups/cc-backup-<时间戳> -y
```

恢复行为要点：

- **settings.json 是合并不是覆盖**：以当前 live 配置为底，用备份覆盖结构项，并再次 `del(.env, .oauthAccount, .oauthToken)` 兜底——即使拿到的是老格式备份，也绝不把旧 token / 代理注回新号。
- **覆盖前留回滚点**：每个被覆盖的文件另存 `*.pre-restore-<时间戳>.bak`。
- **directory 型 marketplace 会做存在性校验**：自建插件仓库（本地 directory 型）在 `known_marketplaces.json` 里是绝对路径引用，换机后路径不存在就装不回来。脚本会逐个查、缺的直接点名，而不是让你在启动时静默少几个插件。
- memory / hooks / skills / agents / commands 按原路径还原；插件在下次启动 CC 时自动重装。
- Playwright 的 `--output-dir` 需插件装好后手动补（脚本会提示，目标目录见全局 CLAUDE.md 的 Playwright 段落）。

依赖 `jq`（macOS `brew install jq`）。没有 `jq` 时脚本不中断，但会**跳过 settings 脱敏与合并**并打印警告——此时备份里含敏感 `env`，务必注意下面的红线。

## 恢复脚本只有一份

`cc-backup.sh` 把同目录的 `cc-restore.sh` 原样 `cp` 进备份目录，实现自包含。**不要**改回「在备份脚本里内嵌一份 heredoc 副本」——那样同一份逻辑要维护两处，必然漂移（历史上已经漂过）。

## 安全红线

- 备份**默认不含**登录态与 `env`。但 `hooks/` / `skills/` / `memory/` 里可能有你自己写进去的敏感内容，仍**不要提交进 git、不要贴聊天 / 截图**。
- 备份默认落在 `~/cc-backups/`（不在 iCloud 可能同步的 `~/Documents` 下）。要改位置用 `CC_BACKUP_ROOT`，注意别放进会自动同步 / 上传的目录。
- 恢复会覆盖当前配置（有 `.bak` 可回滚）。`-y` 跳过确认前，请自行确认目标机是想被覆盖的那台。
