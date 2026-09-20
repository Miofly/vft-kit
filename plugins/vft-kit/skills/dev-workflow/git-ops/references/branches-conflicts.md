# 分支、同步与冲突

## 分支辅助

先查 `git branch -vv`、`git worktree list`、当前分支和 upstream。默认分支从远端 HEAD/平台信息确定，不猜 main/master。分支关系可用 `git rev-list --left-right --count <upstream>...HEAD`；它只反映本地引用，需要最新状态时先 fetch。

- 仅要求“推荐分支名/整理建议”时输出建议，不切换。明确创建时校验 `git check-ref-format --branch <name>`，命名遵循仓库惯例，确认基点后 `git switch -c <name> <start-point>`。
- 切分支前检查 staged、unstaged、untracked 和其他 worktree 占用。能原样保留的修改不必 stash；会覆盖或归属不清时不默认丢弃/夹带。
- 清理先 `git branch --merged <base>` 列候选；排除当前分支、base、保护分支和其他 worktree 占用的分支。明确清理授权后才 `git branch -d <name>`，失败不升级 `-D`；squash merge 后不能仅据“未合并”推断可删除。
- detached HEAD、无 upstream、无远端、浅克隆缺少 merge base 时明确状态。可做只读分析；不创建分支、不猜基点、不自动全量 unshallow。

## 同步与 stash

1. 核对 remote/upstream，执行授权范围内的 fetch。能快进用 `git merge --ff-only <upstream>`；分叉时遵循仓库 merge/rebase 约定。已推送共享提交不默认 rebase。
2. 脏工作区不自动 stash。确需临时保存且范围已获授权时，用带说明的 stash，记录其 OID；`-u` 包含未跟踪文件，不包含 ignored 文件。
3. 恢复优先 `git stash apply --index <oid>`，验证内容和暂存状态后，再找到对应 stash 条目并 drop。apply 失败/冲突时保留原 stash；不得顺手 drop 最新条目。

## 解决冲突

先识别当前操作，不重复发起 merge/rebase：

```bash
git status
git diff --name-only --diff-filter=U
git ls-files -u
git rev-parse --git-path rebase-merge
git rev-parse --git-path rebase-apply
```

后两个命令只返回路径，需检查路径是否存在；同时核对 `MERGE_HEAD`、`CHERRY_PICK_HEAD`、`REVERT_HEAD` 等实际状态。自动化处理文件列表用 `-z`，避免空格/换行路径被切断。

1. 对每个冲突读取上下文、调用方、测试与相关提交。index stage 1 是共同祖先，2/3 是两侧；可用 `git show ':1:path'`、`':2:path'`、`':3:path'` 查看，新增/删除冲突可能缺某一 stage。
2. merge 时 ours 通常是当前分支；rebase 时 ours 是重放到的基线，theirs 是正在重放的提交。先确认 SHA 和业务意图，不能把 ours/theirs 永远映射为“我的/别人的”。
3. 文本冲突整合双方意图；删除/修改、重命名冲突同时核对路径与引用。二进制无法逐行合并时说明选择依据；业务意图矛盾且证据不足时只询问该决策，先处理其余独立冲突。
4. 锁文件先解决依赖声明，再用项目既有包管理器/版本重生成，检查无额外版本漂移；生成文件从源文件重建。不得机械拼接锁文件或整文件选一边。
5. 仅暂存已解决文件，检查 `git diff --cached --check`、未合并索引为空、相关文本无残留冲突标记，再运行最小相关测试。语法通过不代表双方业务语义保留。
6. 按实际操作执行 `git rebase --continue` / `git merge --continue` / `git cherry-pick --continue` / `git revert --continue`；重复到终态。stash 冲突无 `--continue`，解决后检查工作区即可。不得为了通过而 `--skip` 丢掉提交。
7. `--abort` 会撤销当前冲突解决成果，只有用户要求放弃或恢复方案已明确授权时使用；不用 hard reset“清场”。

结束核对：操作状态已消失、`git ls-files -u` 为空、分支/提交正确、定向测试结果与剩余修改明确；解决冲突不隐含 push 授权。

参考：[Git checkout 的 ours/theirs 与 rebase 语义](https://git-scm.com/docs/git-checkout)。
