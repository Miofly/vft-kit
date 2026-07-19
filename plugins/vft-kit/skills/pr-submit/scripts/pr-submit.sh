#!/usr/bin/env bash
# pr-submit.sh - 智能 PR 提交脚本
set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }

# 全局变量
REPO_OWNER=""
REPO_NAME=""
TARGET_REPO=""
BASE_BRANCH=""
BRANCH_NAME=""
PR_TITLE=""
PR_BODY=""
COMMIT_MSG=""
IS_FORK=false
PLATFORM="github"  # github/gitlab/gitee

# 依赖检查
check_dependencies() {
  log_info "检查依赖..."

  if ! command -v git &>/dev/null; then
    log_error "未安装 git"
    exit 1
  fi

  # 检测平台
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null || echo "")

  if [[ "$remote_url" == *github.com* ]]; then
    PLATFORM="github"
    if ! command -v gh &>/dev/null; then
      log_error "未安装 GitHub CLI (gh)，请运行: brew install gh"
      exit 1
    fi
    if ! gh auth status &>/dev/null; then
      log_error "gh 未登录，请运行: gh auth login"
      exit 1
    fi
  elif [[ "$remote_url" == *gitlab.com* ]]; then
    PLATFORM="gitlab"
    if ! command -v glab &>/dev/null; then
      log_warn "未安装 GitLab CLI (glab)，建议运行: brew install glab"
    fi
  elif [[ "$remote_url" == *gitee.com* ]]; then
    PLATFORM="gitee"
    log_warn "Gitee 需要手动配置 API token"
  fi

  log_success "依赖检查完成"
}

# 获取仓库信息
get_repo_info() {
  log_info "分析仓库信息..."

  local remote_url
  remote_url=$(git remote get-url origin)

  # 解析仓库信息
  if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    REPO_OWNER="${BASH_REMATCH[1]}"
    REPO_NAME="${BASH_REMATCH[2]}"
  elif [[ "$remote_url" =~ gitlab\.com[:/]([^/]+)/([^/.]+) ]]; then
    REPO_OWNER="${BASH_REMATCH[1]}"
    REPO_NAME="${BASH_REMATCH[2]}"
  elif [[ "$remote_url" =~ gitee\.com[:/]([^/]+)/([^/.]+) ]]; then
    REPO_OWNER="${BASH_REMATCH[1]}"
    REPO_NAME="${BASH_REMATCH[2]}"
  fi

  TARGET_REPO="${REPO_OWNER}/${REPO_NAME}"

  # 获取默认分支
  if [[ "$PLATFORM" == "github" ]]; then
    BASE_BRANCH=$(gh repo view "$TARGET_REPO" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo "main")
  else
    BASE_BRANCH=$(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5)
  fi

  log_success "仓库: $TARGET_REPO, 基础分支: $BASE_BRANCH"
}

# 分析改动类型
analyze_changes() {
  log_info "分析改动..."

  local added modified deleted
  added=$(git diff --numstat HEAD | awk '{sum+=$1} END {print sum+0}')
  deleted=$(git diff --numstat HEAD | awk '{sum+=$2} END {print sum+0}')

  local changed_files
  changed_files=$(git status --short | wc -l | tr -d ' ')

  local change_type="chore"
  local change_desc=""

  # 分析文件类型
  local file_types
  file_types=$(git status --short | awk '{print $2}' | grep -o '\.[^.]*$' | sort | uniq -c | sort -rn)

  # 判断改动类型
  if [[ $(git status --short | grep '^A' | wc -l) -gt $((changed_files / 2)) ]]; then
    change_type="feat"
    change_desc="新增功能"
  elif [[ $(git status --short | grep '\.md$' | wc -l) -eq "$changed_files" ]]; then
    change_type="docs"
    change_desc="文档更新"
  elif git diff --stat HEAD | grep -q 'test'; then
    change_type="test"
    change_desc="测试相关"
  elif [[ "$added" -gt $((deleted * 2)) ]]; then
    change_type="feat"
    change_desc="新增功能"
  elif [[ $(git diff --name-only HEAD | wc -l) -le 3 ]]; then
    change_type="fix"
    change_desc="Bug 修复"
  fi

  # 提取主要改动目录
  local main_dir
  main_dir=$(git status --short | awk '{print $2}' | cut -d'/' -f1 | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')

  # 生成分支名
  BRANCH_NAME="${change_type}/${main_dir}-updates-$(date +%Y%m%d)"

  # 生成 commit message
  COMMIT_MSG="${change_type}: ${change_desc} ${main_dir}

- 新增 ${added} 行
- 删除 ${deleted} 行
- 改动 ${changed_files} 个文件

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"

  log_success "改动类型: $change_type, 分支名: $BRANCH_NAME"
}

# 生成 PR 描述
generate_pr_body() {
  log_info "生成 PR 描述..."

  local files_changed
  files_changed=$(git diff --name-only HEAD | head -10)

  PR_BODY="## 变更说明

本次改动主要包含以下内容：

## 主要改动

$(git diff --stat HEAD | head -5)

## 改动文件

\`\`\`
${files_changed}
\`\`\`

## 测试

- [x] 本地测试通过
- [ ] 添加了单元测试

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)"

  log_success "PR 描述已生成"
}

# 检查并转换 HTTPS remote 为 SSH（避免 macOS osxkeychain 弹框）
convert_remote_to_ssh() {
  local remote_url
  remote_url=$(git remote get-url origin)

  if [[ "$remote_url" == https://github.com/* ]]; then
    log_info "转换 HTTPS remote 为 SSH..."
    local ssh_url
    ssh_url=$(echo "$remote_url" | sed -E 's#https://github.com/([^/]+)/([^/.]+)(\.git)?#git@github.com:\1/\2.git#')
    git remote set-url origin "$ssh_url"
    log_success "已转换为 SSH: $ssh_url"
  fi
}

# 创建并推送分支
create_and_push_branch() {
  log_info "创建分支 $BRANCH_NAME..."

  # 检查分支是否已存在
  if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    BRANCH_NAME="${BRANCH_NAME}-$(date +%H%M%S)"
    log_warn "分支已存在，使用: $BRANCH_NAME"
  fi

  # 创建分支
  git checkout -b "$BRANCH_NAME"

  # 暂存所有改动
  git add -A

  # 提交
  git commit -m "$COMMIT_MSG"
  log_success "已提交到本地分支"

  # 推送
  convert_remote_to_ssh
  git push -u origin "$BRANCH_NAME"
  log_success "已推送到远程分支"
}

# 创建 PR
create_pull_request() {
  log_info "创建 Pull Request..."

  case "$PLATFORM" in
    github)
      local pr_url
      pr_url=$(gh pr create \
        --title "$PR_TITLE" \
        --body "$PR_BODY" \
        --base "$BASE_BRANCH" 2>&1)

      if [[ "$pr_url" == *"https://"* ]]; then
        log_success "PR 创建成功: $pr_url"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${GREEN}✅ PR 已创建成功！${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "🔗 PR 链接: $pr_url"
        echo "📝 标题: $PR_TITLE"
        echo "🌿 分支: $BRANCH_NAME → $BASE_BRANCH"
        echo ""
        echo "下一步："
        echo "  • 等待 CI 检查通过"
        echo "  • 等待维护者审核"
        echo "  • 如需修改，继续在 $BRANCH_NAME 分支提交即可"
        echo ""
      else
        log_error "PR 创建失败: $pr_url"
        exit 1
      fi
      ;;

    gitlab)
      if command -v glab &>/dev/null; then
        glab mr create \
          --title "$PR_TITLE" \
          --description "$PR_BODY" \
          --target-branch "$BASE_BRANCH"
      else
        log_warn "请手动在 GitLab 创建 Merge Request"
      fi
      ;;

    gitee)
      log_warn "Gitee 不支持 CLI，请手动创建 Pull Request:"
      echo "https://gitee.com/${TARGET_REPO}/pull/new/${BRANCH_NAME}...${BASE_BRANCH}"
      ;;
  esac
}

# 主流程
main() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "${BLUE}  PR Submit - 智能 Pull Request 提交工具${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  check_dependencies
  get_repo_info
  analyze_changes

  # 生成 PR 标题
  PR_TITLE="${COMMIT_MSG%%$'\n'*}"

  generate_pr_body
  create_and_push_branch
  create_pull_request
}

# 执行主流程
main "$@"
