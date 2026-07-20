#!/usr/bin/env bash
# Prepare a stable imagegen CLI runtime and wrapper command.
set -u

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
SYSTEM_SKILLS="$CODEX_HOME/skills/.system"
IMAGEGEN_CLI="${CODEX_IMAGEGEN_CLI:-$SYSTEM_SKILLS/imagegen/scripts/image_gen.py}"
IMAGEGEN_VENV="${CODEX_IMAGEGEN_VENV:-$CODEX_HOME/venvs/imagegen-cli}"
WRAPPER_DIR="${CODEX_IMAGEGEN_WRAPPER_DIR:-$HOME/.local/bin}"
WRAPPER="${CODEX_IMAGEGEN_WRAPPER:-$WRAPPER_DIR/codex-imagegen}"
KEY_SERVICE='CC_SWITCH_CODEX_API_KEY'
URL_SERVICE='CC_SWITCH_CODEX_BASE_URL'

notice() { printf '  ○ %s\n' "$1"; }
success() { printf '  ✓ %s\n' "$1"; }

python_ok() {
  [ -x "$IMAGEGEN_VENV/bin/python" ] || return 1
  "$IMAGEGEN_VENV/bin/python" - <<'PY' >/dev/null 2>&1
import sys
print(sys.executable)
PY
}

deps_ok() {
  "$IMAGEGEN_VENV/bin/python" - <<'PY' >/dev/null 2>&1
import openai
import PIL
PY
}

create_venv() {
  local parent
  parent="$(dirname "$IMAGEGEN_VENV")"
  mkdir -p "$parent" || return 1

  if [ -e "$IMAGEGEN_VENV" ] && ! python_ok; then
    rm -rf "$IMAGEGEN_VENV"
  fi

  if python_ok; then
    return 0
  fi

  if command -v uv >/dev/null 2>&1; then
    uv venv "$IMAGEGEN_VENV" --python python3 >/dev/null || return 1
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m venv "$IMAGEGEN_VENV" >/dev/null || return 1
  else
    return 1
  fi
}

install_deps() {
  if deps_ok; then
    return 0
  fi

  if [ "${CODEX_IMAGEGEN_SKIP_INSTALL:-0}" = "1" ]; then
    notice "已跳过 imagegen CLI Python 依赖安装"
    return 0
  fi

  if command -v uv >/dev/null 2>&1; then
    uv pip install --python "$IMAGEGEN_VENV/bin/python" openai pillow >/dev/null || return 1
  else
    "$IMAGEGEN_VENV/bin/python" -m pip install openai pillow >/dev/null || return 1
  fi
}

write_wrapper() {
  mkdir -p "$WRAPPER_DIR" || return 1
  cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="\${CODEX_HOME:-\$HOME/.codex}"
IMAGEGEN_PYTHON="\${CODEX_IMAGEGEN_PYTHON:-$IMAGEGEN_VENV/bin/python}"
IMAGEGEN_CLI="\${CODEX_IMAGEGEN_CLI:-$IMAGEGEN_CLI}"
KEY_SERVICE='$KEY_SERVICE'
URL_SERVICE='$URL_SERVICE'

read_json_value() {
  local file="\$1"
  local key="\$2"
  [ -r "\$file" ] || return 0
  "\$IMAGEGEN_PYTHON" - "\$file" "\$key" <<'PY' 2>/dev/null || true
import json
import sys
try:
    value = json.load(open(sys.argv[1], encoding="utf-8")).get(sys.argv[2], "")
except Exception:
    value = ""
if isinstance(value, str):
    print(value, end="")
PY
}

read_keychain_value() {
  local service="\$1"
  if [ "\$(uname -s 2>/dev/null || true)" = "Darwin" ] && command -v security >/dev/null 2>&1; then
    security find-generic-password -a "\${USER:-\$(id -un)}" -s "\$service" -w 2>/dev/null || true
  fi
}

api_key="\${OPENAI_API_KEY:-}"
base_url="\${OPENAI_BASE_URL:-}"

[ -n "\$api_key" ] || api_key="\$(read_keychain_value "\$KEY_SERVICE")"
[ -n "\$base_url" ] || base_url="\$(read_keychain_value "\$URL_SERVICE")"
[ -n "\$api_key" ] || api_key="\$(read_json_value "\$CODEX_HOME/auth.json" OPENAI_API_KEY)"

if [ -z "\$api_key" ]; then
  printf 'OPENAI_API_KEY 缺失。先运行 codex-baseline，或确认 ~/.codex/auth.json / macOS Keychain 已有 Codex API Key。\\n' >&2
  exit 1
fi
if [ ! -x "\$IMAGEGEN_PYTHON" ]; then
  printf 'imagegen Python 环境缺失: %s\\n请先运行 codex-baseline。\\n' "\$IMAGEGEN_PYTHON" >&2
  exit 1
fi
if [ ! -f "\$IMAGEGEN_CLI" ]; then
  printf 'imagegen CLI 缺失: %s\\n请先恢复 ~/.codex/skills/.system/imagegen。\\n' "\$IMAGEGEN_CLI" >&2
  exit 1
fi

export OPENAI_API_KEY="\$api_key"
[ -n "\$base_url" ] && export OPENAI_BASE_URL="\$base_url"
exec "\$IMAGEGEN_PYTHON" "\$IMAGEGEN_CLI" "\$@"
EOF
  chmod +x "$WRAPPER" || return 1
}

if [ ! -f "$IMAGEGEN_CLI" ]; then
  notice "imagegen CLI 不存在：$IMAGEGEN_CLI"
  exit 1
fi

create_venv || {
  notice "准备 imagegen CLI Python 虚拟环境失败"
  exit 1
}
install_deps || {
  notice "安装 imagegen CLI 依赖 openai/pillow 失败"
  exit 1
}
write_wrapper || {
  notice "写入 codex-imagegen 包装命令失败"
  exit 1
}

success "imagegen CLI 已就绪：$WRAPPER"
