#!/usr/bin/env node
// Find effects: node tools/list.mjs [words...]
// Matches ids, names, tags and descriptions; no words lists everything.

import { allIds, loadEffect } from "./lib/fxlib.mjs";

const words = process.argv.slice(2).map((w) => w.toLowerCase());
let n = 0;
for (const id of allIds()) {
  let m;
  try {
    m = (await loadEffect(id)).meta;
  } catch {
    continue;
  }
  const hay = [id, m.name, m.desc, ...m.tags].join(" ").toLowerCase();
  if (!words.every((w) => hay.includes(w))) continue;
  n++;
  const kind = m.loop ? `loop ${m.duration}s` : `once ${m.duration}s`;
  console.log(`${id.padEnd(30)} ${kind.padEnd(11)} ${(m.size[0] + "x" + m.size[1]).padEnd(8)} ${m.actor ? "actor  " : "       "}${m.desc}`);
}
console.log(`\n${n} effect${n === 1 ? "" : "s"}`);
