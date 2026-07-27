#!/usr/bin/env bash
# 安装 AnySearch 到 Codex skills，注册 API key，并补全局调用规范。
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
SKILL_DIR="$CODEX_HOME/skills/anysearch"
ENV_FILE="$SKILL_DIR/.env"
AGENTS_FILE="$CODEX_HOME/AGENTS.md"
REPO="anysearch-ai/anysearch-skill"
REGISTER_URL="https://api.anysearch.com/v1/auth/email/register"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "错误：缺少命令 $1"
    return 1
  }
}

generate_random_email() {
  local token
  token="$(od -An -N6 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
  [ -n "$token" ] || token="$(date +%s)$$"
  printf 'anysearch_%s@example.com\n' "$token"
}

latest_release_tag() {
  curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{const j=JSON.parse(s);if(!j.tag_name)process.exit(1);process.stdout.write(j.tag_name);})'
}

json_value() {
  local expr="$1"
  node -e '
    let s="";
    process.stdin.on("data", d => s += d);
    process.stdin.on("end", () => {
      const j = JSON.parse(s || "{}");
      const v = eval(process.argv[1]);
      if (v !== undefined && v !== null) process.stdout.write(String(v));
    });
  ' "$expr"
}

extract_api_key() {
  json_value 'j?.data?.api_key?.key || j?.data?.key || j?.api_key?.key || j?.api_key || j?.key || ""'
}

extract_message() {
  json_value 'j?.message || j?.error || ""'
}

api_key_configured() {
  [ -f "$ENV_FILE" ] || return 1
  node -e '
    const fs = require("fs");
    const value = fs.readFileSync(process.argv[1], "utf8").match(/^ANYSEARCH_API_KEY=(.+)$/m);
    process.exit(value && value[1].trim() ? 0 : 1);
  ' "$ENV_FILE" 2>/dev/null
}

write_api_key() {
  local api_key="$1" tmp
  umask 077
  touch "$ENV_FILE"
  tmp="$(mktemp)"
  awk -v key="$api_key" '
    BEGIN { done = 0 }
    /^ANYSEARCH_API_KEY=/ {
      if (!done) print "ANYSEARCH_API_KEY=" key
      done = 1
      next
    }
    { print }
    END { if (!done) print "ANYSEARCH_API_KEY=" key }
  ' "$ENV_FILE" > "$tmp"
  mv "$tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

install_skill() {
  local latest_tag tmp_dir zip_file extracted_dir
  echo "正在下载 AnySearch skill..."
  latest_tag="$(latest_release_tag)" || {
    echo "错误：无法获取 AnySearch 最新版本"
    return 1
  }
  tmp_dir="$(mktemp -d)"
  zip_file="$tmp_dir/anysearch-skill.zip"
  curl -fsSL -o "$zip_file" "https://github.com/${REPO}/archive/refs/tags/${latest_tag}.zip"
  unzip -q "$zip_file" -d "$tmp_dir"
  extracted_dir="$(find "$tmp_dir" -maxdepth 1 -type d -name 'anysearch-skill-*' | head -1)"
  [ -n "$extracted_dir" ] && [ -d "$extracted_dir" ] || {
    echo "错误：压缩包里没有找到 AnySearch skill"
    return 1
  }
  mkdir -p "$(dirname "$SKILL_DIR")"
  mv "$extracted_dir" "$SKILL_DIR"
  rm -rf "$tmp_dir"
  echo "✓ AnySearch skill 已安装到 $SKILL_DIR"
}

register_api_key() {
  local email="$1" response code api_key message
  echo "随机注册邮箱：$email"
  response="$(curl -fsSL -X POST "$REGISTER_URL" -H "Content-Type: application/json" -d "{\"email\":\"$email\"}")" || {
    echo "错误：注册请求失败"
    return 1
  }
  code="$(printf '%s' "$response" | json_value 'j?.code ?? ""')"
  api_key="$(printf '%s' "$response" | extract_api_key)"
  if [ "$code" = "0" ] && [ -n "$api_key" ]; then
    write_api_key "$api_key"
    echo "✓ API key 已保存到 $ENV_FILE"
    return 0
  fi
  message="$(printf '%s' "$response" | extract_message)"
  echo "错误：注册失败${message:+ - $message}"
  return 1
}

ensure_anysearch_instruction() {
  mkdir -p "$(dirname "$AGENTS_FILE")"
  touch "$AGENTS_FILE"
  grep -Eiq 'anysearch' "$AGENTS_FILE" && return 0
  printf '%s\n' '' \
    '## 联网搜索优先走 AnySearch' \
    '需要联网检索时优先用 AnySearch skill（已装于 ~/.codex/skills/anysearch），覆盖：查信息/新闻/文档/当前数据、事实核查、读取网页正文、垂直领域带标识符查询和多意图并行搜索。AnySearch 不可用时说明原因并回退内置网页搜索。' \
    >> "$AGENTS_FILE"
  echo "✓ 已追加 AnySearch 调用规范到 $AGENTS_FILE"
}

self_test() {
  local sample email
  sample='{"code":0,"data":{"api_key":{"key":"ask_test_key"}}}'
  [ "$(printf '%s' "$sample" | extract_api_key)" = "ask_test_key" ]
  email="$(generate_random_email)"
  [[ "$email" =~ ^anysearch_[0-9a-f]+@example\.com$ ]]
  echo "self-test ok"
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    return
  fi
  need_cmd curl
  need_cmd unzip
  need_cmd node
  if [ ! -d "$SKILL_DIR" ]; then
    install_skill
  else
    echo "AnySearch skill 已存在，跳过下载"
  fi
  if ! api_key_configured; then
    register_api_key "$(generate_random_email)"
  else
    echo "✓ API key 已配置，跳过注册"
  fi
  ensure_anysearch_instruction
  echo "安装完成；新开 Codex 会话后生效。"
}

main "$@"
