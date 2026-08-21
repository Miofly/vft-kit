# Vercel-ops Quick Reference

## Setup (30 seconds)

```bash
# 1. Set token
export VERCEL_TOKEN=vcp_your_token_here

# 2. Test
node vercel-ops.js verify

# 3. Done!
```

## Most Used Commands

```bash
# List projects
node vercel-ops.js projects list

# Deploy to production
node vercel-ops.js deployments create PROJECT_ID --target production

# Check deployment status
node vercel-ops.js deployments get DEPLOYMENT_ID

# View logs
node vercel-ops.js logs get DEPLOYMENT_ID

# Add environment variable
node vercel-ops.js env add PROJECT_ID --key KEY --value VALUE --target production

# List deployments
node vercel-ops.js deployments list --project PROJECT_ID
```

## Quick Patterns

### Deploy and Wait
```bash
ID=$(node vercel-ops.js deployments create prj_xxx --target production --json | jq -r '.id')
while [ "$(node vercel-ops.js deployments get $ID --json | jq -r '.readyState')" != "READY" ]; do sleep 5; done
```

### Get Latest Deployment
```bash
node vercel-ops.js deployments list --project prj_xxx --json | jq -r '.deployments[0].uid'
```

### Bulk Import Env
```bash
node vercel-ops.js env import prj_xxx --file .env.production --target production
```

### Watch Deployment
```bash
node vercel-ops.js logs follow dpl_xxx
```

## Global Options

```bash
--profile NAME    # Use different account
--team-id ID      # Override team
--json            # Machine-readable output
--verbose         # Debug mode
--help            # Show help
```

## Common Tasks

| Task | Command |
|------|---------|
| Get project ID | `node vercel-ops.js projects list --json \| jq -r '.projects[] \| select(.name=="my-app") \| .id'` |
| Latest deployment | `node vercel-ops.js deployments list --project prj_xxx --json \| jq -r '.deployments[0]'` |
| Production URL | `node vercel-ops.js projects get prj_xxx --json \| jq -r '.targets.production.alias[0]'` |
| List env vars | `node vercel-ops.js env list prj_xxx` |
| Add custom domain | `node vercel-ops.js domains add prj_xxx --domain example.com` |

## Troubleshooting

```bash
# Check token
node vercel-ops.js verify

# View API calls
node vercel-ops.js --verbose projects list

# Test connectivity
curl -H "Authorization: Bearer $VERCEL_TOKEN" https://api.vercel.com/v2/user

# Check rate limits
node vercel-ops.js projects list -v 2>&1 | grep -i rate
```

## API Shortcuts

```bash
# GET
node vercel-ops.js api GET /v9/projects

# POST
node vercel-ops.js api POST /v13/deployments --data '{"name":"my-project"}'

# With params
node vercel-ops.js api GET /v9/projects --query "limit=10"
```

## Aliases

Add to `~/.bashrc`:

```bash
alias vo="node /path/to/vercel-ops.js"
alias vdeploy="vo deployments create"
alias vlist="vo projects list"
alias vlogs="vo logs get"
```

Then use:
```bash
vo projects list
vdeploy prj_xxx --target production
vlogs dpl_xxx
```

## CI/CD Snippet

```yaml
- name: Deploy
  env:
    VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
  run: |
    ID=$(node vercel-ops.js deployments create $PROJECT_ID --target production --json | jq -r '.id')
    while [ "$(node vercel-ops.js deployments get $ID --json | jq -r '.readyState')" != "READY" ]; do
      sleep 5
    done
    echo "Deployed: https://$(node vercel-ops.js deployments get $ID --json | jq -r '.url')"
```

## Need Help?

```bash
# Command help
node vercel-ops.js --help

# Subcommand help
node vercel-ops.js projects --help

# Full docs
cat SKILL.md
cat references/examples.md
cat references/troubleshooting.md
```
