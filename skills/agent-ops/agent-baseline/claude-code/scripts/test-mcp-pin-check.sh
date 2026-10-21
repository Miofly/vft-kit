#!/usr/bin/env bash
# Selftest for mcp-pin-check.mjs: fake HOME with Claude, plugin and Codex configs.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
H="$tmp/home"
mkdir -p "$H/.claude/plugins/inst/p1/.claude-plugin" "$H/.codex" "$tmp/proj"
SECRETVAL="$(printf 'zq%s' 7Rk2Lm9Xw4Pt8Vb3)"   # built at runtime so no literal sits in this file

cat > "$H/.claude.json" <<EOF
{
  "mcpServers": {
    "latest": {"type": "stdio", "command": "npx", "args": ["-y", "@acme/latest-mcp@latest", "--url=http://localhost:1"]},
    "bare": {"command": "npx", "args": ["--yes", "plain-mcp"]},
    "pinned": {"command": "npx", "args": ["-y", "@acme/pinned-mcp@1.4.2"], "env": {"MG_MCP_TOKEN": "$SECRETVAL", "API_BASE_URL": "https://api.acme.test"}},
    "range": {"command": "npx", "args": ["-y", "ranged-mcp@^2.0.0"]},
    "pkgflag": {"command": "npx", "args": ["--package", "real-pkg", "real-bin"]},
    "gitbranch": {"command": "npx", "args": ["-y", "github:acme/tool#main"]},
    "gitsha": {"command": "npx", "args": ["-y", "github:acme/tool#0123456789abcdef0123456789abcdef01234567"]},
    "uvx": {"command": "uvx", "args": ["--from", "mcp-server-fetch==2025.1.1", "mcp-server-fetch"]},
    "uvxbare": {"command": "uvx", "args": ["mcp-server-time"]},
    "docker": {"command": "docker", "args": ["run", "--rm", "-i", "-e", "X=1", "ghcr.io/acme/mcp:1.0"]},
    "remote": {"type": "http", "url": "https://mcp.acme.test/mcp"},
    "remoteauth": {"type": "http", "url": "https://mcp.acme.test/mcp", "headers": {"Authorization": "Bearer \${ACME_TOKEN}"}},
    "plainhttp": {"type": "sse", "url": "http://mcp.acme.test/sse"},
    "shellwrap": {"command": "sh", "args": ["-c", "npx -y wrapped-mcp"]}
  },
  "projects": {"$tmp/proj": {"mcpServers": {"projlatest": {"command": "bunx", "args": ["proj-mcp@next"]}}}}
}
EOF
printf '{"mcpServers":{"dotmcp":{"command":"pnpm","args":["dlx","dot-mcp"]}}}\n' > "$tmp/proj/.mcp.json"
printf '{"enableAllProjectMcpServers": true, "enabledPlugins": {"p1@m": true}}\n' > "$H/.claude/settings.json"
printf '{"plugins":{"p1@m":[{"installPath":"%s"}],"gone@m":[{"installPath":"%s"}]}}\n' "$H/.claude/plugins/inst/p1" "$H/nope" > "$H/.claude/plugins/installed_plugins.json"
printf '{"mcpServers":{"plugmcp":{"command":"npx","args":["-y","@acme/plug-mcp@latest"]}}}\n' > "$H/.claude/plugins/inst/p1/.mcp.json"
cat > "$H/.codex/config.toml" <<EOF
model = "x"

[mcp_servers.cx-latest]
command = "npx"
args = [
  "-y",
  "@acme/codex-mcp@latest",
]

[mcp_servers.cx-latest.env]
MG_MCP_TOKEN = "$SECRETVAL"

[mcp_servers.cx-remote]
url = "https://mcp.acme.test/codex"
bearer_token_env_var = "ACME_TOKEN"
EOF

before="$(find "$H" "$tmp/proj" -type f -exec shasum {} + | sort)"
out="$(node "$DIR/mcp-pin-check.mjs" --home "$H" --json)"
text="$(node "$DIR/mcp-pin-check.mjs" --home "$H")"
after="$(find "$H" "$tmp/proj" -type f -exec shasum {} + | sort)"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
[ "$before" = "$after" ] || fail 'config files were modified'
case "$out$text" in *"$SECRETVAL"*) fail 'env value leaked into output' ;; esac

verdict() { node -e 'const r=JSON.parse(process.argv[1]).results.find(x=>x.name===process.argv[2]);process.stdout.write(r?r.worst:"missing")' "$out" "$1"; }
expect() { got="$(verdict "$1")"; [ "$got" = "$2" ] || fail "$1: expected $2, got $got"; }
expect latest high
expect bare high
expect pinned medium        # exact pin, but literal credential in env
expect range medium
expect pkgflag high
expect gitbranch high
expect gitsha review
expect uvx safe
expect uvxbare high
expect docker high
expect remote medium
expect remoteauth safe
expect plainhttp high
expect shellwrap high
expect projlatest high
expect dotmcp high
expect plugmcp high
expect cx-latest high
expect cx-remote safe
printf '%s' "$text" | grep -q 'env keys: MG_MCP_TOKEN,API_BASE_URL' || fail 'env key names not listed'
printf '%s' "$text" | grep -q 'enableAllProjectMcpServers=true' || fail 'enableAllProjectMcpServers not reported'
printf '%s' "$text" | grep -q 'plugin gone@m' || fail 'missing plugin installPath not reported'

set +e
node "$DIR/mcp-pin-check.mjs" --home "$H" >/dev/null; s0=$?
node "$DIR/mcp-pin-check.mjs" --home "$H" --fail-on high >/dev/null; s1=$?
set -e
[ "$s0" -eq 0 ] || fail "default exit should be 0, got $s0"
[ "$s1" -eq 1 ] || fail "--fail-on high should exit 1, got $s1"

printf 'PASS: mcp-pin-check classifies 19 MCP selectors, hides env values, never writes configs\n'
