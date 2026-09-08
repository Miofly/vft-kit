#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
TEST_HOME="$tmp/home"
TEST_CODEX_HOME="$TEST_HOME/.codex"
mkdir -p "$tmp/bin" "$TEST_CODEX_HOME"

printf '%s\n' '# inactive global' > "$TEST_CODEX_HOME/AGENTS.md"
cat > "$TEST_CODEX_HOME/AGENTS.override.md" <<EOF
# active override
@$TEST_CODEX_HOME/RTK.md
EOF

cat > "$tmp/bin/brew" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_LOG"
printf '%s\n' '#!/usr/bin/env bash' 'printf "rtk test\n"' > "$FAKE_RTK"
chmod +x "$FAKE_RTK"
EOF
chmod +x "$tmp/bin/brew"

run_install() {
  env HOME="$TEST_HOME" CODEX_HOME="$TEST_CODEX_HOME" PATH="$tmp/bin:/usr/bin:/bin" \
    TEST_LOG="$tmp/brew.log" FAKE_RTK="$tmp/bin/rtk" bash "$SKILL_DIR/scripts/install-rtk.sh"
}

run_install
run_install

[ "$(wc -l < "$tmp/brew.log" | tr -d ' ')" = 1 ] || { printf 'FAIL: Homebrew should run exactly once\n' >&2; exit 1; }
[ "$(cat "$tmp/brew.log")" = 'install rtk' ] || { printf 'FAIL: wrong Homebrew command\n' >&2; exit 1; }
[ "$(cat "$TEST_CODEX_HOME/AGENTS.md")" = '# inactive global' ] || { printf 'FAIL: inactive AGENTS.md should not be modified\n' >&2; exit 1; }
[ "$(grep -Fc '<!-- >>> vft-kit rtk safe shell usage >>> -->' "$TEST_CODEX_HOME/AGENTS.override.md")" -eq 1 ] || { printf 'FAIL: active override must contain one RTK block\n' >&2; exit 1; }
[ "$(grep -Fc '<!-- <<< vft-kit rtk safe shell usage <<< -->' "$TEST_CODEX_HOME/AGENTS.override.md")" -eq 1 ] || { printf 'FAIL: active override must contain one RTK end marker\n' >&2; exit 1; }
grep -Fq 'RTK 是受限使用的输出压缩器，不是 Shell 通用前缀' "$TEST_CODEX_HOME/AGENTS.override.md" || { printf 'FAIL: safe scoped rule missing\n' >&2; exit 1; }
grep -Fq '命令同时满足以下条件时必须使用' "$TEST_CODEX_HOME/AGENTS.override.md" || { printf 'FAIL: safe commands must require RTK\n' >&2; exit 1; }
grep -Fq '复杂 `find`' "$TEST_CODEX_HOME/AGENTS.override.md" || { printf 'FAIL: compound find exclusion missing\n' >&2; exit 1; }
grep -Fq '含管道、重定向' "$TEST_CODEX_HOME/AGENTS.override.md" || { printf 'FAIL: pipeline and redirect exclusion missing\n' >&2; exit 1; }
! grep -Fq "@$TEST_CODEX_HOME/RTK.md" "$TEST_CODEX_HOME/AGENTS.override.md" || { printf 'FAIL: unsafe RTK.md import should be removed from active file\n' >&2; exit 1; }

CUSTOM_AGENTS="$tmp/custom-AGENTS.md"
printf '%s\n' '# custom target' > "$CUSTOM_AGENTS"
CODEX_AGENTS="$CUSTOM_AGENTS" run_install
grep -Fq 'vft-kit rtk safe shell usage' "$CUSTOM_AGENTS" || { printf 'FAIL: CODEX_AGENTS target not updated\n' >&2; exit 1; }

BROKEN_AGENTS="$tmp/broken-AGENTS.md"
printf '%s\n' '# keep me' '<!-- >>> vft-kit rtk safe shell usage >>> -->' > "$BROKEN_AGENTS"
before="$(cksum "$BROKEN_AGENTS")"
if CODEX_AGENTS="$BROKEN_AGENTS" run_install >/dev/null 2>&1; then
  printf 'FAIL: malformed managed block should fail\n' >&2
  exit 1
fi
[ "$(cksum "$BROKEN_AGENTS")" = "$before" ] || { printf 'FAIL: malformed target must remain unchanged\n' >&2; exit 1; }

printf 'PASS: RTK install and safe active-AGENTS sync are idempotent\n'
