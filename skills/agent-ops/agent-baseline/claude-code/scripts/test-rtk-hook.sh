#!/usr/bin/env bash
# check.sh 必须把「RTK hook 未装」判为缺失（必需项），装了则判过。
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

home="$tmp/home"
bin="$tmp/bin"
mkdir -p "$home/.claude" "$bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/rtk"
chmod +x "$bin/rtk"

printf '{}\n' > "$home/.claude/settings.json"
out="$(HOME="$home" PATH="$bin:$PATH" bash "$DIR/check.sh" 2>&1 || true)"
printf '%s' "$out" | grep -qE '✗.*RTK hook' || { printf 'FAIL: missing RTK hook not reported\n' >&2; exit 1; }

cat > "$home/.claude/settings.json" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
EOF
out="$(HOME="$home" PATH="$bin:$PATH" bash "$DIR/check.sh" 2>&1 || true)"
printf '%s' "$out" | grep -qE '✓.*RTK hook' || { printf 'FAIL: installed RTK hook not recognized\n' >&2; exit 1; }

printf 'PASS: cc-baseline requires the RTK PreToolUse hook\n'
