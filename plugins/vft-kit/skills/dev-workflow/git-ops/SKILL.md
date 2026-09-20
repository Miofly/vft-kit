---
name: git-ops
description: Git 版本管理与协作：根据 diff 生成提交信息、检查 Commit 规范、解决 merge/rebase 冲突、辅助分支管理、Code Review、生成 PR/MR 描述及交付。用户说“生成 commit”“检查提交规范”“提交一下”“解决冲突”“整理分支”“review 改动”“写 PR 描述”“提 PR”，或需要同步、stash、回退、tag 时使用。GitHub/GitLab/Gitee 均适用；平台设置和 CI 运维用 github-ops。
---

# Git Ops

围绕实际改动完成版本管理与协作。先判断用户要的是文字、检查还是执行；“生成提交信息 / PR 描述”只生成内容，“Review”只报告发现，不隐含提交、推送、发布评论或合并授权。

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
| “只给暂存内容生成提交信息” | [commits.md](references/commits.md) | 可直接使用的 message；不暂存、不提交 |
| “检查 main 到当前分支的 Commit 规范” | [commits.md](references/commits.md) | 校验工具、范围、违规项；缺工具标明人工检查，不改历史 |
| “解决当前 rebase 冲突并验证” | [branches-conflicts.md](references/branches-conflicts.md) | 合并双方意图、定向测试、rebase 终态；业务取舍不明时只问该项 |
| “列出已合并的分支，先不删” | [branches-conflicts.md](references/branches-conflicts.md) | 候选及依据，排除受保护/占用分支；不切换、不删除 |
| “Review 当前分支相对 main 的改动” | [review-pr.md](references/review-pr.md) | 文件位置、严重度、触发条件、后果与证据；不发布评论 |
| “按仓库模板写 PR 描述” | [review-pr.md](references/review-pr.md) | 问题、行为变化及真实验证记录；仅在另有交付授权时创建 PR |

## 执行边界

- 用户已授权的正常操作直接完成。仅生成文字或 Review 时不修改仓库；未明确要求创建/切换分支或 worktree 时保持当前工作区。PR 分支与目标相同则说明阻塞，不自行建分支。
- 暂存只用已确认的文件/补丁；先核对已有暂存区，保留无关改动，不默认 `git add -A`、自动 stash 或提交所有文件。只有用户明确要求全部改动且检查范围后才全量暂存。
- 不改全局 Git 配置、不自动改 remote 协议、不绕过 hooks。钩子失败先修复授权范围内的问题，再重新核对暂存内容。缺工具不静默安装依赖。
- 强推、丢弃修改、删除远端分支/tag、改写已推送历史需要明确授权；已有明确授权不重复询问。强推仍遵守保护分支规则，用指定旧 SHA 的 `--force-with-lease`，不裸 `--force`。
- 疑似真实密钥停止提交/推送，只报告脱敏的文件位置。文件名筛查不等于内容安全扫描；优先复用仓库 secret scanner，示例配置也要检查值。记录实际工具、扫描的提交范围和结果；未运行时明确“未做内容安全扫描”。
- 外部操作结果不确定时先查询现状再重试。推送、PR 创建、CI 和合并是不同状态；不把其中一个成功当作全部完成。

## 日常速查

以下命令中的占位符要换成已核对的值；只有任务需要时才执行。

| 操作 | 命令与限制 |
|---|---|
| 取消指定文件暂存 | `git restore --staged -- <file>`，不覆盖其他暂存内容 |
| 撤回未推送提交，保留改动 | `git reset --soft HEAD~1`，先核对提交范围 |
| 回滚公开提交 | `git revert <sha>`；merge commit 先确认 mainline，不能猜 `-m 1` |
| 修改未推送的最近提交 | `git commit --amend`，不顺手夹带其他暂存内容 |
| 找回提交 | `git reflog` / `git show <sha>`；创建救援分支需用户要求 |
| 打 tag | `git tag -a <tag> -m <说明>`；推送单个 tag 需包含在授权内 |
| 查历史 | `git log --oneline --graph -20` / `git blame -L <start>,<end> <file>` / `git log -S <text> -- <file>` |

## PR 脚本

[scripts/git-pr.sh](scripts/git-pr.sh) 只推送已提交的当前分支并创建/复用 PR/MR，不负责暂存、提交、切分支或生成通用文案。调用前按 [review-pr.md](references/review-pr.md) 完成范围核对、标题正文生成和验证。

```bash
bash <git-ops目录>/scripts/git-pr.sh --base main \
  --title 'fix(auth): 修复过期会话重试' --body-file <正文文件绝对路径> --dry-run
```

已授权 PR 交付时去掉 `--dry-run`；`--draft` 创建草稿。正文写入宿主指定的产物目录或可清理的系统临时文件。脚本支持 GitHub/GitLab 同仓库分支；fork、非标准托管域名按平台 CLI 手动处理。Gitee 仅推送并输出待创建的对比链接。

依赖 Git、Python 3.9+；正式交付按平台需要 `gh` 或 `glab`。退出码：`1` 环境/状态/远端失败，`2` 参数错误，`3` 疑似敏感文件。`--dry-run` 不联网、不依赖平台登录；使用本地远端引用，可能过期。自检：`python3 <git-ops目录>/scripts/selftest.py`。

## 完成证明

按本次范围简报：改动/审查对象、验证结果、当前分支与提交 SHA、剩余修改；PR 另核对仓库身份、URL、base/head、远端 head SHA，新建时核对标题、正文和草稿状态。未执行的检查明确标注，不编造通过状态。

平台账号、仓库设置、Actions、Secrets 用 `github-ops`；不把这些能力嵌入本 skill。

## 工具集成

- 本地状态、暂存区和冲突索引使用 Git；message 校验、lint、测试和内容安全扫描复用项目已有工具，不重复造校验器。
- 平台读取/交付可按宿主规则使用已配置的 MCP/连接器或 `gh` / `glab`。先发现实际工具和参数，不假设某个 MCP 服务名或工具名存在；仅在能指定仓库、base/head 并回读 URL/状态/SHA 时用于对应交付步骤。
- MCP 不可用或信息不完整时使用 CLI；缺少 CLI 时仍可完成本地 Review、message 和 PR 正文生成，并准确标记远端步骤未执行。脚本本身使用 CLI，不包含 MCP 服务。
- 每次远端写入只选择一个通道。MCP/CLI 写入超时先查询同一目标现状，不能换通道再创建一次。GitHub 账号权限与 Actions 等任务按需衔接可用的 `github-ops`。
