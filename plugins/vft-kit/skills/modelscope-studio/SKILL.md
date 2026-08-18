---
name: ms-studio-deploy
description: >-
  Use when the user wants to deploy, update, inspect, or repair a ModelScope Studio; manage its variables or secrets;
  or inspect, start, open, or stop a ModelScope Notebook / PAI-DSW environment. Supports Gradio, Streamlit,
  Docker, static websites, Studio OpenAPI operations, authenticated Notebook browser-session operations, persistent
  workspace file transfer, and CPU-prepare/GPU-run workflows.
  Not applicable to: Hub repository management, model/dataset operations, MCP/skill management, model training, or model evaluation.
---

# ModelScope Studio Deployment and Notebook Operations

> Studio OpenAPI verified 2026-06-29; authenticated Notebook web API verified 2026-08-18.

Deploy a local project to a ModelScope Studio. **This Skill uses OpenAPI as the source of truth**, with the `ms` CLI as an equivalent convenience alias, `modelscope_hub.HubApi` as the API-first Python client, and MCP tools as optional.

## Quick Decision Guide

```
User wants to...
│
├── Deploy a local project to a Studio
│   └── Follow the 10 steps in "Full Deployment Workflow" below
│
├── Update an already-deployed Studio
│   └── Modify code → git push → POST /studios/{o}/{r}/deploy (or ms deploy)
│
├── View Studio status/logs
│   └── GET /studios/{o}/{r}/logs/run (or ms logs --log-type run)
│
├── Manage variables
│   ├── Plaintext variables: GET/POST/PUT/DELETE /studios/{o}/{r}/variables
│   └── Secrets: GET/POST/PUT/DELETE /studios/{o}/{r}/secrets (or ms secret ...)
│
├── Inspect/start/stop a Notebook or PAI-DSW environment
│   └── Follow "Notebook / PAI-DSW" and references/notebook-dsw.md
│
└── Repository file management / model & dataset operations
    └── hand off → ms-hub
```

## Notebook / PAI-DSW

Notebook is a separate product surface from Studio. Its `/api/v1/notebooks*` endpoints require the ModelScope
web-login cookie; a valid `MODELSCOPE_API_KEY` alone returns `401 user not logged in`. Read
`references/notebook-dsw.md` completely before inspecting or changing a Notebook instance.

Default to the reference's fast API-first automation workflow. Once task scope and resource-cost authorization are
clear, carry the Notebook operation through file transfer, execution, verification, resource switching, and cleanup
without pausing between ordinary reversible steps.

Never omit, forge, replay, log, or persist `CaptchaVerify`. Starting a free instance requires the fresh value
issued by ModelScope's safety-verification widget. If a slider or other verification appears, hand the same
browser session to the user and resume only after they confirm completion.

## Personalization (optional)

This skill can read an optional per-user config file to enable conveniences like Studio aliases, personal defaults, and custom deployment pipelines. **These are entirely optional** — without a config file the skill works in standard mode, and every step below functions normally.

If a config file is present, apply it as described in "Optional config" under Prerequisites. Otherwise ignore all config-driven behavior.

## Prerequisites

### 1. MODELSCOPE_API_KEY

The entire workflow depends on this token (API authentication, Git push, variable/secret configuration); it must be confirmed first.

**Resolve the token in this priority order, using the first one found:**

```
1. Environment variable (highest priority)
   echo $MODELSCOPE_API_KEY

2. Git remote (if already configured)
   git remote -v | grep -E 'modelscope\.(cn|ai)'

3. A local config file (see "Optional config" below)
```

**First-time setup:** Copy `config.example.json` from this skill directory to a location of your choice and fill in your token:

```json
{
  "api_key": "your-token-here",
  "endpoint": "https://modelscope.cn",
  "default_owner": "your-username"
}
```

If none of the above are found, guide the user:
1. Visit $MODELSCOPE_ENDPOINT/my/myaccesstoken to obtain a token
2. Choose one of the configuration methods above

> **Site routing:** this skill targets whichever site `$MODELSCOPE_ENDPOINT` points to (default domestic `https://modelscope.cn`; international `https://www.modelscope.ai`). Export `MODELSCOPE_ENDPOINT` plus a **site-scoped** token before deploying — the OpenAPI base and the git remote host below both derive from it. Full guidance: ms-hub → "Site selection & endpoint routing".

### 2. Runtime Environment

```bash
pip install modelscope          # Also provides the OpenAPI/SDK and the ms CLI
```

OpenAPI basic conventions:

| Item | Value |
|------|-----|
| **Base URL** | `$MODELSCOPE_ENDPOINT/openapi/v1` (default `https://modelscope.cn`) |
| **Authentication** | `Authorization: Bearer $MODELSCOPE_API_KEY` |
| **Success response** | `{"success": true, "data": {...}, "request_id": "..."}` |
| **Default branch** | `master` (not main) |

### 3. Git Environment

Studio code is synced via Git; ensure Git is installed and user information is configured.

### 4. Optional config

The token config file (Prerequisite 1) may also carry optional personalization. If such a file exists, load it and apply any keys present; if not, skip this entirely and use standard behavior.

Recognized optional keys:
- `quick_access` — a map of alias → `{ full_name, type }`. When the user refers to a Studio by a short alias, expand it to `full_name`.
- `defaults` — personal defaults (e.g. `default_visibility`, `default_hardware`, `auto_push_on_deploy`, `check_logs_after_deploy`, `save_logs_to`). Apply these where the corresponding step would otherwise prompt or use a built-in default.
- `workflows.deploy.steps` — a custom ordered pipeline to run instead of the standard deploy sequence.
- `failover` — a hot-standby group of two or more Studios that back each other up. See "Failover groups" below.

#### Failover groups (optional)

Some setups run two Studios as a hot-standby pair behind a router/proxy: both exist, but only one serves live traffic at a time, and traffic can switch between them. The `failover` key describes such a group so that, when the user asks "which one is primary / which is the backup / which is live right now", the skill can answer from a **runtime source of truth** instead of guessing.

Shape:
```json
{
  "failover": {
    "members": [
      { "role": "primary", "full_name": "owner-a/repo-a", "upstream": "https://a.example" },
      { "role": "backup",  "full_name": "owner-b/repo-b", "upstream": "https://b.example" }
    ],
    "active_probe": {
      "url": "https://router.example/health",
      "active_field": "upstream"
    }
  }
}
```

How to answer a "which is primary/backup/live" question:
1. `role` is the **fixed** designation of each member (primary vs backup) — read it straight from config.
2. **Currently-serving** is **dynamic**. GET `active_probe.url`, read the JSON field named by `active_probe.active_field`, and match its value against each member's `upstream`. The member whose `upstream` matches is the one **currently serving live traffic**; the others are on standby.
3. Report **both dimensions**: each member's fixed role AND whether it is currently live. Do not conflate "primary" (role) with "live" (current state) — after a failover the backup can be the one serving while the primary stands by.

If the probe is unreachable, say so and fall back to reporting only the fixed roles from config.

The file location is chosen by the user (e.g. `~/.config/modelscope-studio/config.json`, or a project-local path). Check the common locations, or wherever the user points you.

## Operations Overview: OpenAPI (source of truth) ↔ CLI ↔ Python

| Operation | OpenAPI (source of truth) | ms CLI (equivalent alias) | `modelscope_hub.HubApi` (Python) | MCP tool (optional) |
|------|---------------------|---------------------|-----------------------------------|------------------|
| User info | `GET /users/me` | `ms whoami` | `api.whoami()` | `getCurrentUser` |
| Create Studio | `POST /studios` | `ms create o/r --repo-type studio` | `api.create_repo("o/r", repo_type="studio", ...)` | `createStudio` |
| Get details | `GET /studios/{o}/{r}` | `ms info o/r --repo-type studio` | `api.get_repo("o/r", repo_type="studio")` | `getStudio` |
| Deploy/restart | `POST /studios/{o}/{r}/deploy` | `ms deploy o/r --repo-type studio` | `api.deploy_repo("o/r")` | `deployStudio` |
| Stop | `POST /studios/{o}/{r}/stop` | `ms stop o/r --repo-type studio` | `api.stop_repo("o/r")` | `stopStudio` |
| Logs | `GET /studios/{o}/{r}/logs/{run\|build}` | `ms logs o/r --log-type run` | `api.get_repo_logs("o/r", log_type="run")` | `getStudioLogs` |
| Update settings | `PATCH /studios/{o}/{r}/settings` | `ms settings o/r --repo-type studio k=v` | `api.update_repo_settings("o/r","studio",**kw)` | `updateStudioSettings` |
| Query available hardware | `GET /studios/hardware?sdk_type=gradio[&studio=o/r]` | none | none | `listHardware` |
| Query SDK versions | `GET /studios/sdk-versions?sdk_type=gradio` | none | none | `listSdkVersions` |
| Query base images | `GET /studios/base-images` | none | none | `listBaseImages` |
| List plaintext variables | `GET /studios/{o}/{r}/variables` | none | none | `listStudioVariables` |
| Add plaintext variable | `POST /studios/{o}/{r}/variables` | none | none | `addStudioVariable` |
| Update plaintext variable | `PUT /studios/{o}/{r}/variables` | none | none | `updateStudioVariable` |
| Delete plaintext variable | `DELETE /studios/{o}/{r}/variables` | none | none | `deleteStudioVariable` |
| List secrets | `GET /studios/{o}/{r}/secrets` | `ms secret list o/r` | `api.list_secrets("o/r")` | `listStudioSecrets` |
| Add secret | `POST /studios/{o}/{r}/secrets` | `ms secret add o/r K V` | `api.add_secret("o/r","K","V")` | `addStudioSecret` |
| Update secret | `PUT /studios/{o}/{r}/secrets` | `ms secret update o/r K V` | `api.update_secret("o/r","K","V")` | `updateStudioSecret` |
| Delete secret | `DELETE /studios/{o}/{r}/secrets` | `ms secret delete o/r K` | `api.delete_secret("o/r","K")` | `deleteStudioSecret` |

> **`HubApi` is the same engine that drives the `ms` CLI** and is the API-first Python entry point:
> ```python
> from modelscope_hub import HubApi
> api = HubApi(); api.login("$MODELSCOPE_API_KEY")
> ```
> Note it is a different pair of classes from the legacy `modelscope.hub.api.HubApi`: the legacy version has not yet wired up Studio methods such as deploy/stop, whereas **the new `modelscope_hub.HubApi` has** (its `deploy_repo`/`stop_repo`/`get_repo_logs`/secret series default to `repo_type="studio"`).

> **MCP tools (optional)** — the last column of the table above lists the equivalent tools provided by the `studio-mcp` service, with the same semantics as the OpenAPI call in the same row; when the agent has this service configured it can be called directly, and when it is not configured this column can be ignored. See the appendix at the end for first-time setup.

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

## Docker Studio Reference

For applications that go beyond the scope of Gradio/Streamlit, such as FastAPI, Golang, and Node.js.
Prerequisite: you must complete Alibaba Cloud account binding and pass real-name verification on the ModelScope platform; see https://modelscope.cn/docs/studios/docker for details. See `references/docker-templates.md` for details.

**Key requirements:**

- The port must expose `0.0.0.0:7860`; using `8080` is prohibited (occupied by the platform)
- HTTP headers must not use `Authorization`, `X-modelscope-*`, or `X-studio-*`

## Data Persistence

- By default, data is lost on every restart
- Persistence directory: `/mnt/workspace`
- Data is still lost when transferring/renaming a Studio
- For high-reliability needs, use external storage (OSS, databases)

## Notes

1. The default branch is `master`; force push is prohibited
2. Files over 100MB must use Git LFS
3. The first Docker build takes about 3-5 minutes; other types start faster
4. Free quotas have time limits
5. Switching to paid hardware resources will incur charges on the Alibaba Cloud account bound to the user's ModelScope account; the user's explicit authorization must be obtained first
6. Hardcoding sensitive information in code is prohibited; it must be injected via secrets; non-sensitive configuration may use plaintext variables
7. A Studio **cannot be deleted through a programmatic interface**: OpenAPI `DELETE /openapi/v1/studios/{id}` returns 404; the SDK/CLI `delete_repo` is deprecated and does not support studio. Deletion is only possible via the web console at https://modelscope.cn (which uses a cookie-authenticated internal interface; a Bearer token call returns 401). Programmatically, you can only stop (`stop`).

## Reference Documentation

Consult when you run into problems or need more detail:

- `references/openapi-studio-endpoints.md` — detailed Studios OpenAPI endpoint parameters (source-of-truth specification)
- `references/notebook-dsw.md` — authenticated Notebook / PAI-DSW endpoints, start payload, states, and captcha boundary
- `references/docker-templates.md` — Dockerfile templates for the Docker type (FastAPI, Node.js, Golang, etc.)
- `references/troubleshooting.md` — deployment-failure troubleshooting process, common errors, and fixes

<details>
<summary>Appendix: MCP tools first-time setup (optional)</summary>

#### Query existing deployment links

```bash
curl -s "$MODELSCOPE_ENDPOINT/openapi/v1/mcp/servers/maasadmin/studio-mcp?get_operational_url=true" \
  -H "Authorization: Bearer ${MODELSCOPE_API_KEY}"
```

Check `data.operational_urls` in the returned JSON; if there is an entry with `accessible: true`, extract its `url`.

#### Deploy the MCP service (when no link is available)

```bash
ms mcp deploy maasadmin/studio-mcp --transport-type streamable_http
```

> The `transport_type` for MCP deploy is required, with valid values `sse` / `streamable_http`; see the MCP section of ms-hub for details.

#### Write the local MCP configuration (Cursor `.cursor/mcp.json`)

```json
{
  "mcpServers": {
    "modelscope-studio": {
      "type": "streamable_http",
      "url": "<deployment URL>",
      "name": "modelscope-studio"
    }
  }
}
```

For other clients, add a Streamable HTTP type MCP service per their respective documentation, using the same URL. After configuration, call the MCP tool `getCurrentUser` to verify the connection.

</details>

## Related Skills

- Hub repository management / models & datasets / MCP / skill management → ms-hub
