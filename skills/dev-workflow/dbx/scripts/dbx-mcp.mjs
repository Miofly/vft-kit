#!/usr/bin/env node

import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';

const args = process.argv.slice(2);
const dataDir = process.env.DBX_DATA_DIR || (
  process.platform === 'darwin'
    ? path.join(os.homedir(), 'Library/Application Support/com.dbx.app')
    : process.platform === 'win32'
      ? path.join(process.env.APPDATA || '', 'com.dbx.app')
      : path.join(os.homedir(), '.local/share/com.dbx.app')
);
const command = process.env.DBX_MCP_COMMAND || 'npx';
const commandArgs = process.env.DBX_MCP_ARGS
  ? JSON.parse(process.env.DBX_MCP_ARGS)
  : ['-y', '@dbx-app/mcp-server'];

const child = spawn(command, commandArgs, {
  env: { ...process.env, DBX_DATA_DIR: dataDir },
  stdio: ['pipe', 'pipe', 'pipe'],
});

let buffer = '';
let nextId = 1;
const pending = new Map();
const timeoutMs = Number(process.env.DBX_MCP_TIMEOUT_MS || 30_000);

child.stdout.on('data', (chunk) => {
  buffer += chunk;
  for (;;) {
    const newline = buffer.indexOf('\n');
    if (newline < 0) return;
    const line = buffer.slice(0, newline).trim();
    buffer = buffer.slice(newline + 1);
    if (!line) continue;
    try {
      const message = JSON.parse(line);
      const resolve = pending.get(message.id);
      if (resolve) {
        pending.delete(message.id);
        resolve(message);
      }
    } catch {
      // The native server speaks newline-delimited JSON; ignore non-protocol noise.
    }
  }
});

child.stderr.resume();

function rpc(method, params = {}) {
  const id = nextId++;
  child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`timeout calling ${method}`));
    }, timeoutMs);
    pending.set(id, (message) => {
      clearTimeout(timer);
      resolve(message);
    });
  });
}

async function tool(name, input = {}) {
  const response = await rpc('tools/call', { name, arguments: input });
  if (response.error) throw new Error(response.error.message || `DBX MCP ${name} failed`);
  if (response.result?.isError) {
    const text = response.result.content?.map((item) => item.text || '').join(' ').trim();
    throw new Error(text || `DBX MCP ${name} failed`);
  }
  return response.result;
}

function contentText(result) {
  return result?.content?.map((item) => item.text || '').join('\n') || '';
}

function rows(text) {
  return text.split('\n')
    .filter((line) => line.startsWith('|') && !line.includes('---'))
    .map((line) => line.split('|').slice(1, -1).map((cell) => cell.trim()))
    .filter((cells) => cells.length >= 7 && cells[1] !== 'Name');
}

function option(name, required = true) {
  const index = args.indexOf(name);
  if (index < 0) {
    if (required) throw new Error(`missing ${name}`);
    return undefined;
  }
  const value = args[index + 1];
  if (!value || value.startsWith('--')) throw new Error(`missing value for ${name}`);
  return value;
}

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf8').replace(/\r?\n$/, '');
}

async function main() {
  const commandName = args[0];
  await rpc('initialize', {
    protocolVersion: '2025-06-18',
    capabilities: {},
    clientInfo: { name: 'vft-kit-dbx', version: '1.0' },
  });
  child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} })}\n`);

  if (commandName === 'list') {
    process.stdout.write(contentText(await tool('dbx_list_connections')));
    return;
  }

  if (commandName !== 'add-mysql') {
    throw new Error('usage: dbx-mcp.mjs list | add-mysql --name NAME --host HOST --port PORT --username USER --database DB --password-stdin [--probe]');
  }

  if (!args.includes('--password-stdin')) throw new Error('password must be supplied through --password-stdin');
  const name = option('--name');
  const host = option('--host');
  const port = Number(option('--port'));
  const username = option('--username');
  const database = option('--database');
  const password = await readStdin();
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error('invalid --port');
  if (!password) throw new Error('empty password on stdin');

  const current = contentText(await tool('dbx_list_connections'));
  const existing = rows(current).find((cells) => cells[1] === name);
  let state = 'added';
  if (existing) {
    if (existing[3] !== 'mysql' || existing[4] !== host || existing[5] !== String(port) || existing[6] !== database) {
      throw new Error(`connection name already exists with a different target: ${name}`);
    }
    state = 'already-present';
  } else {
    await tool('dbx_add_connection', {
      name,
      db_type: 'mysql',
      host,
      port,
      username,
      password,
      database,
      ssl: false,
    });
  }

  if (args.includes('--probe')) {
    await tool('dbx_execute_query', {
      connection_name: name,
      database,
      sql: 'SELECT 1 AS dbx_probe',
    });
    process.stdout.write(`${state} name=${name} test=passed\n`);
  } else {
    process.stdout.write(`${state} name=${name}\n`);
  }
}

try {
  await main();
} catch (error) {
  console.error(`DBX MCP operation failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  child.kill('SIGTERM');
}
