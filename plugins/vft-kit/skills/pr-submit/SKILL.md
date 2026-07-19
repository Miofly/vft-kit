---
name: pr-submit
description: 智能 PR 提交工具。自动分析改动、生成 PR 描述、创建分支、提交并创建 Pull Request。支持 GitHub/GitLab/Gitee，可分析目标仓库贡献指南自动适配格式。用户说"提 PR"、"创建 PR"、"submit PR"、"发起 pull request"、"给 xxx 提交代码"等场景时触发。
version: 1.0.0
---

# PR Submit - 智能 Pull Request 提交工具

全自动分析改动、生成高质量 PR 描述、创建并提交 Pull Request。

## 核心能力

1. **智能改动分析**：自动分析 git diff、识别改动类型和影响范围
2. **贡献指南适配**：读取目标仓库的 CONTRIBUTING.md、PR 模板，自动适配格式
3. **多平台支持**：GitHub (`gh`)、GitLab (`glab`)、Gitee (`git`)
4. **分支管理**：自动创建规范分支名、处理冲突
5. **Fork 检测**：自动检测是否需要 fork、设置 remote
6. **子仓库支持**：识别并处理 submodule/gitlink

## 适用场景

### 向开源项目提交贡献
```
用户："给 chinese-independent-developer 这个项目提 PR，添加我的网站"
→ 自动 fork、分析贡献指南、创建分支、生成符合项目规范的 PR
```

### 自己的仓库提交功能
```
用户："提个 PR 到 master"
→ 创建 feature 分支、分析改动、生成 PR 描述、推送并创建 PR
```

### 子仓库联合提交
```
用户："blog 项目和它的 submodule 一起提 PR"
→ 先处理 submodule 的 PR，再处理父仓库的 PR，PR 描述中关联子仓库 PR 链接
```

## 执行流程

### 1. 环境预检

```bash
# 检查 CLI 工具
command -v gh >/dev/null 2>&1  # GitHub
command -v glab >/dev/null 2>&1  # GitLab
command -v git >/dev/null 2>&1  # 通用

# 检查认证状态
gh auth status 2>&1 | grep -q "Logged in"
glab auth status 2>&1 | grep -q "Logged in"

# 检查当前仓库状态
git status --porcelain
git remote -v
git branch --show-current
git log -1 --oneline
```

**关键判断**：
- 是否是 fork（remote 有 upstream）
- 需要提交到哪个仓库（origin/upstream）
- 当前是否在 main/master 分支（需要创建新分支）
- 是否有未提交的改动

### 2. 目标仓库分析（针对开源贡献）

如果是向别人的仓库提交：

```bash
# 获取目标仓库信息
gh repo view <owner>/<repo> --json name,description,defaultBranchRef

# 下载贡献指南（优先级顺序）
gh repo view <owner>/<repo> --web  # 浏览器打开查看
curl -sL "https://raw.githubusercontent.com/<owner>/<repo>/<branch>/CONTRIBUTING.md"
curl -sL "https://raw.githubusercontent.com/<owner>/<repo>/<branch>/.github/CONTRIBUTING.md"
curl -sL "https://raw.githubusercontent.com/<owner>/<repo>/<branch>/.github/PULL_REQUEST_TEMPLATE.md"
curl -sL "https://raw.githubusercontent.com/<owner>/<repo>/<branch>/docs/contributing.md"
```

**从贡献指南中提取**：
- PR 标题格式要求（如：`feat: xxx` / `[Feature] xxx`）
- PR 描述模板（如：必须包含 `## What` / `## Why` 等章节）
- 分支命名规范（如：`feature/xxx` / `fix/xxx`）
- 提交信息格式（如：Conventional Commits）
- 是否需要签署 CLA
- 是否需要关联 Issue

**关键：用 3 秒快速扫描**，提取核心规则，不要逐字分析。

### 3. 改动分析

```bash
# 获取改动统计
git diff --stat HEAD
git diff --shortstat HEAD
git status --short

# 识别改动类型
git diff --name-status HEAD
```

**智能分类**（按优先级）：

1. **新增功能** (`feat`)
   - 新增文件占比 > 60%
   - 新增行数 > 删除行数 * 2
   - 关键词：`add`、`create`、`new`、`implement`

2. **Bug 修复** (`fix`)
   - 改动集中在已有文件
   - 删除/修改行数接近
   - 包含测试文件改动
   - 关键词：`fix`、`bug`、`issue`、`error`

3. **文档更新** (`docs`)
   - 只改 `.md` 文件
   - 只改 `docs/` 目录

4. **样式调整** (`style`)
   - 只改 `.css`/`.scss`/`.less` 文件
   - 或只改代码格式（空格、缩进）

5. **重构** (`refactor`)
   - 多文件改动
   - 新增/删除行数接近
   - 无新增文件

6. **测试** (`test`)
   - 只改测试文件

7. **构建/配置** (`chore`)
   - 改 `package.json`、`pom.xml`、配置文件
   - 改 CI/CD 配置

8. **其他** (`chore`)
   - 兜底分类

### 4. 生成 PR 描述

**模板结构**（根据目标仓库要求调整）：

```markdown
## 变更说明

<一句话概括这次改动的目的和价值>

## 主要改动

- <改动点 1>：<具体说明>
- <改动点 2>：<具体说明>
- <改动点 3>：<具体说明>

## 测试

- [x] 本地测试通过
- [ ] 添加了单元测试
- [ ] 更新了文档

## 相关链接

- 相关 Issue: #<issue_number>（如果有）
- 依赖 PR: <submodule_pr_link>（如果是父仓库）

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

**描述生成规则**：

1. **简洁但完整**：标题 ≤ 70 字符，描述 ≤ 500 字
2. **量化改动**：`新增 3 个组件`、`优化 40% 性能`、`修复 2 个内存泄漏`
3. **突出价值**：说清楚"为什么要这样改"，不只是"改了什么"
4. **中英文适配**：
   - 中文仓库 → 全中文
   - 国际开源项目 → 全英文
   - 判断依据：README 前 500 字的语言
5. **关联上下文**：
   - 如果改动涉及 Issue → 自动链接（`Closes #123`）
   - 如果是子仓库 → 关联子仓库 PR
   - 如果是系列改动 → 关联前序 PR

### 5. 分支管理

**分支命名规则**（按目标仓库要求 > 改动类型自动生成）：

```
feat/<feature-name>
fix/<bug-description>
docs/<doc-update>
refactor/<refactor-scope>
chore/<task-name>
```

**自动生成逻辑**：
1. 用户指定分支名 → 直接用
2. 读到贡献指南的分支规范 → 遵循
3. 否则根据改动类型自动生成：
   - `feat/add-throttled-deploy-workflow`
   - `fix/memory-leak-in-usage-hook`
   - `docs/update-pr-submit-skill`

**冲突处理**：
```bash
# 分支已存在
git branch | grep -q "^[* ]*${branch_name}$" && {
  # 追加时间戳
  branch_name="${branch_name}-$(date +%Y%m%d%H%M%S)"
}
```

### 6. Fork 处理（开源贡献）

```bash
# 检测是否已 fork
gh repo view <owner>/<repo> --json isFork

# 未 fork → 自动 fork
gh repo fork <owner>/<repo> --remote=false

# 设置 remote
git remote | grep -q "^upstream$" || {
  git remote add upstream https://github.com/<owner>/<repo>.git
}

# 确保 fork 最新
git fetch upstream
git checkout <default_branch>
git merge upstream/<default_branch>
```

### 7. 提交流程

#### 7.1 创建分支并提交

```bash
# HTTPS → SSH（macOS 避免 osxkeychain 弹框）
url=$(git remote get-url origin)
if [[ "$url" == https://github.com/* ]]; then
  ssh_url=$(echo "$url" | sed -E 's#https://github.com/([^/]+)/([^/.]+)(\.git)?#git@github.com:\1/\2.git#')
  git remote set-url origin "$ssh_url"
fi

# 创建并切换分支
git checkout -b "$branch_name"

# 暂存改动
git add -A

# 生成 commit message
commit_msg="<type>: <short_description>

<detailed_description>

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"

# 提交
git commit -m "$commit_msg"

# 推送
git push -u origin "$branch_name"
```

#### 7.2 创建 PR

**GitHub**:
```bash
gh pr create \
  --repo <owner>/<repo> \
  --title "$pr_title" \
  --body "$pr_body" \
  --base <default_branch>
```

**GitLab**:
```bash
glab mr create \
  --repo <owner>/<repo> \
  --title "$pr_title" \
  --description "$pr_body" \
  --target-branch <default_branch>
```

**Gitee** (无官方 CLI，用 API):
```bash
curl -X POST "https://gitee.com/api/v5/repos/${owner}/${repo}/pulls" \
  -H "Content-Type: application/json" \
  -d "{
    \"access_token\": \"${GITEE_TOKEN}\",
    \"title\": \"${pr_title}\",
    \"head\": \"${username}:${branch_name}\",
    \"base\": \"${default_branch}\",
    \"body\": \"${pr_body}\"
  }"
```

### 8. 子仓库处理

检测到 submodule/gitlink 改动时：

```bash
git status | grep -E '\(modified content\)|\(new commits\)'
```

**处理策略**：

1. **先处理子仓库**：
   - 进入子仓库目录
   - 递归执行完整 PR 流程（step 1-7）
   - 获取子仓库的 PR 链接

2. **再处理父仓库**：
   - 回到父仓库
   - `git add <submodule_path>` 更新 gitlink
   - PR 描述中添加：`依赖子仓库 PR: <submodule_pr_link>`
   - 创建父仓库 PR

### 9. 验证与汇报

```bash
# 验证 PR 创建成功
gh pr view <pr_number> --json url,title,state

# 检查 CI 状态（可选）
gh pr checks <pr_number>
```

**汇报内容**：
```
✅ PR 已创建成功！

PR 链接：<pr_url>
分支：<branch_name>
标题：<pr_title>
目标分支：<base_branch>

下一步：
- 等待 CI 检查通过
- 等待维护者审核
- 如需修改，继续在 <branch_name> 分支提交即可
```

## 高级功能

### 10.1 批量 PR（monorepo）

用户说"给 packages 下的所有改动分别提 PR"：

```bash
# 检测改动的 package
git status --short | awk '{print $2}' | grep '^packages/' | cut -d/ -f2 | sort -u

# 每个 package 创建独立分支和 PR
for pkg in $packages; do
  branch="feat/${pkg}-updates"
  git checkout -b "$branch"
  git add "packages/${pkg}"
  git commit -m "feat(${pkg}): <changes>"
  git push -u origin "$branch"
  gh pr create --title "feat(${pkg}): <changes>" --body "..."
  git checkout <base_branch>
done
```

### 10.2 Draft PR

用户说"先提个草稿 PR"：

```bash
gh pr create --draft --title "WIP: <title>" --body "..."
```

### 10.3 PR 模板检测

```bash
# 检查是否有 PR 模板
gh api "repos/<owner>/<repo>/contents/.github/pull_request_template.md" 2>/dev/null

# 有模板 → 下载并填充
curl -sL "<template_url>" | sed "s/<!-- .* -->//g"
```

## 安全规则

1. **绝不自动 force push**
2. **绝不直接提交到 main/master**（必须创建分支）
3. **检测敏感文件**：`.env`、`*.pem`、`*.key` → 停下警告
4. **Fork 确认**：向别人仓库提交时，确保推送到自己的 fork
5. **分支保护**：检测到目标分支有保护规则时提示用户

## 智能优化

### 缓存机制

```bash
# 缓存贡献指南（24 小时）
CACHE_DIR="${HOME}/.cache/vft-kit/pr-submit"
mkdir -p "$CACHE_DIR"

repo_cache="${CACHE_DIR}/${owner}_${repo}.json"
if [[ -f "$repo_cache" ]] && [[ $(find "$repo_cache" -mtime -1) ]]; then
  # 使用缓存
  cat "$repo_cache"
else
  # 重新获取
  fetch_contributing_guide > "$repo_cache"
fi
```

### 并行执行

```bash
# 并行获取仓库信息
{
  gh repo view <owner>/<repo> --json defaultBranchRef > /tmp/repo_info.json &
  curl -sL "<contributing_url>" > /tmp/contributing.md &
  git diff --stat > /tmp/diff_stat.txt &
  wait
}
```

## 用户交互

### 明确授权后全自动执行

用户说"提 PR"/"创建 PR" = 已授权，不再询问：
- ✅ 自动创建分支
- ✅ 自动提交改动
- ✅ 自动推送
- ✅ 自动创建 PR

### 仅这些情况停下询问

1. **目标仓库不明确**：
   ```
   检测到 remote 有 origin 和 upstream，请问要提交到哪个仓库？
   1. origin (你的 fork)
   2. upstream (上游仓库)
   ```

2. **改动范围不明确**：
   ```
   检测到改动涉及 3 个子目录，请问要：
   1. 全部一起提一个 PR
   2. 分别提交多个 PR（每个目录一个）
   ```

3. **存在敏感文件**：
   ```
   ⚠️ 检测到 .env 文件未在 .gitignore 中，是否继续提交？
   ```

4. **需要关联 Issue**：
   ```
   检测到仓库有 open issue 与此改动相关：
   #123 - 添加限流部署功能
   是否在 PR 中关联此 Issue？(Closes #123)
   ```

## 正例

```bash
# 场景 1：向开源项目贡献
用户："给 chinese-independent-developer 提 PR，添加我的网站"
→ fork → 分析贡献指南 → 创建分支 feat/add-wflynn-projects
→ 提交 → 推送 → 创建 PR（标题和描述符合项目规范）

# 场景 2：自己仓库的功能分支
用户："把这个新功能提个 PR"
→ 创建分支 feat/throttled-deploy-workflow → 分析改动
→ 生成描述 → 提交 → 推送 → 创建 PR

# 场景 3：子仓库联合提交
用户："blog 和 submodule 都提 PR"
→ 先进 submodule 提 PR（获取 PR 链接）
→ 回父仓库，更新 gitlink，提 PR（描述中关联子仓库 PR）
```

## 反例（禁止）

```bash
# ❌ 直接在 main 分支提交
git checkout main
git commit -m "..."
gh pr create  # 错误：应该先创建新分支

# ❌ 没分析贡献指南就用自己的格式
# 目标仓库要求 "feat: xxx"，结果提交 "[Feature] xxx"

# ❌ Fork 后推送到 upstream
git push upstream feat/xxx  # 错误：应该推送到自己的 fork

# ❌ 子仓库有改动但没先处理
# 直接在父仓库 add -A，gitlink SHA 没更新

# ❌ 敏感文件没检查就提交
git add .env  # 危险：可能包含 secrets
```

## 依赖检查

运行前自动检查并提示安装：

```bash
# GitHub
if ! command -v gh &>/dev/null; then
  echo "❌ 未安装 gh CLI，请运行：brew install gh"
  exit 1
fi

# GitLab
if ! command -v glab &>/dev/null && [[ "$remote_url" == *gitlab* ]]; then
  echo "💡 检测到 GitLab 仓库，建议安装 glab CLI：brew install glab"
fi

# 认证检查
if ! gh auth status &>/dev/null; then
  echo "❌ gh 未登录，请运行：gh auth login"
  exit 1
fi
```

## 配置文件（可选）

`~/.config/vft-kit/pr-submit.json`:

```json
{
  "defaultBase": "main",
  "branchPrefix": {
    "feat": "feature",
    "fix": "fix",
    "docs": "docs"
  },
  "autoLink": {
    "issue": true,
    "submodule": true
  },
  "language": "auto",
  "template": {
    "github": "default",
    "gitlab": "default"
  }
}
```

## 错误处理

```bash
# PR 创建失败 → 给出诊断
if ! gh pr create ...; then
  echo "❌ PR 创建失败，可能原因："
  echo "1. 没有权限（请确认已 fork 并推送到自己的仓库）"
  echo "2. 分支已存在 PR（检查是否重复创建）"
  echo "3. CI 配置错误（查看仓库的 Actions 设置）"
  echo ""
  echo "手动创建链接："
  echo "https://github.com/<owner>/<repo>/compare/<base>...<head>"
fi

# 网络错误 → 重试 3 次
for i in {1..3}; do
  if curl -sf "https://api.github.com/..."; then
    break
  else
    echo "⚠️ 网络请求失败，重试 $i/3..."
    sleep 2
  fi
done
```

## 性能优化

- 贡献指南缓存 24 小时
- 并行执行独立任务（仓库信息、diff 分析、remote 检查）
- 3 秒超时机制（贡献指南下载、改动分析）
- 懒加载：只在需要时才 fork/fetch upstream

## 总结

本 skill 的核心价值：

1. **0 配置使用**：检测环境、自动适配
2. **智能理解意图**：从改动中推断类型、范围、目的
3. **适配目标规范**：读贡献指南、遵循项目风格
4. **全流程自动化**：fork → 分支 → 提交 → PR 一气呵成
5. **安全可靠**：敏感文件检测、分支保护、错误恢复

让开发者专注于代码，PR 提交交给工具。
