---
name: git-ops
description: Git 版本管理与协作：根据 diff 生成提交信息、检查 Commit 规范、解决 merge/rebase 冲突、辅助分支管理、Code Review、生成 PR/MR 描述及交付。用户说”生成 commit””检查提交规范””提交一下””解决冲突””整理分支””review 改动””写 PR 描述””提 PR””评审这个 MR””CR 一下”，或需要同步、stash、回退、tag 时使用。GitHub/GitLab/Gitee 均适用；平台设置和 CI 运维用 github-ops。
---

# Git Ops

围绕实际改动完成版本管理与协作。先判断用户要的是文字、检查还是执行；”生成提交信息 / PR 描述”只生成内容，”Review”只报告发现，不隐含提交、推送、发布评论或合并授权。

## 何时用

生成提交信息、检查 Commit 规范、解决 merge/rebase 冲突、整理分支、Review 改动、写或提交 PR/MR、stash/回退/tag。平台账号、仓库设置、Actions、Secrets 用 `github-ops`。

## 硬规则

- 只生成文字或 Review 时不修改仓库；未明确要求时不建、不切分支或 worktree。
- 只暂存已确认的文件；不默认 `git add -A`、不自动 stash、不绕过 hooks、不改全局 Git 配置。
- 强推、丢弃修改、删除远端分支/tag、改写已推送历史需明确授权；强推只用指定旧 SHA 的 `--force-with-lease`。
- 疑似真实密钥立即停止提交/推送，只报告脱敏位置；没做内容安全扫描要明说。
- 推送、PR 创建、CI、合并分别核实；结果不确定先查现状再重试，每次远端写入只走一个通道。
- 未执行的检查明确标注，不编造通过状态。

## 路由

| 任务 | references | 脚本 |
|---|---|---|
| 功能范围、预检命令、请求示例与交付边界、执行边界 | [overview-boundaries.md](references/overview-boundaries.md) | — |
| 提交信息、Commit 规范检查 | [commits.md](references/commits.md) | — |
| 冲突解决、分支整理 | [branches-conflicts.md](references/branches-conflicts.md) | — |
| 本地 Review、PR/MR 描述 | [review-pr.md](references/review-pr.md)；评审清单 [mr-review-checklist.md](references/mr-review-checklist.md) | — |
| 日常速查、PR 交付、完成证明、工具集成 | [daily-pr-delivery.md](references/daily-pr-delivery.md) | [git-pr.sh](scripts/git-pr.sh)；自检 [selftest.py](scripts/selftest.py) |
