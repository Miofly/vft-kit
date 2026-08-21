#!/usr/bin/env bash
# Vercel Ops - 通用工具函数
# 可被任何 Vercel 项目复用

# ============================================================================
# 颜色定义
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# 日志函数
# ============================================================================

log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✅${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}⚠️${NC} $1"
}

log_warn() {
  log_warning "$1"
}

log_error() {
  echo -e "${RED}❌${NC} $1"
}

# ============================================================================
# Token 管理
# ============================================================================

# 从环境变量加载 token
load_token_from_env() {
  if [ -n "$VERCEL_TOKEN" ]; then
    return 0
  fi
  return 1
}

# 从配置文件加载 token
load_token_from_file() {
  local config_file="$1"

  if [ ! -f "$config_file" ]; then
    return 1
  fi

  if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed"
    return 1
  fi

  local token=$(jq -r '.access_token' "$config_file" 2>/dev/null)

  if [ -z "$token" ] || [ "$token" = "null" ]; then
    return 1
  fi

  export VERCEL_TOKEN="$token"
  return 0
}

# 尝试多种方式加载 token
load_token() {
  local config_file="${1:-}"

  # 1. 尝试从环境变量
  if load_token_from_env; then
    return 0
  fi

  # 2. 尝试从配置文件
  if [ -n "$config_file" ]; then
    if load_token_from_file "$config_file"; then
      return 0
    fi
  fi

  # 3. 尝试默认位置
  local default_configs=(
    "$HOME/.secrets/vercel/config.json"
    "$HOME/.vercel/auth.json"
  )

  for config in "${default_configs[@]}"; do
    if load_token_from_file "$config"; then
      return 0
    fi
  done

  return 1
}

# 验证 token 是否有效
verify_token() {
  local token="${1:-$VERCEL_TOKEN}"

  if [ -z "$token" ]; then
    return 1
  fi

  local response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $token" \
    "https://api.vercel.com/v2/user" 2>&1)

  local http_code=$(echo "$response" | tail -n1)

  if [ "$http_code" = "200" ]; then
    return 0
  else
    return 1
  fi
}

# ============================================================================
# CLI 检查
# ============================================================================

# 检查是否安装了 Vercel CLI
has_vercel_cli() {
  command -v vercel &> /dev/null
}

# 检查 CLI 是否已登录
vercel_cli_logged_in() {
  if ! has_vercel_cli; then
    return 1
  fi

  vercel whoami &> /dev/null
  return $?
}

# ============================================================================
# 依赖检查
# ============================================================================

check_dependencies() {
  local missing_deps=()

  if ! command -v node &> /dev/null; then
    missing_deps+=("node")
  fi

  if ! command -v jq &> /dev/null; then
    missing_deps+=("jq")
  fi

  if ! command -v curl &> /dev/null; then
    missing_deps+=("curl")
  fi

  if [ ${#missing_deps[@]} -gt 0 ]; then
    log_error "Missing dependencies: ${missing_deps[*]}"
    log_info "Install with: brew install ${missing_deps[*]}"
    return 1
  fi

  return 0
}

# ============================================================================
# vercel-ops.js 封装
# ============================================================================

# 获取 vercel-ops.js 的路径
get_vercel_ops_script() {
  # 尝试几个可能的位置
  local candidates=(
    "$(dirname "${BASH_SOURCE[0]}")/../scripts/vercel-ops.js"
    "/Users/wfly/Documents/code/wfly/bolierplate/project/vft-kit/plugins/vft-kit/skills/cloud-platforms/vercel-ops/scripts/vercel-ops.js"
  )

  for path in "${candidates[@]}"; do
    if [ -f "$path" ]; then
      echo "$path"
      return 0
    fi
  done

  return 1
}

# 调用 vercel-ops.js
vercel_ops() {
  local script=$(get_vercel_ops_script)

  if [ -z "$script" ]; then
    log_error "vercel-ops.js not found"
    return 1
  fi

  node "$script" "$@"
}
