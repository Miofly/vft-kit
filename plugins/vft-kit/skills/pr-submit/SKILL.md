---
name: pr-submit
description: 智能 PR 提交工具。自动分析改动、生成 PR 描述、创建分支、提交并创建 Pull Request。支持 GitHub/GitLab/Gitee，可分析目标仓库贡献指南自动适配格式。用户说"提 PR"、"创建 PR"、"submit PR"、"发起 pull request"、"给 xxx 提交代码"等场景时触发。
---

# PR Submit - 智能 Pull Request 提交工具

全自动分析改动、生成高质量 PR 描述、创建并提交 Pull Request。

## 使用方式

用户说"提 PR" / "创建 PR" / "给 xxx 项目提 PR" 时，调用本 skill 内嵌的 `scripts/pr-submit.sh` 脚本。

```bash
bash "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/pr-submit/scripts/pr-submit.sh"
```

## 核心能力

1. **智能改动分析** - 自动识别改动类型（feat/fix/docs/chore）和影响范围
2. **自动生成 PR 描述** - 基于 git diff 生成结构化、高质量的 PR 描述
3. **多平台支持** - GitHub (`gh`)、GitLab (`glab`)、Gitee
4. **智能分支管理** - 自动创建规范分支名、处理冲突
5. **安全特性** - 敏感文件检测、HTTPS→SSH 转换（避免 macOS 弹框）
6. **全自动执行** - 一条命令完成：分析 → 分支 → 提交 → 推送 → 创建 PR

## 适用场景

### 1. 向开源项目提交贡献

```
用户："给 chinese-independent-developer 这个项目提 PR，添加我的网站"

自动执行：
- 分析当前仓库和改动
- 创建规范分支（如 feat/add-wflynn-projects）
- 提交改动并生成描述
- 推送到远程
- 创建 PR 到目标仓库
```

### 2. 自己仓库的功能分支

```
用户："提个 PR 到 master"

自动执行：
- 检测改动类型（feat/fix/docs/chore）
- 创建 feature 分支
- 分析改动并生成 commit message
- 推送并创建 PR
```

### 3. Bug 修复提交

```
用户："修复完了，提 PR"

自动识别：
- 改动类型：fix
- 分支名：fix/xxx-20260719
- 包含改动统计的 PR 描述
```

## 改动类型识别规则

脚本会根据以下规则自动识别改动类型：

| 改动特征 | 识别为 | 分支前缀 |
|---------|-------|---------|
| 新增文件占比 > 60% | `feat` | `feat/` |
| 只改 `.md` 文件 | `docs` | `docs/` |
| 改动包含测试文件 | `test` | `test/` |
| 少量文件修改（≤3 个） | `fix` | `fix/` |
| 改配置/package.json/CI | `chore` | `chore/` |
| 新增行数 > 删除行数 * 2 | `feat` | `feat/` |
| 其他情况 | `chore` | `chore/` |

## 执行流程

```
1. 检查依赖（git, gh, glab）
   ↓
2. 分析仓库信息（owner/repo/base_branch）
   ↓
3. 分析改动类型和范围
   ↓
4. 生成分支名（type/description-YYYYMMDD）
   ↓
5. 生成 commit message（包含改动统计）
   ↓
6. 生成 PR 描述（变更说明、文件列表、测试清单）
   ↓
7. 创建并切换到新分支
   ↓
8. 暂存并提交改动（git add -A）
   ↓
9. 转换 HTTPS → SSH（macOS，避免 osxkeychain 弹框）
   ↓
10. 推送到远程
   ↓
11. 创建 Pull Request（gh/glab/gitee API）
   ↓
12. 输出 PR 链接和后续步骤
```

## 安全特性

### 1. HTTPS → SSH 自动转换（macOS）

macOS 上 HTTPS remote push 会触发 `git-credential-osxkeychain` 弹框并卡死进程。脚本会自动检测并转换：

```bash
# 检测到 https://github.com/... 
# 自动转换为 git@github.com:...
```

**仅对 GitHub 自动转换**，其他平台保持原样。

### 2. 敏感文件检测（TODO）

检测到以下文件时会停下警告：
- `.env*` 包含 secrets
- `*.pem` / `*.key` 私钥
- `credentials.json` 凭证文件

### 3. 分支保护

- ✅ 总是创建新分支，绝不直接在 main/master 提交
- ✅ 分支名冲突时自动追加时间戳
- ✅ 绝不自动 force push

## 生成的内容

### Commit Message

```
<type>: <description>

- 新增 <added> 行
- 删除 <deleted> 行
- 改动 <changed> 个文件

```

### PR 描述

```markdown
## 变更说明

本次改动主要包含以下内容：

## 主要改动

<git diff --stat 前 5 行>

## 改动文件

```
<改动的文件列表>
```

## 测试

- [x] 本地测试通过
- [ ] 添加了单元测试

```

### PR 标题

从 commit message 的第一行提取（不包含多行描述）。

## 依赖要求

### 必需
- `git` - Git 版本控制
- `gh` - GitHub CLI（用于 GitHub 仓库）

### 可选
- `glab` - GitLab CLI（用于 GitLab 仓库）
- Gitee API token（用于 Gitee 仓库）

### 安装

```bash
# macOS
brew install gh glab

# 登录 GitHub
gh auth login

# 登录 GitLab（可选）
glab auth login
```

## 输出示例

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PR Submit - 智能 Pull Request 提交工具
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ 检查依赖...
✓ 依赖检查完成
ℹ 分析仓库信息...
✓ 仓库: wfly/blog, 基础分支: master
ℹ 分析改动...
✓ 改动类型: feat, 分支名: feat/workflows-updates-20260719
ℹ 生成 PR 描述...
✓ PR 描述已生成
ℹ 创建分支 feat/workflows-updates-20260719...
✓ 已提交到本地分支
✓ 已推送到远程分支
ℹ 创建 Pull Request...
✓ PR 创建成功

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ PR 已创建成功！
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔗 PR 链接: https://github.com/wfly/blog/pull/1
📝 标题: feat: 添加限流部署工作流
🌿 分支: feat/workflows-updates-20260719 → master

下一步：
  • 等待 CI 检查通过
  • 等待维护者审核
  • 如需修改，继续在 feat/workflows-updates-20260719 分支提交即可
```

## 故障排除

### gh 命令找不到

```bash
brew install gh
gh auth login
```

### 推送失败（权限问题）

确保你有仓库的写权限，或已经 fork 了目标仓库。

### osxkeychain 弹框

脚本会自动转换 HTTPS → SSH。如果还是弹框，配置 GitHub SSH：

```bash
# 生成 SSH key
ssh-keygen -t ed25519 -C "your_email@example.com"

# 添加到 GitHub
# Settings → SSH and GPG keys → New SSH key
```

### PR 创建失败

常见原因：
1. **分支已存在 PR** - 检查是否重复创建
2. **没有权限** - 确认 fork 状态和推送权限
3. **CI 配置错误** - 查看仓库的 Actions 设置

## 使用限制

- **不会自动 fork** - 需要用户提前 fork 目标仓库
- **不会读取贡献指南** - 使用统一格式，不适配特定项目规范
- **不会关联 Issue** - 需要手动在 PR 描述中添加
- **不支持 Draft PR** - 总是创建正式 PR

## 与其他 Skills 的关系

- **git-auto-push** - 绕过 hooks 的快速提交（不创建 PR，不创建分支）
- **pr-submit**（本 skill）- 完整的 PR 工作流（分析 → 分支 → PR）

两者互补，覆盖不同使用场景。

## 实现细节

- 脚本位置：`scripts/pr-submit.sh`
- 语言：Bash
- 行数：约 400 行
- 依赖：git、gh（必需），glab（可选）

## 后续优化方向

- [ ] 自动 fork 检测和处理
- [ ] 读取并适配目标仓库的 CONTRIBUTING.md
- [ ] 自动关联相关 Issue
- [ ] 支持 Draft PR
- [ ] 批量 PR（monorepo 场景）
- [ ] 子仓库联合提交
- [ ] PR 模板自动填充
- [ ] CI 状态实时监控

## 许可

MIT
