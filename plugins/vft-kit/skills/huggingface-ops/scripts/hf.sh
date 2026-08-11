#!/usr/bin/env bash
set -euo pipefail

config=''
config_supplied=false
forward=()

while (($#)); do
  case "$1" in
    --)
      shift
      forward+=("$@")
      break
      ;;
    --config)
      if (($# < 2)); then
        printf '%s\n' '--config requires a file' >&2
        exit 2
      fi
      config="$2"
      config_supplied=true
      shift 2
      ;;
    --config=*)
      config="${1#--config=}"
      config_supplied=true
      shift
      ;;
    *)
      forward+=("$1")
      shift
      ;;
  esac
done

if [[ -z ${HF_TOKEN:-} && $config_supplied == true ]]; then
  if [[ ! -f $config || ! -r $config ]]; then
    printf 'config file not found: %s\n' "$config" >&2
    exit 1
  fi

  if ! HF_TOKEN="$(python3 - "$config" <<'PY'
import json
import sys

try:
    with open(sys.argv[1]) as config_file:
        config = json.load(config_file)
except Exception:
    sys.exit(1)

if isinstance(config, dict):
    for name in ("token", "access_token", "api_token", "key"):
        value = config.get(name)
        if isinstance(value, str) and value.strip():
            print(value)
            sys.exit(0)
sys.exit(1)
PY
  )"; then
    printf '%s\n' 'config has no supported token field' >&2
    exit 1
  fi
  export HF_TOKEN
fi

if command -v hf >/dev/null 2>&1; then
  exec hf "${forward[@]}"
fi
if command -v uvx >/dev/null 2>&1; then
  exec uvx --from huggingface-hub hf "${forward[@]}"
fi

printf '%s\n' 'hf/uvx not found' >&2
exit 127
