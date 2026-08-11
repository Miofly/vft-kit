#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HF_SH="$SKILL_DIR/scripts/hf.sh"
HF_API="$SKILL_DIR/scripts/hf-api.py"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_line() {
  local label="$1" output="$2" expected="$3"
  grep -Fxq -- "$expected" <<< "$output" || fail "$label: expected line '$expected', got: $output"
}

assert_not_contains() {
  local label="$1" output="$2" forbidden="$3"
  if grep -Fq -- "$forbidden" <<< "$output"; then
    fail "$label: output leaked or forwarded '$forbidden': $output"
  fi
}

expect_failure() {
  local label="$1" expected_status="$2" expected_stderr="$3"
  shift 3
  local actual_stderr actual_stdout status
  set +e
  "$@" > "$TMP_ROOT/failure.stdout" 2> "$TMP_ROOT/failure.stderr"
  status=$?
  set -e
  actual_stdout="$(< "$TMP_ROOT/failure.stdout")"
  actual_stderr="$(< "$TMP_ROOT/failure.stderr")"
  [ "$status" -eq "$expected_status" ] || fail "$label: expected status $expected_status, got $status"
  [ -z "$actual_stdout" ] || fail "$label: expected empty stdout, got: $actual_stdout"
  [ "$actual_stderr" = "$expected_stderr" ] || fail "$label: expected stderr '$expected_stderr', got: $actual_stderr"
}

CONFIG_DIR="$TMP_ROOT/config fixtures"
CONFIG="$CONFIG_DIR/hf config.json"
UNSUPPORTED_CONFIG="$TMP_ROOT/unsupported.json"
MISSING_CONFIG="$TMP_ROOT/missing.json"
FAKE_BIN="$TMP_ROOT/bin"
FAKE_PYTHON="$TMP_ROOT/python"
mkdir -p "$CONFIG_DIR" "$FAKE_BIN" "$FAKE_PYTHON/huggingface_hub"

printf '%s\n' '{"token":"config-token","username":"vftfnn"}' > "$CONFIG"
printf '%s\n' '{"username":"vftfnn"}' > "$UNSUPPORTED_CONFIG"

cat > "$FAKE_BIN/hf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'token=%s\n' "${HF_TOKEN-}"
printf 'argc=%s\n' "$#"
index=0
for arg in "$@"; do
  printf 'arg[%s]=%s\n' "$index" "$arg"
  index=$((index + 1))
done
EOF
chmod +x "$FAKE_BIN/hf"

cat > "$FAKE_PYTHON/huggingface_hub/__init__.py" <<'PY'
class HfApi:
    def __init__(self, token=None):
        self.token = token

    def echo(self, value):
        return {"token": self.token, "value": value}

    def _private(self):
        return "must not be callable"
PY

[ -f "$HF_SH" ] || fail "CLI launcher missing: $HF_SH"

output="$(HF_TOKEN='env-token' PATH="$FAKE_BIN:$PATH" bash "$HF_SH" --config "$CONFIG" spaces list --search 'two words;still-one')"
assert_line 'CLI environment token precedence' "$output" 'token=env-token'
assert_line 'CLI strips wrapper arguments' "$output" 'argc=4'
assert_line 'CLI first argument boundary' "$output" 'arg[0]=spaces'
assert_line 'CLI second argument boundary' "$output" 'arg[1]=list'
assert_line 'CLI third argument boundary' "$output" 'arg[2]=--search'
assert_line 'CLI spaced argument boundary' "$output" 'arg[3]=two words;still-one'
assert_not_contains 'CLI strips wrapper config flag' "$output" '--config'
assert_not_contains 'CLI hides config path' "$output" "$CONFIG"
assert_not_contains 'CLI environment token precedence' "$output" 'config-token'

output="$(env -u HF_TOKEN PATH="$FAKE_BIN:$PATH" bash "$HF_SH" --config "$CONFIG" repos list)"
assert_line 'CLI config token fallback' "$output" 'token=config-token'
assert_line 'CLI config token argc' "$output" 'argc=2'
assert_line 'CLI config token first argument' "$output" 'arg[0]=repos'
assert_line 'CLI config token second argument' "$output" 'arg[1]=list'

output="$(env -u HF_TOKEN PATH="$FAKE_BIN:$PATH" bash "$HF_SH" --config="$CONFIG" repos list)"
assert_line 'CLI equals config syntax' "$output" 'token=config-token'
assert_line 'CLI equals config argc' "$output" 'argc=2'
assert_line 'CLI equals config first argument' "$output" 'arg[0]=repos'
assert_line 'CLI equals config second argument' "$output" 'arg[1]=list'

output="$(HF_TOKEN='env-token' PATH="$FAKE_BIN:$PATH" bash "$HF_SH" -- --config official-config spaces list)"
assert_line 'CLI option parsing terminator token' "$output" 'token=env-token'
assert_line 'CLI option parsing terminator argc' "$output" 'argc=4'
assert_line 'CLI escaped config flag' "$output" 'arg[0]=--config'
assert_line 'CLI escaped config value' "$output" 'arg[1]=official-config'
assert_line 'CLI escaped third argument' "$output" 'arg[2]=spaces'
assert_line 'CLI escaped fourth argument' "$output" 'arg[3]=list'

output="$(HF_TOKEN='env-token' PATH="$FAKE_BIN:$PATH" bash "$HF_SH")"
assert_line 'CLI no arguments' "$output" 'argc=0'
assert_not_contains 'CLI no argument boundary' "$output" 'arg[0]'

expect_failure 'CLI missing config' 1 "config file not found: $MISSING_CONFIG" \
  env -u HF_TOKEN PATH="$FAKE_BIN:$PATH" bash "$HF_SH" --config "$MISSING_CONFIG" repos list
expect_failure 'CLI unsupported config' 1 'config has no supported token field' \
  env -u HF_TOKEN PATH="$FAKE_BIN:$PATH" bash "$HF_SH" --config "$UNSUPPORTED_CONFIG" repos list

[ -f "$HF_API" ] || fail "SDK launcher missing: $HF_API"

assert_json_echo() {
  local label="$1" output="$2" expected_token="$3"
  JSON_OUTPUT="$output" EXPECTED_TOKEN="$expected_token" python3 - <<'PY' || fail "$label: unexpected JSON: $output"
import json
import os

value = json.loads(os.environ["JSON_OUTPUT"])
assert value == {"token": os.environ["EXPECTED_TOKEN"], "value": 42}
PY
}

output="$(env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" echo --kwargs '{"value":42}')"
assert_json_echo 'SDK config token' "$output" 'config-token'

output="$(HF_TOKEN='env-token' PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" echo --kwargs '{"value":42}')"
assert_json_echo 'SDK environment token precedence' "$output" 'env-token'

expect_failure 'SDK private method' 1 'method must be public' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" _private
expect_failure 'SDK missing method' 1 'HfApi method not found: does_not_exist' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" does_not_exist
expect_failure 'SDK non-object kwargs' 1 '--kwargs must be a JSON object' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" echo --kwargs '[]'
expect_failure 'SDK missing config' 1 "config file not found: $MISSING_CONFIG" \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$MISSING_CONFIG" echo --kwargs '{"value":42}'
expect_failure 'SDK unsupported config' 1 'config has no supported token field' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$UNSUPPORTED_CONFIG" echo --kwargs '{"value":42}'

printf 'PASS: huggingface-ops\n'
