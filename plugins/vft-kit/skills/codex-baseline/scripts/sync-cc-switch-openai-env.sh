#!/usr/bin/env bash
# Synchronize the active CC-Switch Codex credentials into Keychain and new zsh sessions.
set -u

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CC_SWITCH_DB="${CC_SWITCH_DB:-$HOME/.cc-switch/cc-switch.db}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
START_MARKER='# >>> vft-kit cc-switch openai env >>>'
END_MARKER='# <<< vft-kit cc-switch openai env <<<'
LEGACY_MARKER='# CC-Switch Codex provider credentials (stored in macOS Keychain).'
KEY_SERVICE='CC_SWITCH_CODEX_API_KEY'
URL_SERVICE='CC_SWITCH_CODEX_BASE_URL'

notice() { printf '  ○ %s\n' "$1"; }
success() { printf '  ✓ %s\n' "$1"; }

read_auth_key() {
  local auth_file="$CODEX_HOME/auth.json"
  [ -r "$auth_file" ] || return 0

  if command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs");
      try {
        const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8")).OPENAI_API_KEY;
        if (typeof value === "string") process.stdout.write(value);
      } catch {}
    ' "$auth_file" 2>/dev/null
  elif command -v jq >/dev/null 2>&1; then
    jq -r '.OPENAI_API_KEY // empty' "$auth_file" 2>/dev/null
  fi
}

read_config_base_url() {
  local config="$CODEX_HOME/config.toml"
  local provider
  [ -r "$config" ] || return 0

  provider="$(awk '
    /^\[/ { exit }
    /^[[:space:]]*model_provider[[:space:]]*=/ {
      value=$0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      sub(/[[:space:]]*#.*/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value ~ /^".*"$/) value=substr(value, 2, length(value)-2)
      print value
      exit
    }
  ' "$config")"

  [ -n "$provider" ] || return 0
  awk -v target="[model_providers.$provider]" '
    /^\[/ { in_target=($0 == target) }
    in_target && /^[[:space:]]*base_url[[:space:]]*=/ {
      value=$0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      sub(/[[:space:]]*#.*/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value ~ /^".*"$/) value=substr(value, 2, length(value)-2)
      print value
      exit
    }
  ' "$config"
}

read_db_key() {
  command -v sqlite3 >/dev/null 2>&1 && [ -r "$CC_SWITCH_DB" ] || return 0
  sqlite3 "$CC_SWITCH_DB" \
    "SELECT COALESCE(json_extract(settings_config, '$.auth.OPENAI_API_KEY'), '') FROM providers WHERE app_type='codex' AND is_current=1 LIMIT 1;" \
    2>/dev/null || true
}

read_db_base_url() {
  command -v sqlite3 >/dev/null 2>&1 && [ -r "$CC_SWITCH_DB" ] || return 0
  sqlite3 "$CC_SWITCH_DB" \
    "SELECT COALESCE(e.url, '') FROM providers p LEFT JOIN provider_endpoints e ON e.provider_id=p.id AND e.app_type=p.app_type WHERE p.app_type='codex' AND p.is_current=1 LIMIT 1;" \
    2>/dev/null || true
}

write_managed_zsh_block() {
  local target_dir tmp mode
  target_dir="$(dirname "$ZSHRC")"
  mkdir -p "$target_dir" || return 1
  touch "$ZSHRC" || return 1
  mode="$(stat -f '%Lp' "$ZSHRC" 2>/dev/null || stat -c '%a' "$ZSHRC" 2>/dev/null || printf '600')"
  tmp="$(mktemp "$target_dir/.zshrc.vft-kit.XXXXXX")" || return 1

  awk -v start="$START_MARKER" -v end="$END_MARKER" -v legacy="$LEGACY_MARKER" '
    $0 == start { managed=1; next }
    managed { if ($0 == end) managed=0; next }
    $0 == legacy { legacy_lines=2; next }
    legacy_lines > 0 { legacy_lines--; next }
    { lines[++count]=$0 }
    END {
      while (count > 0 && lines[count] == "") count--
      for (i=1; i<=count; i++) print lines[i]
    }
  ' "$ZSHRC" > "$tmp" || { rm -f "$tmp"; return 1; }

  cat >> "$tmp" <<'EOF'

# >>> vft-kit cc-switch openai env >>>
# Values stay in macOS Keychain; only lookups are stored here.
export OPENAI_API_KEY="$(security find-generic-password -a "$USER" -s 'CC_SWITCH_CODEX_API_KEY' -w 2>/dev/null)"
export OPENAI_BASE_URL="$(security find-generic-password -a "$USER" -s 'CC_SWITCH_CODEX_BASE_URL' -w 2>/dev/null)"
# <<< vft-kit cc-switch openai env <<<
EOF

  chmod "$mode" "$tmp" 2>/dev/null || true
  mv "$tmp" "$ZSHRC"
}

platform="${VFT_PLATFORM:-$(uname -s 2>/dev/null || printf unknown)}"
if [ "$platform" != "Darwin" ]; then
  notice "CC-Switch OpenAI 环境同步仅支持 macOS，已跳过"
  exit 0
fi

if ! command -v security >/dev/null 2>&1; then
  notice "未找到 macOS security 命令，已跳过 CC-Switch OpenAI 环境同步"
  exit 0
fi

api_key="$(read_auth_key)"
base_url="$(read_config_base_url)"
[ -n "$api_key" ] || api_key="$(read_db_key)"
[ -n "$base_url" ] || base_url="$(read_db_base_url)"

if [ -z "$api_key" ]; then
  notice "未找到可同步的 Codex API Key，保留现有钥匙串配置"
  exit 0
fi
if [ -z "$base_url" ]; then
  notice "未找到可同步的 Codex Base URL，保留现有钥匙串配置"
  exit 0
fi

account="${USER:-$(id -un)}"
security add-generic-password -a "$account" -s "$KEY_SERVICE" -w "$api_key" -U >/dev/null 2>&1 || {
  notice "写入 Codex API Key 到 macOS 钥匙串失败"
  exit 1
}
security add-generic-password -a "$account" -s "$URL_SERVICE" -w "$base_url" -U >/dev/null 2>&1 || {
  notice "写入 Codex Base URL 到 macOS 钥匙串失败"
  exit 1
}
write_managed_zsh_block || {
  notice "更新 $ZSHRC 的 CC-Switch 托管块失败"
  exit 1
}

provider_host="$(printf '%s' "$base_url" | sed -E 's#https?://([^/]+).*#\1#')"
success "CC-Switch Codex 认证已同步到钥匙串与新 zsh 会话（Key 长度 ${#api_key}，主机 ${provider_host}）"
unset api_key base_url
