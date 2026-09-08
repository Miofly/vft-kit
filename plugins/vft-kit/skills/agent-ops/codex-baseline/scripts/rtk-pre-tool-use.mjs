#!/usr/bin/env node

import { accessSync, constants } from 'node:fs';
import { delimiter, join } from 'node:path';

function hasRtk() {
  for (const dir of (process.env.PATH || '').split(delimiter)) {
    if (!dir) continue;
    try {
      accessSync(join(dir, 'rtk'), constants.X_OK);
      return true;
    } catch {}
  }
  return false;
}

function shouldWrap(command) {
  const value = command.trim();
  if (!value || value.startsWith('rtk ') || /[\n\r|;&<>`]|\$\(/.test(value)) return false;

  if (/^git\s+(status|diff|log)(?:\s|$)/.test(value)) {
    return !/(?:^|\s)(?:--porcelain(?:=\S+)?|--raw|--numstat|--name-only|--name-status|--format(?:=\S+)?|--pretty(?:=\S+)?|--quiet|--exit-code|--check|-z)(?:\s|$)/.test(value);
  }

  if (/^rg(?:\s|$)/.test(value)) {
    return !/(?:^|\s)(?:--json|--null|--files|--files-with-matches|--files-without-match|--files0-from(?:=\S+)?|--count|--count-matches|--stats|--vimgrep|-0|-c|-l|-L)(?:\s|$)/.test(value);
  }

  return /^ls(?:\s|$)/.test(value);
}

let payload;
try {
  payload = JSON.parse(await new Promise((resolve) => {
    let input = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => { input += chunk; });
    process.stdin.on('end', () => resolve(input));
  }));
} catch {
  process.exit(0);
}

const toolInput = payload?.tool_input;
const command = toolInput?.command;
if (payload?.hook_event_name !== 'PreToolUse' || typeof command !== 'string' || !hasRtk() || !shouldWrap(command)) {
  process.exit(0);
}

process.stdout.write(`${JSON.stringify({
  hookSpecificOutput: {
    hookEventName: 'PreToolUse',
    permissionDecision: 'allow',
    updatedInput: { ...toolInput, command: `rtk ${command.trim()}` },
  },
})}\n`);
