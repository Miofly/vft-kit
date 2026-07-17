#!/usr/bin/env node
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const explicitRoot =
  process.env.VFT_PLUGIN_ROOT ||
  process.env.CLAUDE_PLUGIN_ROOT ||
  process.env.CODEX_PLUGIN_ROOT;

if (explicitRoot) {
  console.log(explicitRoot);
} else {
  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  console.log(path.resolve(scriptDir, '..'));
}
