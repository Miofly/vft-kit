# 功能范围、预检与执行边界

## 功能范围

- **本地 Git 操作**：提交信息生成、规范检查、分支管理、冲突解决、stash/回退/tag
- **代码评审**：本地 diff 评审、PR/MR 描述生成
- **远端协作**：PR/MR 创建与交付（GitHub/GitLab/Gitee）

## 入口与预检

在目标 Git 仓库执行；嵌套仓库先确认 `git rev-parse --show-toplevel`，不自动递归提交子仓库。

```bash
git status --short --branch
git branch --show-current
git log -5 --format=%s
git diff --stat
git diff --cached --stat
```

空仓库没有 HEAD 时跳过历史。读取适用的 AGENTS.md、CONTRIBUTING、commitlint 配置、hooks 和 PR 模板；仓库规则优先于历史风格。远端地址仅在本地解析，输出前去掉内嵌凭据。

| 请求示例 | 按需读取 | 预期交付与边界 |
|---|---|---|
| “只给暂存内容生成提交信息” | [commits.md](commits.md) | 可直接使用的 message；不暂存、不提交 |
| “检查 main 到当前分支的 Commit 规范” | [commits.md](commits.md) | 校验工具、范围、违规项；缺工具标明人工检查，不改历史 |
| “解决当前 rebase 冲突并验证” | [branches-conflicts.md](branches-conflicts.md) | 合并双方意图、定向测试、rebase 终态；业务取舍不明时只问该项 |
| “列出已合并的分支，先不删” | [branches-conflicts.md](branches-conflicts.md) | 候选及依据，排除受保护/占用分支；不切换、不删除 |
| “Review 当前分支相对 main 的改动” | [review-pr.md](review-pr.md) | 文件位置、严重度、触发条件、后果与证据；不发布评论 |
| “按仓库模板写 PR 描述” | [review-pr.md](review-pr.md) | 问题、行为变化及真实验证记录；仅在另有交付授权时创建 PR |

## 执行边界

- 用户已授权的正常操作直接完成。仅生成文字或 Review 时不修改仓库；未明确要求创建/切换分支或 worktree 时保持当前工作区。PR 分支与目标相同则说明阻塞，不自行建分支。
- 暂存只用已确认的文件/补丁；先核对已有暂存区，保留无关改动，不默认 `git add -A`、自动 stash 或提交所有文件。只有用户明确要求全部改动且检查范围后才全量暂存。
- 不改全局 Git 配置、不自动改 remote 协议、不绕过 hooks。钩子失败先修复授权范围内的问题，再重新核对暂存内容。缺工具不静默安装依赖。
- 强推、丢弃修改、删除远端分支/tag、改写已推送历史需要明确授权；已有明确授权不重复询问。强推仍遵守保护分支规则，用指定旧 SHA 的 `--force-with-lease`，不裸 `--force`。
- 疑似真实密钥停止提交/推送，只报告脱敏的文件位置。文件名筛查不等于内容安全扫描；优先复用仓库 secret scanner，示例配置也要检查值。记录实际工具、扫描的提交范围和结果；未运行时明确“未做内容安全扫描”。
- 外部操作结果不确定时先查询现状再重试。推送、PR 创建、CI 和合并是不同状态；不把其中一个成功当作全部完成。
