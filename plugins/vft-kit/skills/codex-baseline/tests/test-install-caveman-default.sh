#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
INSTALL_SCRIPT="$SKILL_DIR/scripts/install-caveman-default.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

TEST_HOME="$TMP_ROOT/home"
TEST_CODEX_HOME="$TEST_HOME/.codex"
mkdir -p "$TEST_CODEX_HOME" "$TEST_HOME/.config/caveman"
printf '%s\n' '# global rules' > "$TEST_CODEX_HOME/AGENTS.md"
printf '%s\n' '# local override' > "$TEST_CODEX_HOME/AGENTS.override.md"
printf '%s\n' '{"keep":true,"defaultMode":"off"}' > "$TEST_HOME/.config/caveman/config.json"

HOME="$TEST_HOME" CODEX_HOME="$TEST_CODEX_HOME" bash "$INSTALL_SCRIPT"
HOME="$TEST_HOME" CODEX_HOME="$TEST_CODEX_HOME" bash "$INSTALL_SCRIPT"

[ "$(grep -Fc '<!-- >>> vft-kit caveman default full >>> -->' "$TEST_CODEX_HOME/AGENTS.override.md")" -eq 1 ] || { printf 'FAIL: active override must contain one managed block\n' >&2; exit 1; }
! grep -Fq 'vft-kit caveman default full' "$TEST_CODEX_HOME/AGENTS.md" || { printf 'FAIL: inactive AGENTS.md should not be modified\n' >&2; exit 1; }
node -e "const j=require(process.argv[1]);process.exit(j.defaultMode==='full'&&j.keep===true?0:1)" "$TEST_HOME/.config/caveman/config.json"

printf 'PASS: Codex Caveman default targets active AGENTS file\n'
