#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

home="$tmp/home"
bin="$tmp/bin"
mkdir -p "$home/.claude" "$bin"
cat > "$home/.claude/settings.json" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"command":"rtk rewrite"}]}]}}
EOF
cat > "$bin/rtk" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$bin/rtk"

output="$(HOME="$home" PATH="$bin:$PATH" bash "$DIR/check.sh" 2>&1 || true)"
case "$output" in
  *"RTK hook"*|*"RTK 压缩豁免"*) exit 1 ;;
esac
grep -Eq 'has_cmd rtk.*\|\| bad "rtk"' "$DIR/check.sh"

printf 'PASS: cc-baseline requires RTK without checking hook policy\n'
