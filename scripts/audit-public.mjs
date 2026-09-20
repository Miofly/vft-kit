#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const skip = new Set(['.git', '.codegraph', '.remember', '.idea', 'node_modules']);
const self = path.resolve(fileURLToPath(import.meta.url));
const privateUser = ['wf', 'ly'].join('');
const privateDomain = ['ifly', 'tek.com'].join('');
const forbidden = [
  new RegExp(`\\b${privateUser}(?:nn)?\\b`, 'i'),
  new RegExp([['vft', 'fnn'].join(''), ['fd', 'wei4'].join(''), ['vft', 'dream'].join('')].join('|'), 'i'),
  new RegExp(`${privateDomain}|${['xun', 'fei'].join('')}|${['kuy', 'in'].join('')}|${['groc', 'ery'].join('')}`, 'i'),
  new RegExp(`/Users/${privateUser}\\b`, 'i'),
  new RegExp(`java/${privateUser}-spring|${['mysql6', 'sqlpub.com'].join('\\.') }|${['spring', 'local'].join('_')}`, 'i'),
];

function walk(dir, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (skip.has(entry.name)) continue;
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(file, files);
    else if (file !== self) files.push(file);
  }
  return files;
}

const findings = [];
for (const file of walk(root)) {
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch {
    continue;
  }
  if (text.includes('\u0000')) continue;
  text.split(/\r?\n/).forEach((line, index) => {
    if (forbidden.some((pattern) => pattern.test(line))) {
      findings.push(`${path.relative(root, file)}:${index + 1}`);
    }
  });
}

if (findings.length) {
  console.error('public audit failed: private identifiers or local paths found');
  for (const finding of findings) console.error(`- ${finding}`);
  process.exit(1);
}

console.log(`public audit passed: ${walk(root).length} files scanned`);
