# 前置条件、可选个性化配置与 MCP 接入（迁自 SKILL.md）

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
