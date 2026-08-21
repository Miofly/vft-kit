# Hugging Face Ops Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a public `vft-kit:huggingface-ops` skill that safely exposes the complete official Hugging Face CLI and SDK surface using externally supplied credentials.

**Architecture:** A Bash launcher resolves credentials and forwards every remaining argument unchanged to the official `hf` CLI, preserving future CLI additions. A small Python launcher calls public `huggingface_hub.HfApi` methods for SDK-only operations; both use official packages and keep private token paths outside `vft-kit`.

**Tech Stack:** Bash 3.2+, Python 3, official `huggingface_hub`, `uv`/`uvx`, shell regression tests.

---

### Task 1: Baseline and scaffold

**Files:**
- Create: `plugins/vft-kit/skills/cloud-platforms/huggingface-ops/SKILL.md`
- Create: `plugins/vft-kit/skills/cloud-platforms/huggingface-ops/agents/openai.yaml`
- Create: `plugins/vft-kit/skills/cloud-platforms/huggingface-ops/scripts/`

- [ ] **Step 1: Run a baseline scenario without the skill**

Ask a fresh agent to operate a Space variable using a JSON token file while requiring that the token never appears in argv or output. Record whether it invents private paths, reimplements the API, or leaks the token.

- [ ] **Step 2: Initialize the skill**

Run:

```bash
python3 /Users/wfly/.codex/skills/.system/skill-creator/scripts/init_skill.py \
  huggingface-ops \
  --path plugins/vft-kit/skills \
  --resources scripts \
  --interface 'display_name=Hugging Face Ops' \
  --interface 'short_description=管理 Hugging Face Hub、Space、仓库与计算资源' \
  --interface 'default_prompt=使用 $huggingface-ops 检查并操作 Hugging Face 资源。'
```

Expected: `plugins/vft-kit/skills/cloud-platforms/huggingface-ops/` contains `SKILL.md`, `agents/openai.yaml`, and `scripts/`.

- [ ] **Step 3: Commit the scaffold**

```bash
git add plugins/vft-kit/skills/cloud-platforms/huggingface-ops
git commit -m "feat: scaffold huggingface ops skill"
```

### Task 2: RED tests for credential handling and forwarding

**Files:**
- Create: `plugins/vft-kit/skills/cloud-platforms/huggingface-ops/tests/test-hf.sh`
- Test: `plugins/vft-kit/skills/cloud-platforms/huggingface-ops/tests/test-hf.sh`

- [ ] **Step 1: Write the failing shell test**

The test must create a temporary fake `hf` binary and fake `huggingface_hub` module, then assert:

```bash
# CLI launcher requirements
HF_TOKEN=env-token bash "$HF_SH" --config "$CONFIG" spaces list
# output contains token=env-token and args=spaces list
# output does not contain --config, the config path, or config-token

env -u HF_TOKEN PATH="$FAKE_BIN:$PATH" bash "$HF_SH" --config "$CONFIG" repos list
# output contains token=config-token and args=repos list

# SDK launcher requirements
PYTHONPATH="$FAKE_PY" python3 "$HF_API" --config "$CONFIG" echo --kwargs '{"value":42}'
# JSON output contains method result and config-token is passed only as HfApi(token=...)
```

The fake commands use only synthetic tokens. The test also checks missing config, private method names, and non-object `--kwargs` fail with clear errors.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
bash plugins/vft-kit/skills/cloud-platforms/huggingface-ops/tests/test-hf.sh
```

Expected: FAIL because `scripts/hf.sh` and `scripts/hf-api.py` do not exist.

- [ ] **Step 3: Commit the failing test**

```bash
git add plugins/vft-kit/skills/cloud-platforms/huggingface-ops/tests/test-hf.sh
git commit -m "test: define huggingface ops launchers"
```

### Task 3: GREEN official CLI launcher

**Files:**
- Create: `plugins/vft-kit/skills/cloud-platforms/huggingface-ops/scripts/hf.sh`
- Test: `plugins/vft-kit/skills/cloud-platforms/huggingface-ops/tests/test-hf.sh`

- [ ] **Step 1: Implement the minimum Bash launcher**

Implement these exact behaviors:

```bash
#!/usr/bin/env bash
set -euo pipefail

config=""
forward=()
while (($#)); do
  case "$1" in
    --config) [[ $# -ge 2 ]] || { echo "--config requires a file" >&2; exit 2; }; config="$2"; shift 2 ;;
    --config=*) config="${1#*=}"; shift ;;
    --) shift; forward+=("$@"); break ;;
    *) forward+=("$1"); shift ;;
  esac
done

if [[ -z "${HF_TOKEN:-}" && -n "$config" ]]; then
  export HF_TOKEN="$(python3 - "$config" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
for key in ("token", "access_token", "api_token", "key"):
    if data.get(key):
        print(data[key], end="")
        break
else:
    raise SystemExit("config has no token field")
PY
)"
fi

if command -v hf >/dev/null 2>&1; then
  exec hf "${forward[@]}"
fi
command -v uvx >/dev/null 2>&1 || { echo "hf/uvx not found" >&2; exit 127; }
exec uvx --from huggingface-hub hf "${forward[@]}"
```

Do not add command-specific wrappers.

- [ ] **Step 2: Run syntax and regression checks**

Run:

```bash
bash -n plugins/vft-kit/skills/cloud-platforms/huggingface-ops/scripts/hf.sh
bash plugins/vft-kit/skills/cloud-platforms/huggingface-ops/tests/test-hf.sh
```

Expected: CLI assertions pass; SDK assertions still fail because `hf-api.py` is absent.

### Task 4: GREEN official SDK launcher

**Files:**
- Create: `plugins/vft-kit/skills/cloud-platforms/huggingface-ops/scripts/hf-api.py`
- Test: `plugins/vft-kit/skills/cloud-platforms/huggingface-ops/tests/test-hf.sh`

- [ ] **Step 1: Implement the minimum Python launcher**

Provide:

```python
def resolve_token(config: str | None) -> str | None:
    if os.environ.get("HF_TOKEN"):
        return os.environ["HF_TOKEN"]
    if config:
        data = json.loads(Path(config).read_text())
        return next((data[k] for k in ("token", "access_token", "api_token", "key") if data.get(k)), None)
    token_path = Path(os.environ.get("HF_TOKEN_PATH", Path(os.environ.get("HF_HOME", Path.home() / ".cache/huggingface")) / "token"))
    return token_path.read_text().strip() if token_path.is_file() else None
```

Parse `method`, `--kwargs`, and `--config`; reject method names beginning with `_`, require kwargs to decode to an object, instantiate `HfApi(token=token)`, call the named public method, and serialize dataclasses, datetimes, enums, mappings, sequences, and object dictionaries to JSON.

If `huggingface_hub` is missing, re-exec once through:

```bash
uv run --with huggingface-hub python <script> <original args>
```

- [ ] **Step 2: Run the complete regression test**

Run:

```bash
python3 -m py_compile plugins/vft-kit/skills/cloud-platforms/huggingface-ops/scripts/hf-api.py
bash plugins/vft-kit/skills/cloud-platforms/huggingface-ops/tests/test-hf.sh
```

Expected: `PASS: huggingface-ops`.

- [ ] **Step 3: Commit launchers and tests**

```bash
git add plugins/vft-kit/skills/cloud-platforms/huggingface-ops/scripts plugins/vft-kit/skills/cloud-platforms/huggingface-ops/tests
git commit -m "feat: add huggingface ops launchers"
```

### Task 5: Skill instructions and metadata

**Files:**
- Modify: `plugins/vft-kit/skills/cloud-platforms/huggingface-ops/SKILL.md`
- Modify: `plugins/vft-kit/skills/cloud-platforms/huggingface-ops/agents/openai.yaml`

- [ ] **Step 1: Replace the scaffold with concise instructions**

The frontmatter description starts with `Use when` and includes Hugging Face, Hub, models, datasets, Spaces, variables, secrets, Jobs, Endpoints, repositories, files, collections, webhooks, buckets, and runtime triggers.

The body must contain:

```markdown
1. Resolve `<skill-dir>` from the loaded skill path.
2. Use `scripts/hf.sh --config <credential.json> ...` for every official CLI command.
3. Run `scripts/hf.sh ... --help` before guessing current syntax.
4. Use `scripts/hf-api.py <method> --kwargs '<json>'` only when the CLI lacks the operation.
5. Read-only operations run directly; destructive, replacement, or billable operations require exact-target confirmation.
6. Never print tokens or secret values; secret listings expose keys and metadata only.
```

Include one compact quick-reference table for auth, models/datasets/Spaces, repository files, variables/secrets, logs/runtime, Jobs/Endpoints, collections/webhooks/buckets, and SDK fallback. Do not duplicate the official CLI reference.

- [ ] **Step 2: Validate metadata**

Run:

```bash
uv run --with pyyaml python /Users/wfly/.codex/skills/.system/skill-creator/scripts/quick_validate.py \
  plugins/vft-kit/skills/cloud-platforms/huggingface-ops
```

Expected: validation success.

- [ ] **Step 3: Forward-test the finished skill**

Give a fresh agent the skill path and ask it to inspect a Space, replace a secret, and start paid hardware in one request. It must inspect directly, request confirmation before replacement/billing, use the public launchers, and avoid exposing the token.

- [ ] **Step 4: Commit the finished skill**

```bash
git add plugins/vft-kit/skills/cloud-platforms/huggingface-ops
git commit -m "docs: add huggingface ops workflow"
```

### Task 6: Live verification and deployment

**Files:**
- Verify only: `plugins/vft-kit/skills/cloud-platforms/huggingface-ops/`

- [ ] **Step 1: Run local checks**

```bash
bash -n plugins/vft-kit/skills/cloud-platforms/huggingface-ops/scripts/hf.sh
python3 -m py_compile plugins/vft-kit/skills/cloud-platforms/huggingface-ops/scripts/hf-api.py
bash plugins/vft-kit/skills/cloud-platforms/huggingface-ops/tests/test-hf.sh
git diff --check HEAD~3..HEAD
```

Expected: syntax checks pass, test prints `PASS: huggingface-ops`, and diff check is empty.

- [ ] **Step 2: Run live read-only checks**

Use the private credential only through `--config`:

```bash
bash plugins/vft-kit/skills/cloud-platforms/huggingface-ops/scripts/hf.sh \
  --config <private-huggingface-json> auth whoami
bash plugins/vft-kit/skills/cloud-platforms/huggingface-ops/scripts/hf.sh \
  --config <private-huggingface-json> spaces list vftfnn/wfly-spring
```

Expected: authenticated user and Space file/runtime information; no token in output. Do not mutate the Space.

- [ ] **Step 3: Refresh both plugin caches**

Run the existing `vft-kit:plugin-refresh` scripts for Claude Code and Codex, then compare SHA-256 hashes of source and cached `huggingface-ops` files.

Expected: both caches contain the skill and every compared hash matches source.

- [ ] **Step 4: Confirm clean scoped status**

```bash
git status --short
```

Expected: only the pre-existing `plugins/vft-kit/skills/web-automation/web-scrape/scripts/__pycache__/` remains unrelated and untracked.
