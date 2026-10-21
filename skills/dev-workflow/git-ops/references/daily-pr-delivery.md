# 日常速查、PR 交付与工具集成

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

[scripts/git-pr.sh](../scripts/git-pr.sh) 只推送已提交的当前分支并创建/复用 PR/MR，不负责暂存、提交、切分支或生成通用文案。调用前按 [review-pr.md](review-pr.md) 完成范围核对、标题正文生成和验证。

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
