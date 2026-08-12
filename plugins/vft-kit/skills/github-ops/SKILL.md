---
name: github-ops
description: 通过 GitHub CLI 安全管理任意 GitHub 仓库、Actions、repository secrets 和 workflow。用于验证 token/仓库权限、列出或写入 Actions Secret、查看或重跑 Actions、触发 workflow；要求调用方通过 GH_TOKEN 或 gh 登录态供给凭据，不包含任何私有仓库或密钥路径。
---

# GitHub Ops

使用 `scripts/github-ops.mjs`，不要重新拼 `gh api`。脚本只依赖 Node.js 18+ 和 `gh`。

## 凭据

优先使用调用方提供的 `GH_TOKEN`；否则复用 `gh auth` 登录态。绝不输出 token，Secret 值只从 stdin 或文件读取。

## 命令

```bash
SKILL_DIR="<本 skill 的绝对路径>"

# 验证 token；指定仓库时同时验证仓库权限
node "$SKILL_DIR/scripts/github-ops.mjs" auth --repo owner/repo

# 仓库信息
node "$SKILL_DIR/scripts/github-ops.mjs" repo --repo owner/repo

# Actions Secrets
node "$SKILL_DIR/scripts/github-ops.mjs" secret list --repo owner/repo
printf '%s' "$VALUE" | node "$SKILL_DIR/scripts/github-ops.mjs" secret set --repo owner/repo --name NAME
node "$SKILL_DIR/scripts/github-ops.mjs" secret set --repo owner/repo --name NAME --value-file /secure/path
node "$SKILL_DIR/scripts/github-ops.mjs" secret delete --repo owner/repo --name NAME

# Actions runs
node "$SKILL_DIR/scripts/github-ops.mjs" run list --repo owner/repo
node "$SKILL_DIR/scripts/github-ops.mjs" run view --repo owner/repo --id 123
node "$SKILL_DIR/scripts/github-ops.mjs" run rerun-failed --repo owner/repo --id 123

# workflow_dispatch
node "$SKILL_DIR/scripts/github-ops.mjs" workflow run --repo owner/repo --workflow deploy.yml --ref main
```

## 规则

- 写 Secret、删除 Secret、重跑或触发 workflow 前，确认目标仓库和动作在用户授权范围内。
- `secret set` 禁止接受 `--value`，避免密钥进入 shell history 和进程列表。
- 写入后用 `secret list` 核验名称/更新时间；GitHub 不支持读回 Secret 原值。
- 私有默认仓库、凭据文件和业务动作放在私有继承 skill，不得写入本 skill。

