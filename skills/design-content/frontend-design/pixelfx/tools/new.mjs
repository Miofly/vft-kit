#!/usr/bin/env node
// Start a new effect from a template: node tools/new.mjs <category>/<name> [--loop]
// Writes src/fx/<category>/<name>.js and renders it once.

import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { FX_DIR } from "./lib/fxlib.mjs";

const id = process.argv[2], loop = process.argv.includes("--loop");
if (!id || !/^[a-z0-9-]+\/[a-z0-9-]+$/.test(id)) {
  console.error("usage: node tools/new.mjs <category>/<name> [--loop]   (kebab-case)");
  process.exit(1);
}
const file = join(FX_DIR, id + ".js");
if (existsSync(file)) {
  console.error(`${file} already exists`);
  process.exit(1);
}
const name = id.split("/")[1].replace(/-/g, " ").replace(/^./, (c) => c.toUpperCase());
const body = loop
  ? `  // a loop: everything is a function of the phase, so t = 0 and t = duration match
  const C = ramp(o.palette), ph = t / meta.duration;
  cycle(t, meta.duration, 12, o.seed, 0.8, (age, life, r) => {
    const k = age / life, a = r.range(0, TAU) + ph * TAU, rad = 6 + k * 12;
    p.px(Math.cos(a) * rad, Math.sin(a) * rad - 8, at(C.slice(2), 1 - k));
  });
  p.circle(0, -8, 4 + Math.sin(ph * TAU) * 1.5, C[5]);
  p.glow(0, -8, 20, C[4], 0.35);`
  : `  // a one-shot: a hero frame, then everything falls away and is gone by t = duration
  const C = ramp(o.palette);
  if (t < 0.06) p.circle(0, -8, 6, WHITE);
  burst(14, o.seed, (r) => {
    const a = r.range(0, TAU), sp = r.range(40, 90), life = r.range(0.3, 0.6);
    if (t > life) return;
    const [x, y] = fly(0, -8, Math.cos(a) * sp, Math.sin(a) * sp, t, 120, 2);
    p.px(x, y, at(C.slice(2), 1 - t / life));
    p.light(x, y, C[4], 0.5 * (1 - t / life));
  });
  p.glow(0, -8, 24, C[4], 0.5 * (1 - seg(t, 0, 0.4)));`;
const src = `import { PAL, ramp, at, ${loop ? "cycle" : "burst, fly, seg, WHITE"}, TAU } from "../../core/index.js";

export const meta = {
  name: "${name}",
  desc: "One line: what it is, how it moves.",
  tags: ["${id.split("/")[0]}"],
  size: [48, 48],
  origin: [24, 32],
  duration: ${loop ? 1.2 : 0.7},
  loop: ${loop},
  fps: 30,
  bg: "dark",
  options: { palette: PAL.arcane, seed: 1 },
};

export function draw(p, t, o) {
${body}
}
`;
mkdirSync(dirname(file), { recursive: true });
writeFileSync(file, src);
console.log(`wrote ${file}\nnext: node tools/render.mjs ${id}   then look at records/${id}/contact.png\na character in it? give it an act: see "Acts" in docs/AUTHORING.md, then node tools/act.mjs ${id}`);
