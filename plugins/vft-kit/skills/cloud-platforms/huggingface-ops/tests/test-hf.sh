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

expect_failure_quickly() {
  local label="$1" expected_status="$2" expected_stderr="$3"
  shift 3
  local actual_stderr actual_stdout status
  set +e
  python3 - "$TMP_ROOT/failure.stdout" "$TMP_ROOT/failure.stderr" "$@" <<'PY'
import subprocess
import sys

try:
    with open(sys.argv[1], "w") as stdout, open(sys.argv[2], "w") as stderr:
        result = subprocess.run(sys.argv[3:], stdout=stdout, stderr=stderr, timeout=3)
except subprocess.TimeoutExpired:
    sys.exit(124)
sys.exit(result.returncode)
PY
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
INVALID_CONFIG="$TMP_ROOT/invalid.json"
NONREGULAR_CONFIG="$TMP_ROOT/config-directory"
MISSING_CONFIG="$TMP_ROOT/missing.json"
FAKE_BIN="$TMP_ROOT/bin"
FAKE_PYTHON="$TMP_ROOT/python"
HF_FAKE_CAPTURE="$TMP_ROOT/sdk-token"
HF_STANDARD_TOKEN="$TMP_ROOT/standard-token"
UV_CAPTURE="$TMP_ROOT/uv-args"
mkdir -p "$CONFIG_DIR" "$NONREGULAR_CONFIG" "$FAKE_BIN" "$FAKE_PYTHON/huggingface_hub"

printf '%s\n' '{"token":"config-token","username":"vftfnn"}' > "$CONFIG"
printf '%s\n' '{"username":"vftfnn"}' > "$UNSUPPORTED_CONFIG"
printf '%s\n' '{"token":' > "$INVALID_CONFIG"

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
import os


class HfApi:
    def __init__(self, token=None):
        self.token = token
        with open(os.environ["HF_FAKE_CAPTURE"], "w") as capture:
            capture.write(token or "")

    def echo(self, value):
        return {"value": value}

    def reflect(self, payload):
        return payload

    def nested_token(self):
        return {"nested": [f"prefix-{self.token}-suffix"]}

    def token_error(self):
        raise RuntimeError(f"failed with {self.token}")

    def response_secret_fields(self):
        return {
            "token": "server-issued-token",
            "secret": {"value": "server-issued-secret"},
            "safe": "visible",
        }

    def add_space_secret(self, repo_id, key, value):
        raise RuntimeError(f"failed to update {repo_id}/{key} with {value}")

    def cyclic_result(self):
        value = {}
        value["self"] = value
        return value

    def infinite_result(self):
        value = 0
        while True:
            yield value
            value += 1

    def nan_result(self):
        return float("nan")

    def _private(self):
        return "must not be callable"
PY

cat > "$FAKE_BIN/uv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$UV_CAPTURE"
[ "$1 $2 $3 $4" = 'run --with huggingface-hub python' ] || exit 2
shift 4
exec env PYTHONPATH="$HF_BOOTSTRAP_PYTHONPATH" python3 "$@"
EOF
chmod +x "$FAKE_BIN/uv"

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
  local label="$1" output="$2"
  JSON_OUTPUT="$output" python3 - <<'PY' || fail "$label: unexpected JSON: $output"
import json
import os

value = json.loads(os.environ["JSON_OUTPUT"])
assert value == {"value": 42}
PY
}

output="$(env -u HF_TOKEN HF_FAKE_CAPTURE="$HF_FAKE_CAPTURE" PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" echo --kwargs '{"value":42}')"
assert_json_echo 'SDK config token' "$output"
[ "$(< "$HF_FAKE_CAPTURE")" = 'config-token' ] || fail 'SDK config token: constructor did not receive config token'
assert_not_contains 'SDK config token stdout' "$output" 'config-token'
assert_not_contains 'SDK config token stdout' "$output" 'env-token'

output="$(HF_TOKEN='env-token' HF_FAKE_CAPTURE="$HF_FAKE_CAPTURE" PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" echo --kwargs '{"value":42}')"
assert_json_echo 'SDK environment token precedence' "$output"
[ "$(< "$HF_FAKE_CAPTURE")" = 'env-token' ] || fail 'SDK environment token precedence: constructor did not receive environment token'
assert_not_contains 'SDK environment token stdout' "$output" 'config-token'
assert_not_contains 'SDK environment token stdout' "$output" 'env-token'

printf '%s\n' 'standard-token' > "$HF_STANDARD_TOKEN"
output="$(env -u HF_TOKEN HF_TOKEN_PATH="$HF_STANDARD_TOKEN" HF_FAKE_CAPTURE="$HF_FAKE_CAPTURE" PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" echo --kwargs '{"value":42}')"
assert_json_echo 'SDK standard token path' "$output"
[ "$(< "$HF_FAKE_CAPTURE")" = 'standard-token' ] || fail 'SDK standard token path: constructor did not receive standard token'
assert_not_contains 'SDK standard token stdout' "$output" 'standard-token'

output="$(env -u HF_TOKEN -u PYTHONPATH PATH="$FAKE_BIN:$PATH" HF_BOOTSTRAP_PYTHONPATH="$FAKE_PYTHON" HF_FAKE_CAPTURE="$HF_FAKE_CAPTURE" UV_CAPTURE="$UV_CAPTURE" python3 -S "$HF_API" --config "$CONFIG" echo --kwargs '{"value":42}')"
assert_json_echo 'SDK uv bootstrap' "$output"
[ -s "$UV_CAPTURE" ] || fail 'SDK uv bootstrap: uv was not invoked'
[ "$(< "$HF_FAKE_CAPTURE")" = 'config-token' ] || fail 'SDK uv bootstrap: constructor did not receive config token'
assert_not_contains 'SDK uv bootstrap stdout' "$output" 'config-token'

output="$(HF_TOKEN='env-token' HF_FAKE_CAPTURE="$HF_FAKE_CAPTURE" PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" nested_token)"
JSON_OUTPUT="$output" python3 - <<'PY' || fail "SDK nested token redaction: unexpected JSON: $output"
import json
import os

assert json.loads(os.environ["JSON_OUTPUT"]) == {"nested": ["prefix-[REDACTED]-suffix"]}
PY
assert_not_contains 'SDK nested token redaction' "$output" 'env-token'

output="$(HF_TOKEN='env-token' HF_FAKE_CAPTURE="$HF_FAKE_CAPTURE" PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" reflect --kwargs '{"payload":{"password":"alternate-token"}}')"
JSON_OUTPUT="$output" python3 - <<'PY' || fail "SDK kwargs token redaction: unexpected JSON: $output"
import json
import os

assert json.loads(os.environ["JSON_OUTPUT"]) == {"password": "[REDACTED]"}
PY
assert_not_contains 'SDK kwargs token redaction' "$output" 'alternate-token'

output="$(HF_TOKEN='env-token' HF_FAKE_CAPTURE="$HF_FAKE_CAPTURE" PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" reflect --kwargs '{"payload":{"secrets":{"REDIS_PASSWORD":"space-secret-value"}}}')"
JSON_OUTPUT="$output" python3 - <<'PY' || fail "SDK secrets mapping redaction: unexpected JSON: $output"
import json
import os

assert json.loads(os.environ["JSON_OUTPUT"]) == {"secrets": "[REDACTED]"}
PY
assert_not_contains 'SDK secrets mapping redaction' "$output" 'space-secret-value'

output="$(HF_TOKEN='env-token' HF_FAKE_CAPTURE="$HF_FAKE_CAPTURE" PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" response_secret_fields)"
JSON_OUTPUT="$output" python3 - <<'PY' || fail "SDK response field redaction: unexpected JSON: $output"
import json
import os

assert json.loads(os.environ["JSON_OUTPUT"]) == {
    "token": "[REDACTED]",
    "secret": "[REDACTED]",
    "safe": "visible",
}
PY
assert_not_contains 'SDK response token field redaction' "$output" 'server-issued-token'
assert_not_contains 'SDK response secret field redaction' "$output" 'server-issued-secret'

expect_failure 'SDK private method' 1 'method must be public' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" _private
expect_failure 'SDK missing method' 1 'HfApi method not found: does_not_exist' \
  env -u HF_TOKEN HF_FAKE_CAPTURE="$HF_FAKE_CAPTURE" PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" does_not_exist
expect_failure 'SDK non-object kwargs' 1 '--kwargs must be a JSON object' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" echo --kwargs '[]'
expect_failure 'SDK credential kwargs' 1 'credential kwargs are not allowed: token' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" echo --kwargs '{"value":42,"token":"alternate-token"}'
assert_not_contains 'SDK credential kwargs stderr' "$(< "$TMP_ROOT/failure.stderr")" 'alternate-token'
expect_failure 'SDK NaN kwargs' 1 '--kwargs must be valid JSON' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" echo --kwargs '{"value":NaN}'
expect_failure 'SDK Infinity kwargs' 1 '--kwargs must be valid JSON' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" echo --kwargs '{"value":Infinity}'
expect_failure 'SDK missing config' 1 "config file not found: $MISSING_CONFIG" \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$MISSING_CONFIG" echo --kwargs '{"value":42}'
expect_failure 'SDK invalid config JSON' 1 "invalid config JSON: $INVALID_CONFIG" \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$INVALID_CONFIG" echo --kwargs '{"value":42}'
expect_failure 'SDK non-regular config' 1 "cannot read config file: $NONREGULAR_CONFIG" \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$NONREGULAR_CONFIG" echo --kwargs '{"value":42}'
expect_failure 'SDK unsupported config' 1 'config has no supported token field' \
  env -u HF_TOKEN PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$UNSUPPORTED_CONFIG" echo --kwargs '{"value":42}'
expect_failure 'SDK exception token redaction' 1 'failed with [REDACTED]' \
  env HF_TOKEN='env-token' HF_FAKE_CAPTURE="$HF_FAKE_CAPTURE" PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" token_error
assert_not_contains 'SDK exception token redaction' "$(< "$TMP_ROOT/failure.stderr")" 'env-token'
expect_failure 'SDK Space secret value redaction' 1 'failed to update vftfnn/wfly-spring/REDIS_PASSWORD with [REDACTED]' \
  env HF_TOKEN='env-token' HF_FAKE_CAPTURE="$HF_FAKE_CAPTURE" PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" add_space_secret --kwargs '{"repo_id":"vftfnn/wfly-spring","key":"REDIS_PASSWORD","value":"space-secret-value"}'
assert_not_contains 'SDK Space secret value redaction' "$(< "$TMP_ROOT/failure.stderr")" 'space-secret-value'
expect_failure 'SDK cyclic result' 1 'result contains a cycle' \
  env -u HF_TOKEN HF_FAKE_CAPTURE="$HF_FAKE_CAPTURE" PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" cyclic_result
expect_failure_quickly 'SDK infinite result' 1 'result exceeds serialization limit' \
  env -u HF_TOKEN HF_FAKE_CAPTURE="$HF_FAKE_CAPTURE" PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" infinite_result
expect_failure 'SDK NaN result' 1 'result contains non-finite float' \
  env -u HF_TOKEN HF_FAKE_CAPTURE="$HF_FAKE_CAPTURE" PYTHONPATH="$FAKE_PYTHON" python3 "$HF_API" --config "$CONFIG" nan_result
expect_failure 'SDK uv recursion guard' 1 'huggingface_hub import failed after uv bootstrap' \
  env -u HF_TOKEN -u PYTHONPATH HF_API_UV_BOOTSTRAPPED=1 python3 -S "$HF_API" --config "$CONFIG" echo --kwargs '{"value":42}'

printf 'PASS: huggingface-ops\n'
