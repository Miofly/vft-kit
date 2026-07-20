#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SKILL_DIR/scripts/refresh-local-codex-plugin.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
CODEX_HOME="$HOME_DIR/.codex"
MARKETPLACE_ROOT="$TMP_ROOT/marketplace"
PLUGIN_ROOT="$MARKETPLACE_ROOT/plugins/vft-kit"
FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$PLUGIN_ROOT/.codex-plugin" "$PLUGIN_ROOT/skills/a" "$PLUGIN_ROOT/skills/b" "$FAKE_BIN" "$CODEX_HOME"

cat > "$PLUGIN_ROOT/.codex-plugin/plugin.json" <<'EOF'
{"name":"vft-kit","version":"0.0.1-test","skills":"./skills/"}
EOF
printf '%s\n' '---' 'name: a' '---' '# A' > "$PLUGIN_ROOT/skills/a/SKILL.md"
printf '%s\n' '---' 'name: b' '---' '# B' > "$PLUGIN_ROOT/skills/b/SKILL.md"

cat > "$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1 $2 $3" == "plugin marketplace list" ]]; then
  printf 'MARKETPLACE ROOT\n'
  printf 'vft-kit %s\n' "$MARKETPLACE_ROOT"
  exit 0
fi

if [[ "$1 $2" == "plugin remove" ]]; then
  rm -rf "$CODEX_HOME/plugins/cache/vft-kit/vft-kit"
  printf 'removed %s\n' "$3"
  exit 0
fi

if [[ "$1 $2" == "plugin add" ]]; then
  cache="$CODEX_HOME/plugins/cache/vft-kit/vft-kit/0.0.1-test"
  mkdir -p "$(dirname "$cache")"
  cp -R "$PLUGIN_ROOT" "$cache"
  printf 'installed %s\n' "$3"
  exit 0
fi

printf 'unexpected codex args: %s\n' "$*" >&2
exit 2
EOF
chmod +x "$FAKE_BIN/codex"

output="$(
  HOME="$HOME_DIR" \
  CODEX_HOME="$CODEX_HOME" \
  MARKETPLACE_ROOT="$MARKETPLACE_ROOT" \
  PLUGIN_ROOT="$PLUGIN_ROOT" \
  PATH="$FAKE_BIN:$PATH" \
  bash "$SCRIPT" -p vft-kit -q
)"

grep -Fq 'Codex cache 已刷新' <<< "$output" || { printf 'FAIL: success line absent\n%s\n' "$output" >&2; exit 1; }
[ -f "$CODEX_HOME/plugins/cache/vft-kit/vft-kit/0.0.1-test/skills/a/SKILL.md" ] || { printf 'FAIL: cache skill a absent\n' >&2; exit 1; }
[ -f "$CODEX_HOME/plugins/cache/vft-kit/vft-kit/0.0.1-test/skills/b/SKILL.md" ] || { printf 'FAIL: cache skill b absent\n' >&2; exit 1; }

printf 'PASS: refresh-local-codex-plugin\n'
