#!/usr/bin/env bash
# Install an idempotent zsh wrapper that injects the Codex auth key only into the Codex child process.
set -euo pipefail

ZSHENV="${ZDOTDIR:-$HOME}/.zshenv"
START_MARKER='# >>> vft-kit codex auth env >>>'

if [ -f "$ZSHENV" ] && grep -Fq "$START_MARKER" "$ZSHENV"; then
  printf 'Codex API key injector already installed in %s\n' "$ZSHENV"
  exit 0
fi

mkdir -p "$(dirname "$ZSHENV")"
touch "$ZSHENV"

cat >> "$ZSHENV" <<'EOF'

# >>> vft-kit codex auth env >>>
# Read the active CC Switch/Codex key at launch time; do not export it to the parent shell.
codex() {
  local auth_file="${CODEX_HOME:-$HOME/.codex}/auth.json"
  local api_key=""

  if [[ -r "$auth_file" ]]; then
    api_key="$(node -e 'const fs=require("fs");try{const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(typeof j.OPENAI_API_KEY==="string"?j.OPENAI_API_KEY:"")}catch{}' "$auth_file" 2>/dev/null)"
  fi

  if [[ -n "$api_key" ]]; then
    OPENAI_API_KEY="$api_key" command codex "$@"
  else
    command codex "$@"
  fi
}
# <<< vft-kit codex auth env <<<
EOF

printf 'Installed Codex API key injector in %s\n' "$ZSHENV"
printf 'Open a new terminal before starting Codex.\n'
