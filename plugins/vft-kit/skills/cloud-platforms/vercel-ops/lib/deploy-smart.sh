#!/usr/bin/env bash
# Vercel Ops - 智能部署决策
# 根据情况自动选择最佳部署方式

# 加载依赖
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/deploy-methods.sh"

# ============================================================================
# 智能部署主函数
# ============================================================================

# 智能选择部署方式
# 决策逻辑：
#   1. 检查 token 是否有效
#      - 无效 → 使用 CLI
#   2. 是否指定了 ref？
#      - 是 → 使用 API（支持指定 ref）
#      - 否 → 优先 Deploy Hook（最快）→ fallback API → fallback CLI
#
# 参数：
#   $1 - project_id: 项目 ID (prj_xxx)
#   $2 - hook_url: Deploy Hook URL（可选）
#   $3 - project_dir: 项目目录（用于 CLI fallback）
#   $4 - target: 部署目标 (production/preview，默认 production)
#   $5 - ref: Git ref（可选）
# 返回：
#   0 - 成功
#   1 - 失败
deploy_smart() {
  local project_id="$1"
  local hook_url="$2"
  local project_dir="$3"
  local target="${4:-production}"
  local ref="${5:-}"

  # ========================================================================
  # Step 1: 检查 token 是否有效
  # ========================================================================

  local has_valid_token=false
  if [ -n "$VERCEL_TOKEN" ]; then
    log_info "验证 token..."
    if verify_token; then
      log_success "Token 验证成功"
      has_valid_token=true
    else
      log_warn "Token 验证失败 - 将使用 Vercel CLI"
    fi
  fi

  # 如果没有有效 token，直接使用 CLI
  if [ "$has_valid_token" = false ]; then
    log_warn "没有有效的 API token，切换到 Vercel CLI 部署"
    deploy_via_cli "$project_dir" "$target" "$ref"
    return $?
  fi

  # ========================================================================
  # Step 2: 如果指定了 ref，必须使用 API
  # ========================================================================

  if [ -n "$ref" ]; then
    log_info "指定了 ref: $ref，使用 API 方式"
    deploy_via_api "$project_id" "$target" "$ref"
    return $?
  fi

  # ========================================================================
  # Step 3: 默认策略 - Deploy Hook → API → CLI
  # ========================================================================

  # 3.1 尝试 Deploy Hook（最快）
  if [ -n "$hook_url" ]; then
    if deploy_via_hook "$hook_url"; then
      return 0
    else
      log_warn "Deploy Hook 失败，尝试 API 方式..."
    fi
  fi

  # 3.2 尝试 Git API
  if deploy_via_api "$project_id" "$target"; then
    return 0
  else
    log_warn "API 方式失败，尝试 Vercel CLI..."
  fi

  # 3.3 最后的 fallback - Vercel CLI
  deploy_via_cli "$project_dir" "$target"
  return $?
}

# ============================================================================
# 简化接口 - 只需要项目 ID
# ============================================================================

# 快速部署（只使用 API，不 fallback CLI）
# 适用于 CI/CD 环境
# 参数：
#   $1 - project_id: 项目 ID
#   $2 - target: 部署目标（默认 production）
#   $3 - ref: Git ref（可选）
# 返回：
#   0 - 成功
#   1 - 失败
deploy_fast() {
  local project_id="$1"
  local target="${2:-production}"
  local ref="${3:-}"

  if [ -z "$VERCEL_TOKEN" ]; then
    log_error "VERCEL_TOKEN is required for fast deploy"
    return 1
  fi

  if ! verify_token; then
    log_error "Token validation failed"
    return 1
  fi

  deploy_via_api "$project_id" "$target" "$ref"
}

# ============================================================================
# 批量部署
# ============================================================================

# 批量部署多个项目
# 参数：
#   $@ - project_ids: 项目 ID 列表
# 环境变量：
#   DEPLOY_TARGET - 部署目标（默认 production）
#   DEPLOY_REF - Git ref（可选）
# 返回：
#   0 - 全部成功
#   1 - 部分或全部失败
deploy_batch() {
  local target="${DEPLOY_TARGET:-production}"
  local ref="${DEPLOY_REF:-}"
  local failed_projects=()

  log_info "批量部署 ${#@} 个项目到 $target"
  echo ""

  for project_id in "$@"; do
    log_info "部署 $project_id..."
    if deploy_fast "$project_id" "$target" "$ref"; then
      log_success "✓ $project_id 部署成功"
    else
      log_error "✗ $project_id 部署失败"
      failed_projects+=("$project_id")
    fi
    echo ""
  done

  if [ ${#failed_projects[@]} -eq 0 ]; then
    log_success "全部部署成功！"
    return 0
  else
    log_error "以下项目部署失败："
    for project in "${failed_projects[@]}"; do
      echo "  - $project"
    done
    return 1
  fi
}
