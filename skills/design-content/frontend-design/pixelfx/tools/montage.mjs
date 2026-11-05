#!/usr/bin/env node
// Many effects playing at once in one grid video, for READMEs and posts.
//
//   node tools/montage.mjs out.mp4 --ids fire/torch,ice/frost-nova,... --cols 6 --rows 3
//   node tools/montage.mjs out.gif --category fire --cols 5 --rows 3 --seconds 4
//
// Options: --ids a,b,c | --category c | --pick N (a spread over every category) --cols --rows
// --cell WxH (art pixels per cell, default 96x80) --scale N --seconds S --fps N --bg kind (default: each effect's)
// --stagger S (start offsets for one-shots) --rest S (pause before a one-shot replays) --gap N (px between cells)

import { join } from "node:path";
import { allIds, loadEffect, writeVideo, save } from "./lib/fxlib.mjs";
import { createFrame, clearFrame, createFx, composite, backdrop, drawActor, painterFor, stockActor, rand, actorAlphaOf, createAct, actBounds } from "../src/core/index.js";
import { categories } from "../src/fx/categories.js";
import { encodePNG } from "./lib/png.mjs";

const args = process.argv.slice(2), flags = {};
let outFile;
for (let i = 0; i < args.length; i++) {
  if (args[i].startsWith("--")) flags[args[i].slice(2)] = args[++i];
  else outFile = args[i];
}
if (!outFile) {
  console.error("usage: node tools/montage.mjs <out.mp4|out.gif|out.png> [--ids ...|--category c|--pick N] [--cols 6 --rows 3]");
  process.exit(1);
}
const cols = +(flags.cols ?? 6), rows = +(flags.rows ?? 3), [CW, CH] = (flags.cell ?? "96x80").split("x").map(Number);
const fps = +(flags.fps ?? 30), seconds = +(flags.seconds ?? 5), gap = +(flags.gap ?? 2), stagger = +(flags.stagger ?? 0.35), rest = +(flags.rest ?? 0.35);
let ids;
if (flags.ids) ids = flags.ids.split(",");
else if (flags.category) ids = allIds().filter((id) => id.startsWith(flags.category + "/"));
else {
  // a spread: round-robin over categories so every one shows up
  const by = categories.map((c) => allIds().filter((id) => id.startsWith(c.id + "/")));
  ids = [];
  for (let k = 0; ids.length < +(flags.pick ?? cols * rows) && by.some((l) => l.length > k); k++)
    for (const l of by) if (l[k] && ids.length < +(flags.pick ?? cols * rows)) ids.push(l[k]);
}
ids = ids.slice(0, cols * rows);

const W = cols * CW + (cols + 1) * gap, H = rows * CH + (rows + 1) * gap;
const cells = [], cellPlace = {};
for (const [i, id] of ids.entries()) {
  const fx = await loadEffect(id), m = fx.meta, frame = createFrame(CW, CH);
  // a canvas that fits is centred; a bigger one is cropped round its anchor, keeping a strip of floor in view
  const [w, h] = m.size, [ox, oy] = m.origin;
  const x = w <= CW ? Math.floor((CW - w) / 2) + ox : Math.round(CW / 2 + ox - w / 2);
  const y = h <= CH ? Math.floor((CH - h) / 2) + oy : CH - Math.min(h - oy, Math.round(CH * 0.16));
  const bg = backdrop(flags.bg ?? m.bg, CW, CH, y);
  if (fx.mod.act) {
    // an act stands on the floor near the bottom of its cell, with the whole performance in view if it fits
    const b = actBounds(fx.mod), bw = b.x1 - b.x0;
    Object.assign(cellPlace, { x: bw <= CW ? Math.floor((CW - bw) / 2) - b.x0 : Math.round(CW / 2 + (-b.x0 - bw / 2)), y: CH - 16 });
  }
  const acted = !!fx.mod.act, X = acted ? cellPlace.x : x, Y = acted ? cellPlace.y : y;
  cells.push({ id, fx, m, acted, frame, x: X, y: Y, bg: acted ? backdrop(flags.bg ?? m.bg, CW, CH, Y) : bg, cx: gap + (i % cols) * (CW + gap), cy: gap + Math.floor(i / cols) * (CH + gap), delay: m.loop ? 0 : rand(i, 7) * stagger, inst: null, born: 0 });
}
const n = Math.round(seconds * fps), frames = [], buf = new Uint8ClampedArray(CW * CH * 4);
for (let f = 0; f < n; f++) {
  const t = f / fps, out = new Uint8ClampedArray(W * H * 4);
  for (let i = 0; i < W * H; i++) out.set([0, 0, 0, 255], i * 4);
  for (const c of cells) {
    const local = t - c.delay;
    if (c.acted) {
      if (!c.act || (c.act.done() && t - c.ended > rest)) {
        c.act = createAct(c.fx.mod, { x: c.x, y: c.y });
        c.ended = Infinity;
      }
      clearFrame(c.frame);
      if (local >= 0) {
        c.act.draw(c.frame);
        c.act.update(1 / fps);
        if (c.act.done() && c.ended === Infinity) c.ended = t;
      }
      composite(c.frame, buf, c.bg);
      const [sx, sy] = local >= 0 ? c.act.shake : [0, 0];
      for (let yy = 0; yy < CH; yy++) {
        const from = Math.max(0, Math.min(CH - 1, yy - sy));
        for (let xx = 0; xx < CW; xx++) {
          const a = (from * CW + Math.max(0, Math.min(CW - 1, xx - sx))) * 4, d = ((c.cy + yy) * W + c.cx + xx) * 4;
          out[d] = buf[a]; out[d + 1] = buf[a + 1]; out[d + 2] = buf[a + 2];
        }
      }
      continue;
    }
    if (!c.inst || (!c.m.loop && local - c.born > c.m.duration + rest)) {
      c.inst = createFx(c.fx.mod, { x: c.x, y: c.y });
      c.born = Math.max(0, local);
    }
    clearFrame(c.frame);
    if (local >= 0) {
      const tt = local - c.born;
      while (c.inst.t < tt - 1e-6) c.inst.update(1 / fps);
      c.inst.draw(c.frame, "back");
      if (c.m.actor) drawActor(painterFor(c.frame).place(c.x, c.y), c.inst.options.actor ?? stockActor(), actorAlphaOf(c.fx.mod, c.m.loop ? c.inst.t % c.m.duration : Math.min(c.inst.t, c.m.duration), c.inst.options));
      c.inst.draw(c.frame, "front");
    }
    composite(c.frame, buf, c.bg);
    for (let yy = 0; yy < CH; yy++) out.set(buf.subarray(yy * CW * 4, (yy + 1) * CW * 4), ((c.cy + yy) * W + c.cx) * 4);
  }
  frames.push({ color: out });
}
const scale = +(flags.scale ?? Math.max(1, Math.floor(1280 / W)));
if (outFile.endsWith(".png")) {
  save(outFile, encodePNG(W, H, frames[Math.floor(n * 0.45)].color));
} else writeVideo(outFile, { w: W, h: H, fps, frames }, scale);
console.log(`${cells.length} effects, ${W}x${H} art px x${scale}, ${seconds}s -> ${outFile}`);
