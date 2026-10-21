#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="$SKILL_DIR/scripts/sync-cc-switch-openai-env.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

TEST_HOME="$TMP_ROOT/home"
TEST_CODEX_HOME="$TEST_HOME/.codex"
FAKE_BIN="$TMP_ROOT/bin"
FAKE_KEYCHAIN_DIR="$TMP_ROOT/keychain"
mkdir -p "$TEST_CODEX_HOME" "$FAKE_BIN" "$FAKE_KEYCHAIN_DIR"

cat > "$FAKE_BIN/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

store="${FAKE_KEYCHAIN_DIR:?}"
command_name="${1:-}"
shift || true
service=""
password=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -s) service="$2"; shift 2 ;;
    -w)
      if [ "$command_name" = "add-generic-password" ]; then
        password="$2"
        shift 2
      else
        shift
      fi
      ;;
    -a) shift 2 ;;
    -U) shift ;;
    *) shift ;;
  esac
done

case "$command_name" in
  add-generic-password)
    [ -n "$service" ]
    printf '%s' "$password" > "$store/$service"
    ;;
  find-generic-password)
    [ -f "$store/$service" ]
    cat "$store/$service"
    ;;
  *)
    printf 'unsupported security command: %s\n' "$command_name" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$FAKE_BIN/security"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "$3 (expected '$2', got '$1')"
}

run_sync() {
  env \
    HOME="$TEST_HOME" \
    USER="test-user" \
    CODEX_HOME="$TEST_CODEX_HOME" \
    ZDOTDIR="$TEST_HOME" \
    VFT_PLATFORM="Darwin" \
    FAKE_KEYCHAIN_DIR="$FAKE_KEYCHAIN_DIR" \
    PATH="$FAKE_BIN:$PATH" \
    bash "$SYNC_SCRIPT"
}

write_active_config() {
  local key="$1"
  local base_url="$2"
  node -e '
    const fs = require("fs");
    fs.writeFileSync(process.argv[1], JSON.stringify({ auth_mode: "apikey", OPENAI_API_KEY: process.argv[2] }));
  ' "$TEST_CODEX_HOME/auth.json" "$key"
  cat > "$TEST_CODEX_HOME/config.toml" <<EOF
model_provider = "custom"

[model_providers.custom]
base_url = "$base_url"
wire_api = "responses"
EOF
}

KEY_ONE="test-key-${RANDOM}-${RANDOM}"
KEY_TWO="test-key-${RANDOM}-${RANDOM}"
URL_ONE="https://provider-one.example/v1"
URL_TWO="https://provider-two.example/api/v1"

cat > "$TEST_HOME/.zshrc" <<'EOF'
export PATH="$HOME/bin:$PATH"
# CC-Switch Codex provider credentials (stored in macOS Keychain).
export OPENAI_API_KEY="$(security find-generic-password -a "$USER" -s 'CC_SWITCH_CODEX_API_KEY' -w 2>/dev/null)"
export OPENAI_BASE_URL="$(security find-generic-password -a "$USER" -s 'CC_SWITCH_CODEX_BASE_URL' -w 2>/dev/null)"
EOF

write_active_config "$KEY_ONE" "$URL_ONE"
first_output="$(run_sync)"

assert_eq "$(cat "$FAKE_KEYCHAIN_DIR/CC_SWITCH_CODEX_API_KEY")" "$KEY_ONE" "first key sync"
assert_eq "$(cat "$FAKE_KEYCHAIN_DIR/CC_SWITCH_CODEX_BASE_URL")" "$URL_ONE" "first URL sync"
assert_eq "$(grep -Fc '# >>> vft-kit cc-switch openai env >>>' "$TEST_HOME/.zshrc")" "1" "one start marker"
assert_eq "$(grep -Fc '# <<< vft-kit cc-switch openai env <<<' "$TEST_HOME/.zshrc")" "1" "one end marker"
! grep -Fq "$KEY_ONE" "$TEST_HOME/.zshrc" || fail "key leaked into .zshrc"
! grep -Fq "$KEY_ONE" <<< "$first_output" || fail "key leaked into stdout"
! grep -Fq '# CC-Switch Codex provider credentials (stored in macOS Keychain).' "$TEST_HOME/.zshrc" || fail "legacy block not removed"

run_sync >/dev/null
assert_eq "$(grep -Fc '# >>> vft-kit cc-switch openai env >>>' "$TEST_HOME/.zshrc")" "1" "idempotent start marker"

write_active_config "$KEY_TWO" "$URL_TWO"
second_output="$(run_sync)"
assert_eq "$(cat "$FAKE_KEYCHAIN_DIR/CC_SWITCH_CODEX_API_KEY")" "$KEY_TWO" "updated key sync"
assert_eq "$(cat "$FAKE_KEYCHAIN_DIR/CC_SWITCH_CODEX_BASE_URL")" "$URL_TWO" "updated URL sync"
! grep -Fq "$KEY_TWO" <<< "$second_output" || fail "updated key leaked into stdout"

printf '{}' > "$TEST_CODEX_HOME/auth.json"
missing_output="$(run_sync)"
grep -Fq '未找到可同步的 Codex API Key' <<< "$missing_output" || fail "missing-key warning absent"
assert_eq "$(cat "$FAKE_KEYCHAIN_DIR/CC_SWITCH_CODEX_API_KEY")" "$KEY_TWO" "missing key must not erase stored key"

DB_KEY="db-key-${RANDOM}-${RANDOM}"
DB_URL="https://provider-db.example/v1"
rm -f "$TEST_CODEX_HOME/auth.json" "$TEST_CODEX_HOME/config.toml"
mkdir -p "$TEST_HOME/.cc-switch"
sqlite3 "$TEST_HOME/.cc-switch/cc-switch.db" <<EOF
CREATE TABLE providers (
  id TEXT NOT NULL,
  app_type TEXT NOT NULL,
  settings_config TEXT NOT NULL,
  is_current INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (id, app_type)
);
CREATE TABLE provider_endpoints (
  provider_id TEXT NOT NULL,
  app_type TEXT NOT NULL,
  url TEXT NOT NULL
);
INSERT INTO providers VALUES ('active', 'codex', '{"auth":{"OPENAI_API_KEY":"$DB_KEY"}}', 1);
INSERT INTO provider_endpoints VALUES ('active', 'codex', '$DB_URL');
EOF
db_output="$(run_sync)"
assert_eq "$(cat "$FAKE_KEYCHAIN_DIR/CC_SWITCH_CODEX_API_KEY")" "$DB_KEY" "database fallback key"
assert_eq "$(cat "$FAKE_KEYCHAIN_DIR/CC_SWITCH_CODEX_BASE_URL")" "$DB_URL" "database fallback URL"
! grep -Fq "$DB_KEY" <<< "$db_output" || fail "database key leaked into stdout"

printf 'PASS: sync-cc-switch-openai-env\n'
