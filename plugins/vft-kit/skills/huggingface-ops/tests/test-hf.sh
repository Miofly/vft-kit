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

assert_contains() {
  local label="$1" output="$2" expected="$3"
  grep -Fiq -- "$expected" <<< "$output" || fail "$label: expected '$expected', got: $output"
}

assert_not_contains() {
  local label="$1" output="$2" forbidden="$3"
  if grep -Fq -- "$forbidden" <<< "$output"; then
    fail "$label: output leaked or forwarded '$forbidden': $output"
  fi
}

expect_failure() {
  local label="$1" expected="$2"
  shift 2
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "$label: command unexpectedly succeeded"
  assert_contains "$label" "$output" "$expected"
  assert_not_contains "$label" "$output" 'config-token'
  assert_not_contains "$label" "$output" 'env-token'
  assert_not_contains "$label" "$output" 'Traceback'
}

CONFIG="$TMP_ROOT/config.json"
UNSUPPORTED_CONFIG="$TMP_ROOT/unsupported.json"
MISSING_CONFIG="$TMP_ROOT/missing.json"
FAKE_BIN="$TMP_ROOT/bin"
FAKE_PYTHON="$TMP_ROOT/python"
mkdir -p "$FAKE_BIN" "$FAKE_PYTHON/huggingface_hub"

printf '%s\n' '{"token":"config-token","username":"vftfnn"}' > "$CONFIG"
printf '%s\n' '{"username":"vftfnn"}' > "$UNSUPPORTED_CONFIG"

cat > "$FAKE_BIN/hf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'token=%s\n' "${HF_TOKEN-}"
printf 'args=%s\n' "$*"
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
[ -f "$HF_API" ] || fail "SDK launcher missing: $HF_API"

output="$(HF_TOKEN='env-token' PATH="$FAKE_BIN:$PATH" bash "$HF_SH" --config "$CONFIG" spaces list)"
assert_line 'CLI environment token precedence' "$output" 'token=env-token'
assert_line 'CLI strips wrapper arguments' "$output" 'args=spaces list'
assert_not_contains 'CLI strips wrapper config flag' "$output" '--config'
assert_not_contains 'CLI hides config path' "$output" "$CONFIG"
assert_not_contains 'CLI environment token precedence' "$output" 'config-token'

output="$(env -u HF_TOKEN PATH="$FAKE_BIN:$PATH" bash "$HF_SH" --config "$CONFIG" repos list)"
assert_line 'CLI config token fallback' "$output" 'token=config-token'
assert_line 'CLI config token arguments' "$output" 'args=repos list'

output="$(env -u HF_TOKEN PATH="$FAKE_BIN:$PATH" bash "$HF_SH" --config="$CONFIG" repos list)"
assert_line 'CLI equals config syntax' "$output" 'token=config-token'
assert_line 'CLI equals config arguments' "$output" 'args=repos list'

output="$(HF_TOKEN='env-token' PATH="$FAKE_BIN:$PATH" bash "$HF_SH" -- --config official-config spaces list)"
assert_line 'CLI option parsing terminator token' "$output" 'token=env-token'
assert_line 'CLI option parsing terminator arguments' "$output" 'args=--config official-config spaces list'

expect_failure 'CLI missing config' 'not found' \
  env -u HF_TOKEN PATH="$FAKE_BIN:$PATH" bash "$HF_SH" --config "$MISSING_CONFIG" repos list
expect_failure 'CLI unsupported config' 'token' \
  env -u HF_TOKEN PATH="$FAKE_BIN:$PATH" bash "$HF_SH" --config "$UNSUPPORTED_CONFIG" repos list

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

expect_failure 'SDK private method' 'private' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" _private
expect_failure 'SDK missing method' 'not found' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" does_not_exist
expect_failure 'SDK non-object kwargs' 'object' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" echo --kwargs '[]'
expect_failure 'SDK missing config' 'not found' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$MISSING_CONFIG" echo --kwargs '{"value":42}'
expect_failure 'SDK unsupported config' 'token' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$UNSUPPORTED_CONFIG" echo --kwargs '{"value":42}'

printf 'PASS: huggingface-ops\n'
