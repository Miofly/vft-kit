#!/usr/bin/env node
// Restore readable .wxss files from an unpacked mini program.
//
//   node extract-wxss.mjs <unpacked-dir>
//
// Compiled packages keep styles as setCssToHead([...]) arrays inside
// page-frame.html (main package) and */page-frame.html (sub packages):
//   "."  [1]  "foo{...}"   -> [1] is the component scope prefix, dropped
//   [0, 32]                -> 32rpx
// The first unnamed setCssToHead([...]) that carries "./app.wxss" becomes app.wxss.
// Output files are written next to the source tree: <dir>/<path>.wxss
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];
if (!dir) {
  console.error('usage: node extract-wxss.mjs <unpacked-dir>');
  process.exit(2);
}

function walk(root, out = []) {
  for (const e of fs.readdirSync(root, { withFileTypes: true })) {
    const p = path.join(root, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name === 'page-frame.html' || e.name === 'page-frame.js') out.push(p);
  }
  return out;
}

// Find the matching closing bracket of the array literal starting at `start`.
function sliceArray(src, start) {
  let depth = 0;
  let quote = null;
  for (let i = start; i < src.length; i++) {
    const c = src[i];
    if (quote) {
      if (c === '\\') i++;
      else if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'") quote = c;
    else if (c === '[') depth++;
    else if (c === ']' && --depth === 0) return src.slice(start, i + 1);
  }
  return null;
}

function render(parts) {
  return parts
    .map((p) => {
      if (typeof p === 'string') return p;
      if (Array.isArray(p) && p[0] === 0) return `${p[1]}rpx`;
      return ''; // [1] scope prefix, [2, n] import markers
    })
    .join('');
}

let count = 0;
for (const file of walk(dir)) {
  const src = fs.readFileSync(file, 'utf8');
  const re = /setCssToHead\(\s*\[/g;
  let m;
  while ((m = re.exec(src))) {
    const arrStart = m.index + m[0].length - 1;
    const literal = sliceArray(src, arrStart);
    if (!literal || literal === '[]') continue;
    let parts;
    try {
      parts = Function(`"use strict";return (${literal});`)();
    } catch {
      continue;
    }
    const tail = src.slice(arrStart + literal.length, arrStart + literal.length + 400);
    const named = src.slice(Math.max(0, m.index - 200), m.index).match(/__wxAppCode__\['([^']+\.wxss)'\]\s*=\s*$/);
    const pathHint = tail.match(/path:\s*"\.\/([^"]+\.wxss)"/) || tail.match(/\(\.\/([^:]+\.wxss):/);
    const rel = named?.[1] || pathHint?.[1];
    if (!rel) continue;
    const base = path.relative(dir, path.dirname(file));
    const target = path.join(dir, base, rel);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, render(parts));
    console.log(path.relative(dir, target));
    count++;
  }
}
console.log(`restored ${count} wxss file(s)`);
