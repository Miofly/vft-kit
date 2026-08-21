# vercel-ops

Universal Vercel API operations CLI - Zero dependencies, multi-profile support.

## Quick Start

```bash
# 1. Set your token
export VERCEL_TOKEN=your-token-here

# 2. Verify token
node scripts/vercel-ops.js verify

# 3. List projects
node scripts/vercel-ops.js projects list

# 4. Create deployment
node scripts/vercel-ops.js deployments create my-project --target production
```

## Installation

### Option 1: Direct Use (No Installation)

```bash
# Download the script
curl -O https://raw.githubusercontent.com/your-repo/vercel-ops/main/scripts/vercel-ops.js

# Make executable
chmod +x vercel-ops.js

# Run
./vercel-ops.js projects list
```

### Option 2: Global Alias

```bash
# Add to ~/.bashrc or ~/.zshrc
alias vercel-ops="node /path/to/vercel-ops.js"

# Use
vercel-ops projects list
```

### Option 3: npm Script

```json
{
  "scripts": {
    "vercel": "node scripts/vercel-ops.js"
  }
}
```

```bash
npm run vercel -- projects list
```

## Configuration

### Environment Variable (Recommended)

```bash
export VERCEL_TOKEN=vcp_your_token_here
```

### Config File

Create `~/.config/vercel/config.json`:

```json
{
  "default": {
    "access_token": "vcp_xxx",
    "team_id": "team_xxx",
    "team_slug": "my-team"
  }
}
```

Or use project-level config: `./vercel-config.json`

### Multiple Profiles

```json
{
  "personal": {
    "access_token": "vcp_personal_xxx",
    "team_id": null
  },
  "work": {
    "access_token": "vcp_work_xxx",
    "team_id": "team_work_xxx"
  }
}
```

```bash
node vercel-ops.js --profile personal projects list
node vercel-ops.js --profile work projects list
```

## Features

- ✅ **Zero Dependencies** - Pure Node.js 18+
- ✅ **Multi-Profile** - Manage multiple accounts
- ✅ **Full API Coverage** - All major Vercel endpoints
- ✅ **Auto Retry** - Automatic retry with exponential backoff
- ✅ **Rate Limit Handling** - Built-in 429 handling
- ✅ **JSON Output** - Machine-readable output with `--json`
- ✅ **Verbose Mode** - Debug with `--verbose`

## Commands

| Command | Description |
|---------|-------------|
| `verify` | Verify token and show account info |
| `projects` | Manage projects (list, get, create, update, delete, link) |
| `deployments` | Manage deployments (list, get, create, cancel, redeploy, delete) |
| `domains` | Manage domains (list, add, verify, remove, get) |
| `env` | Manage environment variables (list, add, update, remove, import) |
| `logs` | Query deployment logs (get, follow) |
| `aliases` | Manage aliases (list, assign, remove) |
| `teams` | Manage teams (list, get, members, invite) |
| `api` | Direct API call (GET/POST/PATCH/DELETE) |

Coming soon: `edge-config`, `blob`, `functions`, `crons`, `webhooks`, `monitoring`

## Examples

### Deploy Project

```bash
# Create project
node vercel-ops.js projects create --name my-app --framework nextjs

# Set environment variables
node vercel-ops.js env add prj_xxx --key API_KEY --value secret --target production

# Create deployment
node vercel-ops.js deployments create prj_xxx --target production

# Wait for ready
DEPLOYMENT_ID=dpl_xxx
while [ "$(node vercel-ops.js deployments get $DEPLOYMENT_ID --json | jq -r '.readyState')" != "READY" ]; do
  sleep 5
done
```

### Manage Environments

```bash
# Import from .env file
node vercel-ops.js env import prj_xxx --file .env.production --target production

# List all variables
node vercel-ops.js env list prj_xxx

# Update variable
node vercel-ops.js env update prj_xxx env_xxx --value new-value
```

### Domain Setup

```bash
# Add domain
node vercel-ops.js domains add prj_xxx --domain example.com

# Verify DNS
node vercel-ops.js domains verify example.com

# Assign alias
node vercel-ops.js aliases assign dpl_xxx --alias example.com
```

### Query Logs

```bash
# Get deployment logs
node vercel-ops.js logs get dpl_xxx

# Follow logs in real-time
node vercel-ops.js logs follow dpl_xxx

# Filter by source
node vercel-ops.js logs get dpl_xxx --source build
```

### Direct API Access

```bash
# GET request
node vercel-ops.js api GET /v9/projects

# POST request
node vercel-ops.js api POST /v13/deployments --data '{"name":"my-project"}'

# With query params
node vercel-ops.js api GET /v9/projects --query "limit=10&teamId=team_xxx"
```

## Use Cases

### CI/CD Integration

```yaml
# GitHub Actions
- name: Deploy to Vercel
  env:
    VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
  run: |
    node vercel-ops.js deployments create $PROJECT_ID --target production
```

### Blue-Green Deployment

```bash
# Deploy new version
GREEN=$(node vercel-ops.js deployments create prj_xxx --json | jq -r '.id')

# Wait for ready
while [ "$(node vercel-ops.js deployments get $GREEN --json | jq -r '.readyState')" != "READY" ]; do
  sleep 5
done

# Switch traffic
node vercel-ops.js aliases assign $GREEN --alias myapp.com
```

### Cleanup Old Deployments

```bash
# Delete deployments older than 30 days
CUTOFF=$(date -d "30 days ago" +%s)000
node vercel-ops.js deployments list --project prj_xxx --json | \
  jq -r ".deployments[] | select(.created < $CUTOFF) | .uid" | \
  xargs -I {} node vercel-ops.js deployments delete {}
```

## Documentation

- [SKILL.md](SKILL.md) - Full usage guide
- [references/vercel-api.md](references/vercel-api.md) - Complete API reference
- [references/examples.md](references/examples.md) - Real-world examples
- [references/troubleshooting.md](references/troubleshooting.md) - Common issues

## Requirements

- Node.js 18+
- Vercel Access Token

## Comparison

| Tool | Pros | Cons |
|------|------|------|
| **vercel-ops** | Zero deps, scriptable, full API | No official support |
| **vercel CLI** | Official, feature-rich | Large, requires installation |
| **vercel-mcp** | Claude Code integration | OAuth only, limited |
| **@vercel/client** | SDK for apps | Requires build step |

## Contributing

This is an open-source project. Feel free to:
- Add new commands
- Improve error handling
- Add tests
- Fix bugs

## License

MIT

## Credits

Created for the vft-kit Claude Code plugin ecosystem.
