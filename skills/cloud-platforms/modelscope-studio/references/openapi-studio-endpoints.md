# Studios OpenAPI Endpoint Reference

Base URL: `$MODELSCOPE_ENDPOINT/openapi/v1`

Authentication: `Authorization: Bearer $MODELSCOPE_API_KEY`

## Create a Studio

```bash
curl -X POST "$MODELSCOPE_ENDPOINT/openapi/v1/studios" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "owner": "username",
    "repo_name": "my-app",
    "sdk_type": "gradio",
    "display_name": "My Application",
    "description": "Application description",
    "visibility": "private",
    "hardware": "platform/2v-cpu-16g-mem",
    "base_image": "ubuntu22.04-py311-torch2.9.1-modelscope1.35.0",
    "sdk_version": "6.2.0"
  }'
```

### sdk_type values

| Value | Description | Entry file |
|-----|------|----------|
| `gradio` | Gradio app | `app.py` |
| `streamlit` | Streamlit app | `app.py` |
| `docker` | Docker container | `Dockerfile` |
| `static` | Static website | `index.html` |

## Query available configuration

These endpoints are used to dynamically select configuration before creating or updating a Studio, avoiding hardcoding stale values.

```bash
# Hardware configuration; sdk_type is optional, and for an existing Studio you can append studio=owner/repo_name
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/hardware?sdk_type=gradio" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"

# SDK versions; currently only sdk_type=gradio returns a Gradio version list
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/sdk-versions?sdk_type=gradio" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"

# Base images
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/base-images" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"
```

When using the returned values: `hardware` takes the hardware item's `name` (the paid-resource format is `paid/<InstanceType>`), `sdk_version` takes the SDK version item's `version`, and `base_image` takes the base image item's `name`.

**Paid-resource authorization requirement:** If `hardware` uses `paid/<InstanceType>` or the returned hardware item has `resource_type=paid`, charges will be incurred against the Alibaba Cloud account bound to the user's ModelScope account. You must first explain the cost risk to the user and obtain explicit authorization before you can create, update settings, or redeploy.

## Get Studio details

```bash
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/{owner}/{repo_name}" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"
```

## Deploy/restart a Studio

```bash
curl -X POST "$MODELSCOPE_ENDPOINT/openapi/v1/studios/{owner}/{repo_name}/deploy" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"
```

## Stop a Studio

```bash
curl -X POST "$MODELSCOPE_ENDPOINT/openapi/v1/studios/{owner}/{repo_name}/stop" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"
```

## Get run logs

```bash
# Run logs
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/{owner}/{repo_name}/logs/run" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"

# Build logs (Docker type)
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/{owner}/{repo_name}/logs/build" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"
```

## Update settings

```bash
curl -X PATCH "$MODELSCOPE_ENDPOINT/openapi/v1/studios/{owner}/{repo_name}/settings" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "sdk_type": "gradio",
    "visibility": "public",
    "sdk_version": "6.2.0",
    "base_image": "ubuntu22.04-py311-torch2.9.1-modelscope1.35.0",
    "hardware": "platform/2v-cpu-16g-mem"
  }'
```

Changes to `sdk_type`, `sdk_version`, `base_image`, and `hardware` require a redeploy to take effect. `private` is deprecated; OpenAPI prefers `visibility`: `public`, `protected`, `private`.

## Plaintext variables (Variables)

Plaintext variables return both key and value, and are only for non-sensitive configuration. Use secrets for sensitive information.

```bash
# List
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/{owner}/{repo_name}/variables" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"

# Add
curl -X POST "$MODELSCOPE_ENDPOINT/openapi/v1/studios/{owner}/{repo_name}/variables" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key": "GRADIO_TEMP_DIR", "value": "/tmp/gradio"}'

# Update
curl -X PUT "$MODELSCOPE_ENDPOINT/openapi/v1/studios/{owner}/{repo_name}/variables" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key": "GRADIO_TEMP_DIR", "value": "/mnt/workspace/tmp"}'

# Delete (put key in the body, not as a path parameter)
curl -X DELETE "$MODELSCOPE_ENDPOINT/openapi/v1/studios/{owner}/{repo_name}/variables" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key": "GRADIO_TEMP_DIR"}'
```

## Secrets (Secrets)

The secrets list returns only keys, not values, and is used for sensitive information such as API keys, tokens, and passwords.

```bash
# List
curl "$MODELSCOPE_ENDPOINT/openapi/v1/studios/{owner}/{repo_name}/secrets" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY"

# Add
curl -X POST "$MODELSCOPE_ENDPOINT/openapi/v1/studios/{owner}/{repo_name}/secrets" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key": "API_KEY", "value": "sk-xxx"}'

# Update
curl -X PUT "$MODELSCOPE_ENDPOINT/openapi/v1/studios/{owner}/{repo_name}/secrets" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key": "API_KEY", "value": "new-value"}'

# Delete (put key in the body, not as a path parameter)
curl -X DELETE "$MODELSCOPE_ENDPOINT/openapi/v1/studios/{owner}/{repo_name}/secrets" \
  -H "Authorization: Bearer $MODELSCOPE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key": "API_KEY"}'
```

> ⚠️ Deleting either plaintext variables or secrets uses `DELETE .../variables` or `DELETE .../secrets` + body `{"key": "..."}`.
> The path form `DELETE .../{key}` returns 404 and is a no-op.

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
