#!/usr/bin/env bash
# git-pr.sh - git-ops 的 PR 交付子流程：分析改动 → 分支 → 提交 → 推送 → 创建 PR/MR
#
# 用法：git-pr.sh [--base <branch>] [--title <title>] [--draft] [--dry-run]
#   --base     目标分支，默认取远端默认分支
#   --title    PR 标题 / commit 首行，默认按改动自动生成
#   --draft    创建 Draft PR（仅 GitHub/GitLab）
#   --dry-run  只输出分析结果，不改分支、不提交、不推送
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*" >&2; }

TARGET_REPO=""
BASE_BRANCH=""
CURRENT_BRANCH=""
BRANCH_NAME=""
PR_TITLE=""
PR_BODY=""
COMMIT_MSG=""
PLATFORM="unknown"  # github/gitlab/gitee/unknown
DRAFT=false
DRY_RUN=false

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base) BASE_BRANCH="${2:?--base 需要分支名}"; shift 2 ;;
      --title) PR_TITLE="${2:?--title 需要标题}"; shift 2 ;;
      --draft) DRAFT=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
      *) log_error "未知参数: $1"; exit 2 ;;
    esac
  done
}

check_dependencies() {
  log_info "检查依赖..."

  command -v git &>/dev/null || { log_error "未安装 git"; exit 1; }
  git rev-parse --is-inside-work-tree &>/dev/null || { log_error "当前目录不是 git 仓库"; exit 1; }

  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null || echo "")
  [[ -n "$remote_url" ]] || { log_error "缺少 origin remote"; exit 1; }

  case "$remote_url" in
    *github.com*)
      PLATFORM="github"
      command -v gh &>/dev/null || { log_error "未安装 GitHub CLI (gh)，请运行: brew install gh"; exit 1; }
      gh auth status &>/dev/null || { log_error "gh 未登录，请运行: gh auth login"; exit 1; }
      ;;
    *gitlab*)
      PLATFORM="gitlab"
      command -v glab &>/dev/null || log_warn "未安装 GitLab CLI (glab)，将只推送分支"
      ;;
    *gitee.com*)
      PLATFORM="gitee"
      ;;
  esac

  log_success "依赖检查完成 (平台: $PLATFORM)"
}

get_repo_info() {
  log_info "分析仓库信息..."

  local remote_url path
  remote_url=$(git remote get-url origin)
  # 兼容 git@host:owner/repo.git 与 https://host/owner/repo.git，保留仓库名中的点号
  path="${remote_url#*://*/}"
  [[ "$path" == "$remote_url" ]] && path="${remote_url#*:}"
  TARGET_REPO="${path%.git}"

  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

  if [[ -z "$BASE_BRANCH" ]]; then
    if [[ "$PLATFORM" == "github" ]]; then
      BASE_BRANCH=$(gh repo view "$TARGET_REPO" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)
    fi
    if [[ -z "$BASE_BRANCH" ]]; then
      BASE_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
    fi
    BASE_BRANCH="${BASE_BRANCH:-main}"
  fi

  log_success "仓库: $TARGET_REPO, 当前分支: $CURRENT_BRANCH, 目标分支: $BASE_BRANCH"
}

# 敏感文件出现在待提交列表时直接中止，交给用户判断
check_sensitive_files() {
  local hits
  hits=$(git status --porcelain --untracked-files=all | cut -c4- \
    | grep -E '(^|/)(\.env(\..+)?|id_rsa|id_ed25519|credentials\.json)$|\.(pem|key|p12)$' \
    | grep -vE '\.env\.(example|sample|template)$' || true)
  if [[ -n "$hits" ]]; then
    log_error "检测到疑似敏感文件，已中止："
    echo "$hits" >&2
    exit 3
  fi
}

analyze_changes() {
  log_info "分析改动..."

  local status
  status=$(git status --porcelain --untracked-files=all)
  if [[ -z "$status" ]]; then
    log_error "工作区没有改动"
    exit 1
  fi

  local added deleted changed_files new_files md_files
  added=$(git diff --numstat HEAD | awk '{sum+=$1} END {print sum+0}')
  deleted=$(git diff --numstat HEAD | awk '{sum+=$2} END {print sum+0}')
  changed_files=$(echo "$status" | wc -l | tr -d ' ')
  new_files=$(echo "$status" | grep -cE '^(A|\?\?)' || true)
  md_files=$(echo "$status" | grep -c '\.md$' || true)

  local change_type="chore" change_desc="更新"
  if [[ "$new_files" -gt $((changed_files * 6 / 10)) ]]; then
    change_type="feat"; change_desc="新增"
  elif [[ "$md_files" -eq "$changed_files" ]]; then
    change_type="docs"; change_desc="文档更新"
  elif echo "$status" | grep -qE '(test|spec)'; then
    change_type="test"; change_desc="测试相关"
  elif echo "$status" | grep -qE '(package\.json|\.github/|\.ya?ml$|\.config\.)'; then
    change_type="chore"; change_desc="配置调整"
  elif [[ "$added" -gt $((deleted * 2)) ]]; then
    change_type="feat"; change_desc="新增"
  elif [[ "$changed_files" -le 3 ]]; then
    change_type="fix"; change_desc="修复"
  fi

  local main_dir
  main_dir=$(echo "$status" | cut -c4- | sed 's#.* -> ##' | cut -d'/' -f1 | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
  main_dir="${main_dir%.*}"
  main_dir=$(echo "${main_dir:-repo}" | tr -c 'A-Za-z0-9._\n-' '-')

  # 已在功能分支上就沿用，只有在目标分支/主干上才新建
  if [[ "$CURRENT_BRANCH" == "$BASE_BRANCH" || "$CURRENT_BRANCH" =~ ^(main|master)$ ]]; then
    BRANCH_NAME="${change_type}/${main_dir}-updates-$(date +%Y%m%d)"
    if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
      BRANCH_NAME="${BRANCH_NAME}-$(date +%H%M%S)"
    fi
  else
    BRANCH_NAME="$CURRENT_BRANCH"
  fi

  PR_TITLE="${PR_TITLE:-${change_type}: ${change_desc} ${main_dir}}"
  COMMIT_MSG="${PR_TITLE}

- 新增 ${added} 行
- 删除 ${deleted} 行
- 改动 ${changed_files} 个文件"

  log_success "改动类型: $change_type, 分支: $BRANCH_NAME"
}

generate_pr_body() {
  PR_BODY="## 变更说明

${PR_TITLE}

## 主要改动

\`\`\`
$(git diff --stat HEAD | tail -1)
\`\`\`

## 改动文件

\`\`\`
$(git status --porcelain --untracked-files=all | cut -c4- | head -20)
\`\`\`

## 测试

- [ ] 本地测试通过
"
}

# macOS 上 GitHub HTTPS push 会卡 osxkeychain 弹框；只转 GitHub，Gitee 本机无 SSH key 不转
convert_remote_to_ssh() {
  local remote_url
  remote_url=$(git remote get-url origin)
  if [[ "$remote_url" == https://github.com/* ]]; then
    local ssh_url="git@github.com:${remote_url#https://github.com/}"
    ssh_url="${ssh_url%.git}.git"
    git remote set-url origin "$ssh_url"
    log_success "origin 已转为 SSH: $ssh_url"
  fi
}

commit_and_push() {
  if [[ "$BRANCH_NAME" != "$CURRENT_BRANCH" ]]; then
    log_info "创建分支 $BRANCH_NAME..."
    git checkout -b "$BRANCH_NAME"
  fi

  git add -A
  git commit -m "$COMMIT_MSG"
  log_success "已提交到本地分支"

  convert_remote_to_ssh
  git push -u origin "$BRANCH_NAME"
  log_success "已推送到 origin/$BRANCH_NAME"
}

create_pull_request() {
  log_info "创建 PR..."
  local pr_url=""

  case "$PLATFORM" in
    github)
      local args=(--title "$PR_TITLE" --body "$PR_BODY" --base "$BASE_BRANCH" --head "$BRANCH_NAME")
      $DRAFT && args+=(--draft)
      pr_url=$(gh pr create "${args[@]}" 2>&1) || { log_error "PR 创建失败: $pr_url"; exit 1; }
      ;;
    gitlab)
      if command -v glab &>/dev/null; then
        local args=(--title "$PR_TITLE" --description "$PR_BODY" --target-branch "$BASE_BRANCH" --source-branch "$BRANCH_NAME" --yes)
        $DRAFT && args+=(--draft)
        pr_url=$(glab mr create "${args[@]}" 2>&1) || { log_error "MR 创建失败: $pr_url"; exit 1; }
      else
        log_warn "请手动在 GitLab 创建 Merge Request"
      fi
      ;;
    gitee)
      pr_url="https://gitee.com/${TARGET_REPO}/compare/${BASE_BRANCH}...${BRANCH_NAME}"
      log_warn "Gitee 无 CLI，请打开链接手动创建 PR"
      ;;
    *)
      log_warn "未知托管平台，分支已推送，请手动创建 PR"
      ;;
  esac

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  [[ -n "$pr_url" ]] && echo "🔗 PR: $(echo "$pr_url" | grep -Eo 'https://[^ ]+' | tail -1)"
  echo "📝 标题: $PR_TITLE"
  echo "🌿 分支: $BRANCH_NAME → $BASE_BRANCH"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main() {
  parse_args "$@"
  check_dependencies
  get_repo_info
  check_sensitive_files
  analyze_changes
  generate_pr_body

  if $DRY_RUN; then
    echo ""
    echo "[dry-run] 分支: $BRANCH_NAME → $BASE_BRANCH"
    echo "[dry-run] commit message:"
    echo "$COMMIT_MSG"
    echo ""
    echo "[dry-run] PR 描述:"
    echo "$PR_BODY"
    exit 0
  fi

  commit_and_push
  create_pull_request
}

main "$@"
