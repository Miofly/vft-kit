#!/usr/bin/env bash

# Claude / Claude Code cleaner for macOS, Linux, and WSL.
# This script is interactive and intentionally shows every destructive action
# before it runs. It does not scan project folders recursively.

set -u

BACKUP_PREFIX="claudebackup"
QUIET_COPY=1

is_wsl() {
  grep -qiE "microsoft|wsl" /proc/version 2>/dev/null
}

is_macos() {
  [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]
}

line() {
  printf '+------------------------------------------------------------+\n'
}

title() {
  printf '\n'
  line
  printf '| %-58s |\n' "$1"
  line
}

step_header() {
  local step="$1"
  local total="$2"
  local text="$3"
  printf '\n+-- 步骤 %s/%s：%s ' "$step" "$total" "$text"
  printf '%*s\n' $((58 - ${#text})) '' | tr ' ' '-'
}

step_footer() {
  line
}

result() {
  local level="$1"
  local text="$2"
  case "$level" in
    ok) printf '  \033[32m[OK]\033[0m %s\n' "$text" ;;
    warn) printf '  \033[33m[WARN]\033[0m %s\n' "$text" ;;
    fail) printf '  \033[31m[FAIL]\033[0m %s\n' "$text" ;;
    *) printf '  [..] %s\n' "$text" ;;
  esac
}

confirm_yes() {
  local prompt="${1:-输入 Y 确认继续，其他任意键取消}"
  local answer
  read -r -p "$prompt: " answer
  [[ "$answer" == "Y" || "$answer" == "y" ]]
}

read_dir() {
  local prompt="$1"
  local input
  printf '\n%s\n' "$prompt"
  printf '请手动输入目录路径，可直接粘贴路径；留空表示取消。\n'
  read -r -p "请输入目录路径: " input
  [[ -z "$input" ]] && return 1
  input="${input/#\~/$HOME}"
  if [[ ! -d "$input" ]]; then
    printf '\033[31m目录不存在：%s\033[0m\n' "$input"
    return 1
  fi
  printf '%s\n' "$input"
}

format_bytes() {
  local bytes="${1:-0}"
  awk -v b="$bytes" 'BEGIN {
    if (b >= 1073741824) printf "%.2f GB", b/1073741824;
    else if (b >= 1048576) printf "%.2f MB", b/1048576;
    else if (b >= 1024) printf "%.2f KB", b/1024;
    else printf "%d B", b;
  }'
}

path_size_bytes() {
  local total=0
  local path
  for path in "$@"; do
    [[ -e "$path" ]] || continue
    while IFS= read -r -d '' file; do
      local size
      size=$(wc -c < "$file" 2>/dev/null || printf '0')
      total=$((total + size))
    done < <(find "$path" -type f -print0 2>/dev/null)
    if [[ -f "$path" ]]; then
      local size
      size=$(wc -c < "$path" 2>/dev/null || printf '0')
      total=$((total + size))
    fi
  done
  printf '%s\n' "$total"
}

file_count() {
  local count=0
  local path
  for path in "$@"; do
    [[ -e "$path" ]] || continue
    if [[ -f "$path" ]]; then
      count=$((count + 1))
    else
      local c
      c=$(find "$path" -type f 2>/dev/null | wc -l | tr -d ' ')
      count=$((count + c))
    fi
  done
  printf '%s\n' "$count"
}

copy_path() {
  local src="$1"
  local dst="$2"
  [[ -e "$src" ]] || return 1
  mkdir -p "$(dirname "$dst")"
  if [[ -d "$src" ]]; then
    mkdir -p "$dst"
    cp -R "$src"/. "$dst"/ 2>/dev/null
  else
    cp -f "$src" "$dst" 2>/dev/null
  fi
}

backup_items() {
  shopt -s nullglob
  for f in "$HOME"/.claude/*.jsonl; do printf '%s\t%s\n' "$f" ".claude/$(basename "$f")"; done
  printf '%s\t%s\n' "$HOME/.claude/projects" ".claude/projects"
  printf '%s\t%s\n' "$HOME/.claude/settings.json" ".claude/settings.json"
  printf '%s\t%s\n' "$HOME/.claude/CLAUDE.md" ".claude/CLAUDE.md"
  printf '%s\t%s\n' "$HOME/.claude/commands" ".claude/commands"
  printf '%s\t%s\n' "$HOME/.claude/agents" ".claude/agents"
  printf '%s\t%s\n' "$HOME/.claude/hooks" ".claude/hooks"
  printf '%s\t%s\n' "$HOME/.claude/skills" ".claude/skills"
  printf '%s\t%s\n' "$HOME/.claude/mcp" ".claude/mcp"
  printf '%s\t%s\n' "$HOME/.claude.json" ".claude.json"
  printf '%s\t%s\n' "$HOME/.config/Claude" ".config/Claude"
  printf '%s\t%s\n' "$HOME/.config/claude" ".config/claude"
  printf '%s\t%s\n' "$HOME/.config/claude-code" ".config/claude-code"
  if is_macos; then
    printf '%s\t%s\n' "$HOME/Library/Application Support/Claude" "Library/Application Support/Claude"
    printf '%s\t%s\n' "$HOME/Library/Application Support/claude-code" "Library/Application Support/claude-code"
  fi
}

invoke_backup() {
  title "备份 Claude / Claude Code"
  printf '备份会保存关键数据，并按原始目录结构放置。\n'
  printf '注意：备份可能包含 token、API key、MCP、hooks、skills 和本地路径。\n'

  local root
  root=$(read_dir "请选择备份保存目录") || return
  local backup_dir="$root/${BACKUP_PREFIX}_$(date +%Y%m%d_%H%M)"
  if [[ -e "$backup_dir" ]]; then
    result warn "备份目录已存在：$backup_dir"
    confirm_yes "输入 Y 使用这个目录并可能覆盖同名文件" || return
  fi
  mkdir -p "$backup_dir"

  local sources=()
  while IFS=$'\t' read -r src rel; do
    [[ -e "$src" ]] && sources+=("$src")
  done < <(backup_items)

  local total_files total_bytes copied_files copied_bytes
  total_files=$(file_count "${sources[@]}")
  total_bytes=$(path_size_bytes "${sources[@]}")
  printf '\n待备份：%s 个文件，约 %s\n' "$total_files" "$(format_bytes "$total_bytes")"

  copied_files=0
  copied_bytes=0
  while IFS=$'\t' read -r src rel; do
    [[ -e "$src" ]] || continue
    printf '正在备份：%s\n' "$rel"
    copy_path "$src" "$backup_dir/$rel"
  done < <(backup_items)

  copied_files=$(file_count "$backup_dir")
  copied_bytes=$(path_size_bytes "$backup_dir")
  cat > "$backup_dir/backup_meta.json" <<EOF
{
  "createdAt": "$(date -Iseconds)",
  "mode": "selected_with_original_layout",
  "platform": "$(uname -a | sed 's/"/\\"/g')",
  "isWsl": "$(is_wsl && printf true || printf false)",
  "fileCount": $copied_files,
  "bytes": $copied_bytes
}
EOF
  result ok "备份完成：$backup_dir"
  result ok "结果：已复制 $copied_files 个文件，约 $(format_bytes "$copied_bytes")"
}

clean_targets() {
  shopt -s nullglob
  local targets=(
    "$HOME/.claude"
    "$HOME/.claude.json"
    "$HOME/.claude-code"
    "$HOME/.config/Claude"
    "$HOME/.config/claude"
    "$HOME/.config/claude-code"
    "$HOME/.cache/claude"
    "$HOME/.cache/claude-code"
    "$HOME/.local/share/claude"
    "$HOME/.local/share/claude-code"
    "$HOME/.local/bin/claude"
    "$HOME/.local/bin/claude-code"
    "$HOME/.vscode/extensions/anthropic.claude-code"*
    "$HOME/.vscode-server/data/User/globalStorage/"*anthropic*
    "$HOME/.vscode-server/data/User/workspaceStorage/"*anthropic*
  )
  if is_macos; then
    targets+=(
      "$HOME/Library/Application Support/Claude"
      "$HOME/Library/Application Support/claude-code"
      "$HOME/Library/Caches/Claude"
      "$HOME/Library/Caches/claude-code"
      "$HOME/Library/LaunchAgents/ai.anthropic.claude.plist"
    )
  fi
  printf '%s\n' "${targets[@]}"
}

claude_commands() {
  command -v -a claude 2>/dev/null || true
  command -v -a claude-code 2>/dev/null || true
}

stop_processes() {
  pkill -f "claude" 2>/dev/null || true
  pkill -f "claude-code" 2>/dev/null || true
}

remove_commands() {
  local removed=0
  while IFS= read -r cmd_path; do
    [[ -n "$cmd_path" && -e "$cmd_path" ]] || continue
    case "$cmd_path" in
      "$HOME"/*|/usr/local/bin/claude*|/opt/homebrew/bin/claude*)
        rm -f "$cmd_path" 2>/dev/null || sudo rm -f "$cmd_path" 2>/dev/null || true
        [[ ! -e "$cmd_path" ]] && removed=$((removed + 1))
        ;;
    esac
  done < <(claude_commands | sort -u)
  printf '%s\n' "$removed"
}

remove_env_lines() {
  local files=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile")
  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  local changed=0
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    if grep -Eq 'ANTHROPIC_|CLAUDE_|CLAUDE_HOME|MCP_DEBUG' "$f"; then
      cp "$f" "$f.claude-cleaner.bak.$ts" 2>/dev/null || true
      sed -i.bak '/ANTHROPIC_/d;/CLAUDE_/d;/CLAUDE_HOME/d;/MCP_DEBUG/d' "$f" 2>/dev/null || true
      changed=$((changed + 1))
    fi
  done
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_HOME MCP_DEBUG
  printf '%s\n' "$changed"
}

uninstall_packages() {
  if command -v brew >/dev/null 2>&1; then
    brew uninstall --cask claude-code claude-code@latest 2>/dev/null || true
  fi
  if command -v npm >/dev/null 2>&1; then
    npm uninstall -g @anthropic-ai/claude-code @anthropic-ai/ralph-claude >/dev/null 2>&1 || true
  fi
  if command -v apt >/dev/null 2>&1; then
    sudo apt remove -y claude-code claude 2>/dev/null || true
  fi
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf remove -y claude-code claude 2>/dev/null || true
  fi
  if command -v apk >/dev/null 2>&1; then
    sudo apk del claude-code claude 2>/dev/null || true
  fi
}

invoke_clean() {
  title "清理 Claude / Claude Code 环境"
  if is_wsl; then
    result warn "检测到 WSL：本脚本只清理 WSL/Linux 侧，不会清理 Windows AppData。"
  fi

  local targets=()
  while IFS= read -r p; do
    [[ -e "$p" ]] && targets+=("$p")
  done < <(clean_targets)

  local total_files total_bytes
  total_files=$(file_count "${targets[@]}")
  total_bytes=$(path_size_bytes "${targets[@]}")
  printf '\n将删除：%s 个文件，约 %s\n' "$total_files" "$(format_bytes "$total_bytes")"
  for p in "${targets[@]}"; do printf '  - %s\n' "$p"; done
  printf '\n还会执行：停止进程、卸载 brew/npm/apt/dnf/apk 包、删除命令入口、清理 shell 环境变量、清 npm 缓存。\n'
  confirm_yes "输入 Y 开始执行清理" || return

  local total=6
  step_header 1 "$total" "结束相关进程"
  stop_processes
  result ok "已尝试结束 Claude / Claude Code 相关进程"
  step_footer

  step_header 2 "$total" "卸载安装包"
  uninstall_packages
  result ok "已尝试卸载 Homebrew / npm / apt / dnf / apk 安装包"
  step_footer

  step_header 3 "$total" "删除命令入口"
  local removed_cmds
  removed_cmds=$(remove_commands)
  local remaining_cmds
  remaining_cmds=$(claude_commands | sort -u)
  if [[ -z "$remaining_cmds" ]]; then
    result ok "claude / claude-code 命令已清理或不存在"
  else
    result fail "仍发现 claude / claude-code 命令残留"
    printf '%s\n' "$remaining_cmds" | sed 's/^/  - /'
  fi
  [[ "$removed_cmds" != "0" ]] && result ok "已删除 $removed_cmds 个命令入口"
  step_footer

  step_header 4 "$total" "删除文件和目录"
  for p in "${targets[@]}"; do rm -rf "$p" 2>/dev/null || true; done
  local remaining=()
  for p in "${targets[@]}"; do [[ -e "$p" ]] && remaining+=("$p"); done
  if [[ "${#remaining[@]}" -eq 0 ]]; then
    result ok "已删除常见文件和目录残留"
  else
    result fail "部分路径未能删除，剩余 ${#remaining[@]} 项"
    printf '%s\n' "${remaining[@]}" | sed 's/^/  - /'
  fi
  step_footer

  step_header 5 "$total" "清理环境变量"
  local changed
  changed=$(remove_env_lines)
  result ok "已清理当前会话环境变量；已处理 $changed 个 shell 配置文件"
  step_footer

  step_header 6 "$total" "清理 npm 缓存"
  if command -v npm >/dev/null 2>&1; then
    npm cache clean --force >/dev/null 2>&1 || true
    result ok "已执行 npm cache clean --force"
  else
    result warn "未找到 npm，跳过 npm 缓存清理"
  fi
  step_footer

  printf '\n\033[32m清理完成。建议重启终端后再运行检查。\033[0m\n'
}

invoke_check() {
  title "检查 Claude / Claude Code 残留"
  local total=5

  step_header 1 "$total" "平台提示"
  if is_wsl; then
    result warn "当前是 WSL；这里只检查 WSL/Linux 侧。Windows 侧请运行 PowerShell 脚本。"
  elif is_macos; then
    result ok "当前是 macOS"
  else
    result ok "当前是 Linux"
  fi
  step_footer

  step_header 2 "$total" "检查相关进程"
  if pgrep -f "claude|claude-code" >/dev/null 2>&1; then
    result fail "发现相关进程"
    pgrep -af "claude|claude-code" 2>/dev/null | sed 's/^/  - /'
  else
    result ok "未发现相关进程"
  fi
  step_footer

  step_header 3 "$total" "检查 claude / claude-code 命令"
  local cmds
  cmds=$(claude_commands | sort -u)
  if [[ -n "$cmds" ]]; then
    result fail "发现命令残留"
    printf '%s\n' "$cmds" | sed 's/^/  - /'
  else
    result ok "claude / claude-code 未找到"
  fi
  step_footer

  step_header 4 "$total" "检查常见文件和目录"
  local found=()
  while IFS= read -r p; do [[ -e "$p" ]] && found+=("$p"); done < <(clean_targets)
  if [[ "${#found[@]}" -eq 0 ]]; then
    result ok "未发现常见文件残留"
  else
    result fail "发现 ${#found[@]} 个常见残留路径"
    printf '%s\n' "${found[@]}" | sed 's/^/  - /'
  fi
  step_footer

  step_header 5 "$total" "检查环境变量"
  local envs
  envs=$(env | grep -E '^(ANTHROPIC|CLAUDE|MCP)' || true)
  if [[ -n "$envs" ]]; then
    result fail "发现相关环境变量"
    printf '%s\n' "$envs" | sed 's/^/  - /'
  else
    result ok "未发现相关环境变量"
  fi
  step_footer

  printf '\n\033[32m检查完成。\033[0m\n'
}

restore_item() {
  local backup_dir="$1"
  local rel="$2"
  local dest="$3"
  local src="$backup_dir/$rel"
  shopt -s nullglob
  local items=("$src")
  [[ "$rel" == *"*"* ]] && items=($src)
  local copied=0
  for item in "${items[@]}"; do
    [[ -e "$item" ]] || continue
    local target="$dest"
    if [[ "$rel" == *"*"* || -d "$dest" ]]; then
      target="$dest/$(basename "$item")"
    fi
    if [[ -e "$target" ]]; then
      confirm_yes "目标已存在：$target。输入 Y 覆盖" || continue
    fi
    copy_path "$item" "$target"
    copied=$((copied + $(file_count "$item")))
  done
  printf '%s\n' "$copied"
}

# 恢复后清洗：settings.json 剔除旧代理 token / base_url + 登录身份，
# .claude.json 剔除 oauthAccount 身份。防止把旧号凭据/指纹带回新号。
sanitize_settings_json() {
  local f="$HOME/.claude/settings.json"
  [[ -f "$f" ]] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    result warn "未装 jq：$f 未剥离旧 token/身份，请手动删除 env.ANTHROPIC_AUTH_TOKEN / ANTHROPIC_BASE_URL 与 oauthAccount"
    return 0
  fi
  jq '(if .env then .env |= del(.ANTHROPIC_AUTH_TOKEN, .ANTHROPIC_BASE_URL) else . end) | del(.oauthAccount, .oauthToken)' \
    "$f" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f" && result ok "已从 settings.json 剥离旧 token / base_url / 登录身份"
}
sanitize_claude_json() {
  local f="$HOME/.claude.json"
  [[ -f "$f" ]] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    result warn "未装 jq：$f 未剥离旧身份，请手动删除 oauthAccount"
    return 0
  fi
  jq 'del(.oauthAccount)' "$f" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f" && result ok "已从 .claude.json 剥离旧 oauthAccount 身份"
}

invoke_restore() {
  title "恢复备份"
  local backup_dir
  backup_dir=$(read_dir "请选择 ${BACKUP_PREFIX}_yyyyMMdd_HHmm 备份目录") || return

  printf '\n恢复选项：\n'
  printf '  [1] 会话记录和 projects\n'
  printf '  [2] 基础配置和用户记忆\n'
  printf '  [3] commands / agents\n'
  printf '  [4] hooks / skills（高风险）\n'
  printf '  [5] MCP / 应用配置（高风险）\n'
  printf '  [A] 全部恢复\n'
  printf '  [0] 返回主菜单\n'
  local choice
  read -r -p "请输入选项，可多选如 1,2,3: " choice
  [[ -z "$choice" || "$choice" == "0" ]] && return
  [[ "$choice" =~ [Aa] ]] && choice="1,2,3,4,5"
  if [[ "$choice" =~ [45] ]]; then
    result warn "你选择了高风险恢复项，可能带回旧 token、MCP、hooks、skills 和敏感路径。"
    confirm_yes "输入 Y 确认继续恢复高风险项" || return
  fi

  local total=0 copied=0
  if [[ "$choice" =~ 1 ]]; then
    step_header 1 5 "恢复会话记录和 projects"
    copied=0
    copied=$((copied + $(restore_item "$backup_dir" ".claude/*.jsonl" "$HOME/.claude")))
    copied=$((copied + $(restore_item "$backup_dir" ".claude/projects" "$HOME/.claude/projects")))
    result ok "已恢复 $copied 个文件"
    total=$((total + copied))
    step_footer
  fi
  if [[ "$choice" =~ 2 ]]; then
    step_header 2 5 "恢复基础配置和用户记忆"
    copied=0
    copied=$((copied + $(restore_item "$backup_dir" ".claude/settings.json" "$HOME/.claude/settings.json")))
    copied=$((copied + $(restore_item "$backup_dir" ".claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md")))
    copied=$((copied + $(restore_item "$backup_dir" ".claude.json" "$HOME/.claude.json")))
    result ok "已恢复 $copied 个文件"
    sanitize_settings_json
    sanitize_claude_json
    total=$((total + copied))
    step_footer
  fi
  if [[ "$choice" =~ 3 ]]; then
    step_header 3 5 "恢复 commands / agents"
    copied=0
    copied=$((copied + $(restore_item "$backup_dir" ".claude/commands" "$HOME/.claude/commands")))
    copied=$((copied + $(restore_item "$backup_dir" ".claude/agents" "$HOME/.claude/agents")))
    result ok "已恢复 $copied 个文件"
    total=$((total + copied))
    step_footer
  fi
  if [[ "$choice" =~ 4 ]]; then
    step_header 4 5 "恢复 hooks / skills"
    copied=0
    copied=$((copied + $(restore_item "$backup_dir" ".claude/hooks" "$HOME/.claude/hooks")))
    copied=$((copied + $(restore_item "$backup_dir" ".claude/skills" "$HOME/.claude/skills")))
    result ok "已恢复 $copied 个文件"
    total=$((total + copied))
    step_footer
  fi
  if [[ "$choice" =~ 5 ]]; then
    step_header 5 5 "恢复 MCP / 应用配置"
    copied=0
    copied=$((copied + $(restore_item "$backup_dir" ".claude/mcp" "$HOME/.claude/mcp")))
    copied=$((copied + $(restore_item "$backup_dir" ".config/Claude" "$HOME/.config/Claude")))
    copied=$((copied + $(restore_item "$backup_dir" ".config/claude" "$HOME/.config/claude")))
    copied=$((copied + $(restore_item "$backup_dir" ".config/claude-code" "$HOME/.config/claude-code")))
    if is_macos; then
      copied=$((copied + $(restore_item "$backup_dir" "Library/Application Support/Claude" "$HOME/Library/Application Support/Claude")))
      copied=$((copied + $(restore_item "$backup_dir" "Library/Application Support/claude-code" "$HOME/Library/Application Support/claude-code")))
    fi
    result ok "已恢复 $copied 个文件"
    total=$((total + copied))
    step_footer
  fi
  printf '\n\033[32m恢复流程完成：共恢复 %s 个文件。\033[0m\n' "$total"
}

main_menu() {
  while true; do
    clear 2>/dev/null || true
    title "Claude / Claude Code 清理工具"
    printf '  适用于 macOS / Linux / WSL。WSL 不会清理 Windows 侧 AppData。\n\n'
    printf '  [1] 备份        关键数据，保留原目录结构\n'
    printf '  [2] 清理环境    列出残留，确认后删除\n'
    printf '  [3] 检查残留    快速检查固定位置\n'
    printf '  [4] 恢复备份    从备份中选择恢复\n'
    printf '  [0] 退出\n'
    line
    local choice
    read -r -p "请输入选项: " choice
    case "$choice" in
      1) invoke_backup ;;
      2) invoke_clean ;;
      3) invoke_check ;;
      4) invoke_restore ;;
      0) exit 0 ;;
      *) result warn "无效选项，请重新输入。" ;;
    esac
    printf '\n'
    read -r -p "按回车返回主菜单"
  done
}

main_menu
