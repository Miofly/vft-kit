---
name: git-auto-push
description: 绕过 git hooks（husky / pre-commit / commit-msg / pre-push）执行 commit + push。用户说"绕过 hooks 提交"、"跳过钩子提交"、"强制提交"、"--no-verify 推送"、"force commit push"、"不跑 lint 直接推"、"hooks 卡住先推上去"等场景时触发。仅在用户明确要求时使用。
---

# Git Auto Commit + Push (Bypass Hooks)

绕过所有 git hooks 完成一次 `add → commit → push` 流程。

## 核心规则（最重要）

**用户调用本 skill = 已经明确授权全自动执行**。不要再问"是否提交 / 是否包含未跟踪文件 / 当前是 master 是否继续"之类的确认。一路跑到底，最后一次性汇报。

唯一会停下来询问的情形（红线）：
- 需要使用 `--force` / `--force-with-lease`（必须用户在当前对话明确要求才可加）
- 检测到工作区里**明显的敏感文件**未在 `.gitignore` 里：`.env*`（含真实 secret 的）、`*.pem`、`id_rsa`、`*.key`、`credentials.json` 等 —— 这时停下提示一句，让用户判断是否真要推

## 适用场景

- husky / lint-staged / commitlint 卡住，先推上去
- 大批量重构、WIP 备份到远端
- hooks 本身坏了，先推再修
- 用户原话提到 "绕过 hooks"、"跳过钩子"、"--no-verify"、"force commit / push"、"不跑 lint 直接推"

**禁止主动建议使用本 skill**。常规提交一律走标准流程。

## 执行流程（全自动，不打断）

### 1. 预检

并行执行（结果只用于自检 + 拟 commit message，不用于询问用户）：

```bash
git status --short
git diff --stat
git log -3 --oneline
git rev-parse --abbrev-ref HEAD
git remote -v        # 检测 HTTPS remote，避免 push 时弹 osxkeychain 框（见 step 1.1）
```

自检要点（**不向用户询问**，仅作为内部判断）：
- 当前分支是什么（master / main / release/* 也直接继续，不停下问）
- 工作区里有没有疑似敏感文件（仅当命中上面"红线"清单时才停下）
- remote 是 HTTPS 还是 SSH（命中 HTTPS 时按 step 1.1 处理）
- `git status` 是否出现 `(modified content)` / `(new commits)` 子目录提示 = 嵌套 gitlink，按 step 5.1 处理

### 1.1 HTTPS remote 自动转 SSH（macOS 必做）

macOS 上 HTTPS remote push 会触发 `git-credential-osxkeychain` 钥匙串弹框，并把当前 Bash 调用卡死（exit 137）。**预检时如果 `git remote get-url origin` 返回 `https://github.com/...` → 直接 `set-url` 改成 SSH，不要询问、不要点"始终允许"**。

```bash
url=$(git remote get-url origin)
case "$url" in
  https://github.com/*)
    ssh_url=$(echo "$url" | sed -E 's#https://github.com/([^/]+)/([^/.]+)(\.git)?#git@github.com:\1/\2.git#')
    git remote set-url origin "$ssh_url"
    ;;
esac
```

只对 `github.com` HTTPS 做转换；自建 GitLab / Gitee 等不动，保持原样。本机已配 GitHub SSH key 是前提。

**Gitee 仓库严禁自动转**：本机当前**没配 Gitee SSH key**（`ssh -T git@gitee.com` → `Permission denied (publickey)`）。`gitee.com` HTTPS 保持原样，让 osxkeychain 弹框时用户点"始终允许"即可。等以后配了 Gitee SSH key，再考虑加进这个自动转换列表。

### 2. 收集 commit message

**硬性要求**：
- **中文**
- **简略**（≤ 50 字）
- **快**：只看 step 1 已经拿到的 `git status --short` + `git diff --stat`，**不要**再读 diff 内容、不要扫每个文件。3 秒内拟不出来就直接用默认 fallback
- **不要**追加 `Co-Authored-By: Claude` 尾巴

**生成策略（按顺序，谁先命中用谁）**：

1. 用户在调用时已经提供 message → 直接用
2. 改动集中在一个目录 → `<type>(<目录名>): <动作> xxx`
   - 例：只改 `src/views/foo.vue` → `feat: 更新 foo 页面`
   - 例：只改 `.claude/skills/git-auto-push/SKILL.md` → `chore: 更新 git-auto-push skill`
3. 主要是新增文件 → `feat: 新增 xxx`
4. 主要是删除文件 → `chore: 清理 xxx`
5. 改动跨多个无关目录 / 看不出主线 / 超过 3 秒还没拟好 → **默认 fallback**：`chore: 更新代码`

**type 选择**（看主要改动性质）：
- 新功能、新文件 → `feat:`
- 修 bug → `fix:`
- 删除、清理、配置调整、文档 → `chore:`
- 重构 → `refactor:`
- 样式 → `style:`

**仓库风格参考**（看最近 3 条 `git log` 决定要不要带 scope、要不要中文）。本仓库历史多为 `feat: xxx` / `chore: xxx` 中文短消息，跟着就行。

### 2.1 默认 fallback message

当 step 2 第 5 条触发时，直接用：

```
chore: 更新代码
```

不要为了"想个更好的 message"而拖延。

### 3. 暂存改动

**默认 `git add -A`**，包含未跟踪文件。不要再问"是否包含未跟踪文件"。

```bash
git add -A
```

只有用户在调用时明确说"只推 xxx 文件" / "只 commit 已跟踪的" 才精确 add。

### 4. 执行 commit（跳过 commit-msg / pre-commit）

```bash
git commit --no-verify -m "<message>"
```

多行 message 用 HEREDOC：

```bash
git commit --no-verify -m "$(cat <<'EOF'
feat: xxx

- 细节 1
- 细节 2
EOF
)"
```

### 5. 执行 push（跳过 pre-push）

```bash
git push --no-verify
```

- 新分支没 upstream → `git push --no-verify -u origin <branch>`
- **禁止**自动 `--force` / `-f` / `--force-with-lease`。用户在当前对话明确要求才可加
- **禁止**在 `master` / `main` 上使用任何 force 变体

### 5.1 嵌套子仓库（gitlink）处理

当 step 1 看到 `git status` 报：

```
modified:   packages/web (modified content)
modified:   services/api (new commits)
```

说明子目录是独立 git 仓库（160000 gitlink 模式），父仓库只追踪它的 commit SHA。**默认全部纳入提交范围**（用户原话："子仓库也要纳入提交范围" 是常态需求）：

1. 对每个 `(modified content)` 的子仓库：cd 进去 → 跑完整的 step 1.1 / 2 / 3 / 4 / 5 流程（预检 remote、拟 message、add、commit、push）
2. 对每个 `(new commits)` 的子仓库：本身已经 commit 过，跳过 commit，只确保已 push（`git push --no-verify`）
3. 全部子仓库处理完后回父仓库 → `git add <子仓库路径>` 把 gitlink SHA 更新进 index → 父仓库走自己的 commit + push

父仓库的 commit message 用 `chore: 更新 <子仓库名> 子仓库引用`（多个子仓库改了就并列）。

**禁止**：父仓库 push 完就走，留着子仓库的 `(modified content)` 让用户自己再来一遍。

### 6. 验证 & 汇报

```bash
git log -1 --stat
git status
```

一次性汇报：
- commit hash + message
- 推到了哪个分支
- 是否还有未提交改动
- 如果有副作用（如 `git add -A` 顺手把内嵌 git 仓库以 gitlink 形式加进 index）也一并提一句

## 安全红线（这些情况停下询问 / 拒绝执行）

- **绝不**自动使用 `--force` / `--force-with-lease`
- **绝不**在 `master` / `main` / `release/*` 上 force push
- 检测到敏感文件（`.env*` 含真实 secret、`*.pem`、`id_rsa`、`*.key`、`credentials.json`）→ 停下提示
- 不要 `git config` 任何全局或仓库配置
- 不要 amend 历史 commit

## 正例

```bash
# 用户说"用 git-auto-push 提交一下"，没指定 message、没指定文件
# → 默认行为
git add -A
git commit --no-verify -m "<根据 diff 自拟的 message>"
git push --no-verify
git log -1 --stat
```

## 反例（禁止）

```bash
# ❌ 没拿到用户授权就 --force
git push --no-verify --force

# ❌ 在执行前问用户"当前是 master 分支，是否继续？"
# 用户调用本 skill 已经等于授权，直接跑

# ❌ 在执行前问用户"是否包含未跟踪文件？"
# 默认就是包含

# ❌ HTTPS remote 直接 push → 卡 osxkeychain 弹框 → exit 137
# 必须先按 step 1.1 转 SSH

# ❌ 父仓库看到 `(modified content)` 直接 commit
# → 子仓库的真实改动还在工作区，父仓库 add 不到任何东西，gitlink SHA 不变
# 必须先按 step 5.1 进子仓库 commit+push，再回父仓库 add gitlink
```
