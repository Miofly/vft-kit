# 提交生成与规范检查

## 选定输入

1. 指定文件/范围优先。已有暂存时以 `git diff --cached` 为本次提交事实，不把未暂存修改写进 message。仅生成文字且无暂存时可以读取工作区 diff 和相关未跟踪文件，注明来源，不自动暂存。
2. 读取完整相关 diff 与调用方，区分行为变化、重构、测试和文档。文件数量、新增比例不能决定 `feat` / `fix`。混合目的可给出拆分建议；不擅自重排用户暂存区或拆改已提交历史。
3. 执行提交前用精确路径/补丁暂存，再重新读取 staged diff。已有无关暂存无法明确归属时，先完成 message 草稿，再询问范围，不直接 commit 整个索引。

## 生成 message

规则优先级：用户指定内容与仓库强制规则一起核对 → commitlint / CONTRIBUTING → 最近提交惯例。用户 message 违反强制规则时指出具体项和最小修正版，不静默替换。

没有项目规范时采用 Conventional Commits，语言跟随仓库或用户：

```text
fix(auth): 避免过期会话重复触发登录

并发请求复用登录恢复结果，防止多个请求重复刷新会话。
```

- `feat` 新能力，`fix` 修复缺陷；`docs` / `test` / `refactor` / `perf` / `build` / `ci` / `chore` 按实际目的选择，允许仓库自定义类型。
- scope 取稳定模块名；没有合适 scope 就省略。首行说明可观察变化，不用“更新文件 / 修复问题”或行数统计替代语义。
- 正文仅补充必要原因、行为或迁移信息；不编造 issue、测试、性能收益。长度遵守仓库配置，无配置时简短，不把 50/72 字当通用硬门槛。
- 不兼容变更用 `!` 或 `BREAKING CHANGE:`，说明受影响接口与迁移方式；仓库配置可能要求两者同时存在。

## 检查

优先使用项目已有脚本/已安装的 commitlint，检查其配置是否成功加载。不要用可能下载包的 `npx` 作为默认路径。例如仓库根存在本地 commitlint 时：

```bash
./node_modules/.bin/commitlint --edit <message文件>
./node_modules/.bin/commitlint --from <base-sha> --to HEAD --verbose
```

范围检查中的 `--from` 不包含该提交。新建仓库的首个提交用 message 文件检查；merge/revert/fixup 的豁免服从项目配置，不为了格式擅自重写历史。

未安装校验器时做人工检查并标注“人工检查，未运行 commitlint”：type/scope、非空摘要、正文空行、breaking/footer、长度及内容是否对应 diff。用户要求接入强制校验时才修改 hooks/CI，复用已有管理方式。

检查失败时报告“提交 SHA 或候选 message → 违反规则 → 修正内容”；历史审计只报告，不默认 amend/rebase。单独运行 `git diff --cached --check` 检查补丁空白与冲突标记，它不是 message 校验器。

## 执行与回读

提交前按改动运行最小相关检查；是否允许构建服从项目规定。message 用文件与 `git commit -F <file>`，保留真实换行，避免 shell 展开反引号或 `$()`。正常执行 hooks；钩子更改文件后再次核对和暂存授权范围。

提交后读取 `git show --stat --oneline HEAD`、`git log -1 --format=%B`、`git status --short`，核对实际提交文件和 message。只有用户要求推送/PR 交付时才 push，并比对远端分支 SHA。

参考：[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)、[commitlint CLI](https://commitlint.js.org/reference/cli.html)。
