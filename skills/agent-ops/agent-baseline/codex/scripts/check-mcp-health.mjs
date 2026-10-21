#!/usr/bin/env node

import { spawn } from "node:child_process";

const timeoutMs = Number(process.env.MCP_HEALTH_TIMEOUT_MS || 60000);
let input = "";
for await (const chunk of process.stdin) input += chunk;

let config;
try {
  config = JSON.parse(input);
} catch {
  process.exit(2);
}

const transport = config?.transport;
if (transport?.type !== "stdio" || !transport.command) process.exit(2);

const child = spawn(transport.command, transport.args || [], {
  cwd: transport.cwd || undefined,
  env: { ...process.env, ...(transport.env || {}) },
  detached: process.platform !== "win32",
  stdio: ["pipe", "pipe", "pipe"],
});

let settled = false;
let stdout = "";
let timer;
const stopChild = (signal) => {
  if (!child.pid) return;
  try {
    if (process.platform === "win32") child.kill(signal);
    else process.kill(-child.pid, signal);
  } catch {
    // The MCP process may already have exited between the response and cleanup.
  }
};
const finish = (code) => {
  if (settled) return;
  settled = true;
  clearTimeout(timer);
  stopChild("SIGTERM");
  setTimeout(() => stopChild("SIGKILL"), 250).unref();
  process.exitCode = code;
};

const inspectMessages = () => {
  const lines = stdout.split(/\r?\n/);
  stdout = lines.pop() || "";
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const message = JSON.parse(line);
      if (message.id === 1 && message.result?.protocolVersion) finish(0);
      if (message.id === 1 && message.error) finish(1);
    } catch {
      // Some servers print startup text before the JSON-RPC response.
    }
  }
};

child.stdout.setEncoding("utf8");
child.stdout.on("data", (chunk) => {
  stdout += chunk;
  inspectMessages();
});
if (process.env.MCP_HEALTH_DEBUG === "1") {
  child.stderr.pipe(process.stderr);
}
child.on("error", () => finish(1));
child.on("exit", () => finish(1));

timer = setTimeout(() => finish(1), timeoutMs);
child.stdin.write(JSON.stringify({
  jsonrpc: "2.0",
  id: 1,
  method: "initialize",
  params: {
    protocolVersion: "2025-06-18",
    capabilities: {},
    clientInfo: { name: "codex-baseline", version: "1.0.0" },
  },
}) + "\n");
