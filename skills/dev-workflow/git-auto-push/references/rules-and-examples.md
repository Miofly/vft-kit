# git-auto-push 规则与正反例

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
