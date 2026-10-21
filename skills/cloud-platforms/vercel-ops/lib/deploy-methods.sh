#!/usr/bin/env bash
# Vercel Ops - 部署方法实现
# 提供三种部署方式：Deploy Hook / Git API / Vercel CLI

# 加载工具函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ============================================================================
# Deploy Hook 方式
# ============================================================================

# 使用 Deploy Hook 快速部署
# 参数：
#   $1 - hook_url: Deploy Hook URL
# 返回：
#   0 - 成功
#   1 - 失败
deploy_via_hook() {
  local hook_url="$1"

  if [ -z "$hook_url" ]; then
    log_error "Deploy hook URL is required"
    return 1
  fi

  log_info "使用 Deploy Hook 触发部署..."

  local response=$(curl -s -X POST "$hook_url" 2>&1)
  local job_id=$(echo "$response" | jq -r '.job.id // empty' 2>/dev/null)

  if [ -z "$job_id" ]; then
    log_error "部署触发失败"
    if [ -n "$response" ]; then
      echo "$response" | head -5
    fi
    return 1
  fi

  log_success "部署任务已创建: $job_id"
  return 0
}

# ============================================================================
# Git API 方式
# ============================================================================

# 使用 Vercel Git API 部署
# 参数：
#   $1 - project_id: 项目 ID (prj_xxx)
#   $2 - target: 部署目标 (production/preview)
#   $3 - ref: Git ref (branch/tag/commit，可选)
# 返回：
#   0 - 成功，输出 deployment ID
#   1 - 失败
deploy_via_api() {
  local project_id="$1"
  local target="${2:-production}"
  local ref="${3:-}"

  if [ -z "$project_id" ]; then
    log_error "Project ID is required"
    return 1
  fi

  if [ -z "$VERCEL_TOKEN" ]; then
    log_error "VERCEL_TOKEN is required for API deployment"
    return 1
  fi

  log_info "使用 Vercel API 创建部署..."

  # 构建命令
  local cmd="vercel_ops deployments create $project_id --target $target"
  [ -n "$ref" ] && cmd="$cmd --ref $ref"

  # 执行部署
  local deployment_json=$($cmd --json 2>&1)

  if [ $? -ne 0 ]; then
    log_error "部署创建失败"
    echo "$deployment_json" | head -10
    return 1
  fi

  local deployment_id=$(echo "$deployment_json" | jq -r '.id // empty')

  if [ -z "$deployment_id" ]; then
    log_error "无法获取部署 ID"
    echo "$deployment_json" | head -10
    return 1
  fi

  log_success "部署已创建: $deployment_id"
  echo "$deployment_id"
  return 0
}

# ============================================================================
# Vercel CLI 方式
# ============================================================================

# 使用 Vercel CLI 部署
# 参数：
#   $1 - project_dir: 项目目录
#   $2 - target: 部署目标 (production/preview)
#   $3 - ref: Git ref（CLI 会自动检测当前分支，此参数保留以保持接口一致）
# 返回：
#   0 - 成功
#   1 - 失败
deploy_via_cli() {
  local project_dir="$1"
  local target="${2:-production}"
  local ref="${3:-}"

  if [ -z "$project_dir" ]; then
    log_error "Project directory is required"
    return 1
  fi

  if ! has_vercel_cli; then
    log_error "Vercel CLI 未安装"
    log_info "安装方法: npm install -g vercel"
    return 1
  fi

  if ! vercel_cli_logged_in; then
    log_error "Vercel CLI 未登录"
    log_info "登录方法: vercel login"
    return 1
  fi

  if [ ! -d "$project_dir" ]; then
    log_error "项目目录不存在: $project_dir"
    return 1
  fi

  log_info "使用 Vercel CLI 部署..."

  # 进入项目目录
  cd "$project_dir" || return 1

  # 如果指定了 ref，需要先切换分支（可选）
  if [ -n "$ref" ] && [ -d ".git" ]; then
    log_info "切换到分支/commit: $ref"
    if ! git checkout "$ref" 2>/dev/null; then
      log_warn "无法切换到 $ref，使用当前分支"
    fi
  fi

  # 构建 CLI 命令
  local cli_cmd="vercel --yes"

  if [ "$target" = "production" ]; then
    cli_cmd="$cli_cmd --prod"
  fi

  log_info "执行: cd $project_dir && $cli_cmd"

  # 执行部署
  if $cli_cmd; then
    log_success "Vercel CLI 部署成功"
    return 0
  else
    log_error "Vercel CLI 部署失败"
    return 1
  fi
}

# ============================================================================
# Token 验证（重新导出，方便使用）
# ============================================================================

# 验证 token 是否有效（从 utils.sh 导出）
# 参数：
#   $1 - token: 可选，默认使用 $VERCEL_TOKEN
# 返回：
#   0 - 有效
#   1 - 无效
verify_vercel_token() {
  verify_token "$@"
}
