#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
HEALTH_SCRIPT="$SKILL_DIR/scripts/check-mcp-health.mjs"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

cat > "$TMP_ROOT/healthy-server.mjs" <<'EOF'
import { spawn } from "node:child_process";
import readline from "node:readline";

if (process.env.GRANDCHILD_PID_FILE) {
  const grandchild = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], { stdio: "ignore" });
  await import("node:fs").then(({ writeFileSync }) => writeFileSync(process.env.GRANDCHILD_PID_FILE, String(grandchild.pid)));
}
const lines = readline.createInterface({ input: process.stdin });
lines.on("line", (line) => {
  const message = JSON.parse(line);
  if (message.method === "initialize") {
    process.stdout.write(JSON.stringify({
      jsonrpc: "2.0",
      id: message.id,
      result: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        serverInfo: { name: "fixture", version: "1.0.0" },
      },
    }) + "\n");
  }
});
EOF

cat > "$TMP_ROOT/unhealthy-server.mjs" <<'EOF'
process.exit(1);
EOF

healthy_config="$(node -e 'process.stdout.write(JSON.stringify({transport:{type:"stdio",command:process.execPath,args:[process.argv[1]],env:{GRANDCHILD_PID_FILE:process.argv[2]}}}))' "$TMP_ROOT/healthy-server.mjs" "$TMP_ROOT/grandchild.pid")"
unhealthy_config="$(node -e 'process.stdout.write(JSON.stringify({transport:{type:"stdio",command:process.execPath,args:[process.argv[1]]}}))' "$TMP_ROOT/unhealthy-server.mjs")"

printf '%s' "$healthy_config" | MCP_HEALTH_TIMEOUT_MS=2000 node "$HEALTH_SCRIPT"
if [ "$(uname -s)" != "Windows_NT" ]; then
  for _ in 1 2 3 4 5; do
    [ -f "$TMP_ROOT/grandchild.pid" ] && ! kill -0 "$(cat "$TMP_ROOT/grandchild.pid")" 2>/dev/null && break
    sleep 0.1
  done
  ! kill -0 "$(cat "$TMP_ROOT/grandchild.pid")" 2>/dev/null || { printf 'FAIL: MCP grandchild process leaked\n' >&2; exit 1; }
fi

set +e
printf '%s' "$unhealthy_config" | MCP_HEALTH_TIMEOUT_MS=500 node "$HEALTH_SCRIPT"
status=$?
set -e
[ "$status" -ne 0 ] || { printf 'FAIL: unhealthy MCP unexpectedly passed\n' >&2; exit 1; }

set +e
printf '%s' '{"transport":{"type":"streamable_http","url":"https://example.invalid"}}' | node "$HEALTH_SCRIPT"
status=$?
set -e
[ "$status" -eq 2 ] || { printf 'FAIL: non-stdio MCP should exit 2, got %s\n' "$status" >&2; exit 1; }

printf 'PASS: MCP stdio health probe\n'
