# Studio 部署全流程（迁自 SKILL.md）

## Full Deployment Workflow

> Each step leads with OpenAPI and provides an equivalent one-line CLI command. `${owner}`/`${repo}` are the Studio's owner and name.

### Step 0: Apply optional config (if present)

If a config file was found (see Prerequisites → "Optional config"), apply it before starting:

#### 0.1 Resolve Studio Alias

If the user provided a short name (e.g., "myapp") that exists in `quick_access`:
1. Expand it to the full name: `quick_access.{alias}.full_name`
2. Also load its metadata: type, local_path, tags

**Example:**
```json
// User says: "deploy myapp"
// Config has: {"quick_access": {"myapp": {"full_name": "username/my-app"}}}
// Resolve to: owner="username", repo="my-app"
```

#### 0.2 Apply Smart Defaults

Where a step would otherwise prompt or use a built-in default, use the user's preference instead:
- `defaults.default_visibility` → for Studio creation
- `defaults.default_hardware` → for hardware selection
- `defaults.auto_push_on_deploy` → push before deploy without prompting
- `defaults.check_logs_after_deploy` → fetch logs after deployment
- `defaults.save_logs_to` → save directory for logs

#### 0.3 Prepare Workflow Pipeline

If `workflows.deploy.steps` is defined in the config, run that ordered pipeline instead of the standard deploy sequence below.

### Step 1: Check the local Git repository

```bash
[ -d .git ] && git remote -v 2>/dev/null | grep -E 'modelscope\.(cn|ai)/studios'
```

- Already has a Studio remote address → extract `owner` and `repo` from the URL, skip to Step 3
- None → continue to Step 2

### Step 2: Analyze the project and get user info

#### 2.1 Determine the SDK type

| Type | Detection condition | Entry file | Notes |
|------|----------|----------|------|
| `gradio` | `app.py` imports gradio | `app.py` | Query `sdk_version`, `base_image`, `hardware` as needed |
| `streamlit` | `app.py` uses streamlit | `app.py` | Query `base_image`, `hardware` as needed |
| `docker` | `Dockerfile` present | `Dockerfile` | Port must be 7860 |
| `static` | `index.html` present (pre-built) | `index.html` | Build step not supported; no hardware selection |

Selection advice: `static` does not support a build step and the files must already be built; use `docker` for frontend projects that need building; use `docker` when unsure.

> The `docker` type requires first completing Alibaba Cloud account binding and passing real-name verification on the ModelScope platform: https://modelscope.cn/docs/studios/docker , otherwise the image cannot be built.

#### 2.2 Get user info

```bash
curl "$MODELSCOPE_ENDPOINT/openapi/v1/users/me" -H "Authorization: Bearer $MODELSCOPE_API_KEY"
# Equivalent CLI: ms whoami
```

The `repo` is taken from the project directory name or specified by the user.

### Step 3: Create or update the Studio

Before creating or changing settings, query the available options to avoid hardcoding outdated configuration:

```bash
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/hardware?sdk_type=${sdk_type}" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/sdk-versions?sdk_type=gradio" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/base-images" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"
```

For an existing Studio, you can append `&studio=${owner}/${repo}` to the hardware query so that free resources are returned according to that Studio's available quota. When selecting `hardware`, use the returned item's `name`; the paid resource format is `paid/<InstanceType>`. When selecting a Gradio `sdk_version`, use the returned item's `version`. When selecting `base_image`, use the returned item's `name`.

**Paid-resource authorization requirement:** If you intend to set `hardware` to `paid/<InstanceType>` or the returned item has `resource_type=paid`, you must first explicitly tell the user that this will incur charges on the Alibaba Cloud account bound to their ModelScope account, and only create, update settings, or redeploy after obtaining the user's explicit authorization. Without authorization, only free resources may be selected.

Check whether it already exists:

```bash
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/${owner}/${repo}" -H "Authorization: Bearer $MODELSCOPE_API_KEY"
# Equivalent CLI: ms info ${owner}/${repo} --repo-type studio
```

**Does not exist → create** (before creating, proactively ask the user "public or private?", defaulting to private):

```bash
curl -X POST "$MODELSCOPE_ENDPOINT/openapi/v1/studios" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "owner": "'"${owner}"'",
    "repo_name": "'"${repo}"'",
    "sdk_type": "gradio",
    "visibility": "private",
    "hardware": "platform/2v-cpu-16g-mem",
    "display_name": "My App"
  }'
# Equivalent CLI: ms create ${owner}/${repo} --repo-type studio --sdk-type gradio --private
```

**Already exists → update settings as needed:**

```bash
curl -X PATCH "$MODELSCOPE_ENDPOINT/openapi/v1/studios/${owner}/${repo}/settings" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" -H "Content-Type: application/json" \
  -d '{"sdk_type": "gradio", "sdk_version": "6.2.0", "base_image": "ubuntu22.04-py311-torch2.9.1-modelscope1.35.0"}'
# Equivalent CLI: ms settings ${owner}/${repo} --repo-type studio sdk_type=gradio sdk_version=6.2.0
```

Changes to `sdk_type`, `sdk_version`, `base_image`, and `hardware` require redeployment to take effect. xGPU requires an application (https://modelscope.cn/docs/studios/xGPU).

### Step 4: Handle sensitive information

Before pushing code, scan files for hardcoded sensitive information (API keys, tokens, passwords, etc.) and change them to read from environment variables instead:

```python
# ❌ WRONG
api_key = "sk-xxxxxxxxxxxx"
# ✅ CORRECT
import os
api_key = os.environ.get("API_KEY")
```

Compile a list of variables for use in Step 6: put non-sensitive configuration in plaintext variables, and sensitive information such as API keys, tokens, and passwords in secrets.

### Step 5: Sync code to the Studio ⚠️ The only non-API step

Code sync is done via **Git**; there is no corresponding OpenAPI/CLI endpoint. The default branch is `master`; force push is prohibited.

```bash
# 1. Configure the remote repository (skip init if .git exists, skip add if the modelscope remote exists)
[ -d .git ] || git init
git remote remove modelscope 2>/dev/null || true
MS_HOST="${MODELSCOPE_ENDPOINT:-https://modelscope.cn}"; MS_HOST="${MS_HOST#https://}"   # endpoint host (defaults to modelscope.cn)
git remote add modelscope https://oauth2:${MODELSCOPE_API_KEY}@${MS_HOST}/studios/${owner}/${repo}.git

# 2. Large file handling (files over 100MB must use LFS)
git lfs install

# 3. Fetch the remote and merge
git fetch modelscope master
git merge modelscope/master --allow-unrelated-histories -m "Merge remote"
```

On merge conflicts, keep the local version:

```bash
git checkout --ours . && git add . && git commit -m "Resolve conflicts, keep local version"
```

Commit and push:

```bash
git add . && git commit -m "Deploy to ModelScope Studio"
git push -u modelscope master
```

### Step 6: Configure plaintext variables/secrets

Configure based on the list from Step 4 (API-first). Plaintext variables return both key and value and are only for non-sensitive configuration:

```bash
# List plaintext variables
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/${owner}/${repo}/variables" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"
# Add
curl -X POST "$MODELSCOPE_ENDPOINT/openapi/v1/studios/${owner}/${repo}/variables" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" -H "Content-Type: application/json" \
  -d '{"key": "GRADIO_TEMP_DIR", "value": "/tmp/gradio"}'
# Update
curl -X PUT "$MODELSCOPE_ENDPOINT/openapi/v1/studios/${owner}/${repo}/variables" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" -H "Content-Type: application/json" \
  -d '{"key": "GRADIO_TEMP_DIR", "value": "/mnt/workspace/tmp"}'
# Delete
curl -X DELETE "$MODELSCOPE_ENDPOINT/openapi/v1/studios/${owner}/${repo}/variables" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" -H "Content-Type: application/json" \
  -d '{"key": "GRADIO_TEMP_DIR"}'
```

Secrets do not return the value and are used for sensitive information such as API keys, tokens, and passwords:

```bash
# List secrets (returns key only)
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/${owner}/${repo}/secrets" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"
# Add
curl -X POST "$MODELSCOPE_ENDPOINT/openapi/v1/studios/${owner}/${repo}/secrets" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" -H "Content-Type: application/json" \
  -d '{"key": "API_KEY", "value": "sk-xxx"}'
# Update
curl -X PUT "$MODELSCOPE_ENDPOINT/openapi/v1/studios/${owner}/${repo}/secrets" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" -H "Content-Type: application/json" \
  -d '{"key": "API_KEY", "value": "new-value"}'
# Delete
curl -X DELETE "$MODELSCOPE_ENDPOINT/openapi/v1/studios/${owner}/${repo}/secrets" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" -H "Content-Type: application/json" \
  -d '{"key": "API_KEY"}'
# Equivalent CLI (secrets only): ms secret {list,add,update,delete} ${owner}/${repo}
```

> ⚠️ To delete a plaintext variable or a secret, use `DELETE .../variables` or `DELETE .../secrets` and pass `{"key":"..."}` in the **body**, not the `DELETE .../{key}` path form.

#### Quick Reference: Batch Update Secrets

For updating multiple secrets at once (e.g., switching Redis/database endpoints across multiple Studios), use Python with PUT-fallback-POST logic:

```python
import json, urllib.request

# Secrets to update
SECRETS = {
    "REDIS_HOST": "new-redis-host.example.com",
    "REDIS_PORT": "6379",
    "REDIS_PASSWORD": "new-password",
    "REDIS_SSL_ENABLED": "true",
}

# Studios to update
STUDIOS = [
    {"owner": "user1", "repo": "studio1"},
    {"owner": "user2", "repo": "studio2"},
]

def call(method, url, token, body):
    req = urllib.request.Request(url, method=method,
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")

# Read token from .secrets/modelscope/<account>.json
token = json.load(open("/path/to/.secrets/modelscope/account.json"))["api_key"]
ep = "https://modelscope.cn"

for studio in STUDIOS:
    repo = f"{studio['owner']}/{studio['repo']}"
    base = f"{ep}/openapi/v1/studios/{repo}/secrets"
    print(f"\n===== {repo} =====")
    
    for key, value in SECRETS.items():
        # Try PUT first (update existing), fallback to POST (create new)
        st, rb = call("PUT", base, token, {"key": key, "value": value})
        ok = st == 200 and str(rb.get("Code", rb.get("code", 200))) in ("200", "0")
        
        if not ok:  # 404 means key doesn't exist, use POST
            st, rb = call("POST", base, token, {"key": key, "value": value})
            ok = st == 200
        
        print(f"  {'✅' if ok else '❌'} {key:20s} http={st}")
```

**Common scenarios:**

1. **Switch Redis/database** — update `*_HOST`, `*_PORT`, `*_PASSWORD`, `*_SSL_ENABLED` across all Studios, then redeploy each with `POST .../deploy`
2. **Rotate API keys** — update `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` etc., no redeploy needed (most apps read env on each request)
3. **Add new secrets** — batch-add `NEW_FEATURE_TOKEN` to multiple Studios; PUT returns 404 → POST creates it

**After updating secrets:** Changes take effect **only after container restart**. Trigger with `POST .../deploy` for each Studio.

### Step 7: Deploy the Studio

```bash
curl -X POST "$MODELSCOPE_ENDPOINT/openapi/v1/studios/${owner}/${repo}/deploy" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"
# Equivalent CLI: ms deploy ${owner}/${repo} --repo-type studio
```

### Step 8: Monitor status and logs

```bash
# Run logs
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/${owner}/${repo}/logs/run" -H "Authorization: Bearer $MODELSCOPE_API_KEY"
# Build logs (Docker type)
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/${owner}/${repo}/logs/build" -H "Authorization: Bearer $MODELSCOPE_API_KEY"
# Equivalent CLI: ms logs ${owner}/${repo} --log-type run|build
```

View logs by SDK type:

- `docker`: check `build` first, then check `run` after the build completes
- Other types: check `run` directly

Keep alternating between them until `Running` or an error is found.

### Step 9: Automatic diagnosis and repair

**Common errors:**

| Error signature | Fix |
|----------|----------|
| `ModuleNotFoundError` | Add to requirements.txt |
| `SyntaxError` | Fix the code syntax |
| `MemoryError` | Suggest optimizing memory usage or upgrading the hardware configuration; if switching to a paid resource is needed, first obtain explicit authorization per Step 3 |
| `Permission denied` | Check file permissions |
| Empty variable | Check Step 6 |

**Docker-specific errors:**

| Error signature | Fix |
|----------|----------|
| Port issue / `Address already in use` | Ensure it listens on `0.0.0.0:7860`, not 8080 |
| `COPY failed` | Check the Dockerfile file paths |
| `RUN` step fails | Check the dependency installation commands |
| Image pull failure | Check the FROM base image address |

Repair flow: analyze logs → modify code → `git push` → `POST .../deploy` (or `ms deploy`) → check logs again

### Step 10: Complete the deployment

Provide the Studio URL: `$MODELSCOPE_ENDPOINT/studios/${owner}/${repo}`

> If the Studio is private, prompt the user: "Deployment succeeded and it is currently private. Would you like to make it public?" After confirmation, `PATCH .../settings` with `{"visibility": "public"}` (or `ms settings ${owner}/${repo} --repo-type studio private=false`).
