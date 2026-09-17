---
name: git-ops
description: 通用 Git 操作：查看状态与历史、提交、分支管理、同步远端（pull/rebase/merge）、stash、撤销与回退、tag、冲突处理，以及分析改动后创建分支并提交 PR/MR（GitHub/GitLab/Gitee）。用户说"提交一下"、"建个分支"、"切分支"、"拉最新代码"、"rebase"、"解决冲突"、"撤销提交"、"回滚"、"打 tag"、"stash"、"提 PR"、"创建 PR"、"submit PR"、"给 xxx 提交代码"时使用。绕过 hooks 提交推送用 git-auto-push。
---

# Git Ops

日常 Git 操作与 PR 交付。简单操作直接执行 git 命令；PR 全流程调用内嵌脚本。

## 通用规则

1. **先看再动**：任何写操作前并行跑预检，结果用于自检，不逐条向用户汇报。

   ```bash
   git status --short
   git rev-parse --abbrev-ref HEAD
   git log -5 --oneline
   git remote -v
   ```

2. **用户下达操作 = 已授权**，正常路径不反复确认。只在下文“安全红线”命中时停下。
3. **commit message**：跟随仓库最近 `git log` 风格（本仓库为中文 `feat:` / `fix:` / `chore:` 短消息），≤ 50 字；用户给了 message 直接用。
4. **HTTPS → SSH（macOS）**：push/pull 前若 `origin` 是 `https://github.com/...`，先 `git remote set-url` 改为 `git@github.com:owner/repo.git`，避免 osxkeychain 弹框卡死进程。Gitee 本机没有 SSH key，保持 HTTPS。
5. **嵌套子仓库**：`git status` 出现 `(modified content)` / `(new commits)` 时，先进入子仓库完成提交与推送，再回父仓库 `git add <子仓库路径>` 更新 gitlink。
6. 结束时汇报：执行了什么、当前分支、最新 commit、是否还有未提交改动。

## 安全红线（停下询问）

- `push --force` / `--force-with-lease`：用户在当前对话明确要求才执行；`main` / `master` / `release/*` 上一律拒绝
- `reset --hard`、`clean -fd`、`checkout -- .`、`restore .`、`branch -D`、删除远端分支 / tag：会丢改动或影响他人，先说明影响再确认
- 改写已推送历史（`rebase` / `commit --amend` 已推送的提交）：先确认
- 待提交文件含 `.env*`（真实 secret）、`*.pem`、`*.key`、`id_rsa`、`credentials.json`：停下提示
- 不改 `git config --global`；不加 `--no-verify`（那是 git-auto-push 的职责）

## 操作速查

### 提交

```bash
git add -A                      # 用户指定文件时精确 add
git commit -m "<message>"
git push                         # 新分支：git push -u origin <branch>
```

hooks 失败时展示报错并修复后重新提交，不自动绕过。

### 分支

```bash
git switch -c <type>/<desc>      # 新建，命名：feat|fix|docs|chore|refactor/<kebab-desc>
git switch <branch>              # 切换；有未提交改动先 stash 或提交
git branch -d <branch>           # 删除已合并分支
git fetch --prune && git branch --merged <base> | grep -vE '^\*|main|master'   # 列出可清理分支，确认后删除
```

### 同步远端

```bash
git fetch origin
git pull --rebase                # 默认；仓库有 merge 惯例时用 git pull --no-rebase
git rebase origin/<base>         # 功能分支跟上主干
```

工作区不干净时先 `git stash push -u -m "<说明>"`，同步完 `git stash pop`。

### 冲突处理

1. `git status` 列出冲突文件，逐个读冲突块，按双方意图合并，不整文件选一边
2. 解决后 `git add <file>`，再 `git rebase --continue` / `git merge --continue`
3. 无法判断业务取舍时停下问用户；放弃用 `git rebase --abort` / `git merge --abort`

### stash

```bash
git stash push -u -m "<说明>"
git stash list
git stash pop                    # 冲突时保留 stash，解决后再 git stash drop
```

### 撤销与回退

| 需求 | 命令 | 风险 |
|---|---|---|
| 取消暂存 | `git restore --staged <file>` | 无 |
| 修改最后一次未推送提交 | `git commit --amend` | 已推送需确认 |
| 撤回最近提交，保留改动 | `git reset --soft HEAD~1` | 已推送需确认 |
| 回滚已推送提交 | `git revert <sha>` | 无，推荐 |
| 丢弃工作区改动 | `git restore <file>` / `git reset --hard` | 红线，需确认 |
| 找回丢失提交 | `git reflog` 后 `git switch -c rescue <sha>` | 无 |

### tag

```bash
git tag -a v<x.y.z> -m "<说明>"
git push origin v<x.y.z>
```

### 查看

```bash
git log --oneline --graph -20
git diff --stat [<base>...HEAD]
git blame -L <start>,<end> <file>
git log -S "<关键字>" --oneline  # 查某段代码何时引入
```

## PR 交付

用户说“提 PR / 创建 PR / 给 xxx 提交代码”时运行：

```bash
bash "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/dev-workflow/git-ops/scripts/git-pr.sh" [--base <branch>] [--title <title>] [--draft] [--dry-run]
```

流程：检查依赖 → 识别平台与目标分支 → 敏感文件检测 → 分析改动类型 → 在主干上则新建 `type/<目录>-updates-YYYYMMDD` 分支（已在功能分支则沿用）→ `git add -A` 并提交 → GitHub HTTPS 转 SSH → 推送 → `gh pr create` / `glab mr create` / 输出 Gitee 新建 PR 链接。

- 标题质量优先：先自己读 diff 拟好中文标题，用 `--title` 传入；不传时脚本按目录生成通用标题
- 不确定改动范围时先 `--dry-run` 看分支名、commit message 和 PR 描述
- 向开源项目贡献：脚本不会自动 fork。没有写权限时先 `gh repo fork --remote`，再运行脚本
- 目标仓库有 `CONTRIBUTING.md` 或 PR 模板时，PR 创建后按规范用 `gh pr edit --body` 补全描述

改动类型识别：

| 改动特征 | 类型 |
|---|---|
| 新增文件占比 > 60% | `feat` |
| 只改 `.md` | `docs` |
| 路径含 test/spec | `test` |
| 改 package.json / CI / yaml / config | `chore` |
| 新增行数 > 删除行数 × 2 | `feat` |
| 改动 ≤ 3 个文件 | `fix` |
| 其他 | `chore` |

依赖：`git`、`gh`（GitHub 必需，需 `gh auth login`）、`glab`（GitLab 可选）。

脚本退出码：`1` 环境或执行失败，`2` 参数错误，`3` 检测到敏感文件。

## 与其他 skill 的关系

- **git-auto-push**：仅在用户明确要求绕过 hooks 时使用（`--no-verify` 提交推送）
- **github-ops**：GitHub 仓库设置、Actions、Secrets 等平台操作
- **git-ops**（本 skill）：本地 Git 操作与 PR 交付
