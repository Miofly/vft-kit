---
name: git-auto-push
description: "仅在用户明确要求绕过 Git hooks、--no-verify 或不跑 lint 提交推送时使用，执行 commit + push。"
---

# Git Auto Commit + Push (Bypass Hooks)

绕过所有 git hooks 完成一次 `add → commit → push` 流程。

## 何时用

仅当用户原话要求绕过 hooks、跳过钩子、`--no-verify` 或不跑 lint 直接推时使用。常规提交走标准流程，禁止主动建议本 skill。

## 硬规则

- 调用本 skill 即授权全自动执行：不再确认分支或未跟踪文件，跑完一次性汇报。
- 只在两种情况停下询问：需要 force（须用户在当前对话明确要求）；发现未被忽略的敏感文件（`.env*`、`*.pem`、`id_rsa`、`*.key`、`credentials.json`）。
- `master` / `main` / `release/*` 绝不 force push；不改 `git config`；不 amend 历史提交。
- 默认 `git add -A`；commit 与 push 都带 `--no-verify`。
- message 用中文、≤50 字，只依据 `git status --short` 与 `git diff --stat` 拟定，拟不出就用 `chore: 更新代码`；不加 AI `Co-Authored-By`。
- macOS 上 `github.com` 的 HTTPS remote 先转 SSH；Gitee 等其它托管不转。
- 嵌套子仓库（gitlink）先逐个 commit + push，再回父仓库 add gitlink 并提交。

## 路由

| 任务 | 读取 |
|---|---|
| 授权规则、适用场景、安全红线、正例与反例 | [rules-and-examples.md](references/rules-and-examples.md) |
| 预检、HTTPS 转 SSH、拟 message、暂存、commit、push、子仓库、验证汇报 | [workflow.md](references/workflow.md) |

本 skill 没有脚本，按 [workflow.md](references/workflow.md) 里的命令逐步执行。
