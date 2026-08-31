#!/usr/bin/env bash
# install-rtk.sh：缺失时装、已装则跳过；hook 幂等补进 settings.json 且不动已有 hook。
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.claude"

cat > "$tmp/bin/brew" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_LOG"
printf '%s\n' '#!/usr/bin/env bash' 'printf "rtk test\n"' > "$FAKE_RTK"
chmod +x "$FAKE_RTK"
EOF
chmod +x "$tmp/bin/brew"

settings="$tmp/home/.claude/settings.json"
cat > "$settings" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"other-hook"}]}]}}
EOF

run(){ PATH="$tmp/bin:$(dirname "$(command -v node)"):/usr/bin:/bin" \
  TEST_LOG="$tmp/brew.log" FAKE_RTK="$tmp/bin/rtk" \
  SETTINGS="$settings" RTK_MD="$tmp/home/.claude/RTK.md" bash "$DIR/install-rtk.sh"; }
printf 'stub\n' > "$tmp/home/.claude/RTK.md"   # 跳过 rtk init -g，本测试只验 hook 补丁
run
run

[ "$(wc -l < "$tmp/brew.log" | tr -d ' ')" = 1 ] || { printf 'FAIL: Homebrew should run exactly once\n' >&2; exit 1; }
[ "$(cat "$tmp/brew.log")" = 'install rtk' ] || { printf 'FAIL: wrong Homebrew command\n' >&2; exit 1; }

node -e '
const s=require(process.argv[1]);const pre=s.hooks.PreToolUse;
const rtk=JSON.stringify(pre).split("rtk hook").length-1;
if(rtk!==1){console.error("FAIL: rtk hook count is "+rtk);process.exit(1)}
if(!JSON.stringify(pre).includes("other-hook")){console.error("FAIL: existing hook clobbered");process.exit(1)}
' "$settings"

printf 'PASS: RTK binary and PreToolUse hook install idempotently\n'
