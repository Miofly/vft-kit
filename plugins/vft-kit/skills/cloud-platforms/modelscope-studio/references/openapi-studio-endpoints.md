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
