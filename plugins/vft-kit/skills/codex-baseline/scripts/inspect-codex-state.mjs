#!/usr/bin/env node

let input = "";
for await (const chunk of process.stdin) input += chunk;

let data;
try {
  data = JSON.parse(input);
} catch {
  process.exit(2);
}

const [mode, key] = process.argv.slice(2);
if (mode === "mcp-present") {
  process.exit(data && typeof data.name === "string" && data.transport ? 0 : 1);
}
if (mode === "mcp-enabled") {
  process.exit(data && typeof data.name === "string" && data.transport && data.enabled !== false ? 0 : 1);
}
if (mode === "plugin-enabled") {
  const installed = Array.isArray(data?.installed) ? data.installed : [];
  process.exit(installed.some((plugin) =>
    plugin?.pluginId === key && plugin.installed === true && plugin.enabled === true
  ) ? 0 : 1);
}

process.exit(2);
