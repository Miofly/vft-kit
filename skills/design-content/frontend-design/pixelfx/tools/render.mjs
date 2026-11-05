#!/usr/bin/env node
// Render effects so you can look at them.
//
//   node tools/render.mjs fire/torch            contact sheet: records/fire/torch/contact.png
//   node tools/render.mjs fire --gif            every fire effect, plus an animated GIF each
//   node tools/render.mjs "magic/portal*" --mp4 --scale 6
//   node tools/render.mjs ui/level-up --all     every frame in the contact sheet
//   node tools/render.mjs fire/torch --opts '{"palette":["#102","#215","#43a","#8cf","#fff"]}'
//
// Options: --gif --mp4 --sheet (transparent PNG + JSON) --all --max N (frames in the contact sheet)
// --zoom N (contact sheet scale) --scale N (GIF/MP4) --bg dark|ground|sky|light|black|none --seed N --fps N --opts JSON --out DIR
// --no-actor --loops N (repeat a loop in the GIF/MP4)
//
// This shows the effect by itself, with the character standing by. tools/act.mjs shows it acted out.

import { join } from "node:path";
import { ROOT, resolveIds, loadEffect, renderFrames, contactSheet, spriteSheet, writeVideo, save } from "./lib/fxlib.mjs";

const args = process.argv.slice(2), flags = {}, ids = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (!a.startsWith("--")) ids.push(a);
  else if (["gif", "mp4", "sheet", "all", "no-actor"].includes(a.slice(2))) flags[a.slice(2)] = true;
  else flags[a.slice(2)] = args[++i];
}
if (!ids.length) {
  console.error("usage: node tools/render.mjs <id|category|pattern>... [--gif] [--mp4] [--sheet] [--all]");
  process.exit(1);
}

const out = flags.out ?? join(ROOT, "records");
let failed = 0;
for (const id of resolveIds(ids)) {
  try {
    const fx = await loadEffect(id);
    const r = renderFrames(fx, {
      fps: flags.fps ? +flags.fps : undefined,
      seed: flags.seed ? +flags.seed : undefined,
      bg: flags.bg,
      actor: flags["no-actor"] ? false : undefined,
      options: flags.opts ? JSON.parse(flags.opts) : undefined,
    });
    const dir = join(out, id), made = [];
    made.push(save(join(dir, "contact.png"), contactSheet(fx, r, { max: flags.all ? 400 : +(flags.max ?? 16), zoom: flags.zoom ? +flags.zoom : undefined })));
    const k = +(flags.scale ?? Math.max(2, Math.min(8, Math.floor(480 / Math.max(r.w, r.h)))));
    const loops = +(flags.loops ?? (fx.meta.loop ? 2 : 1));
    if (flags.gif && writeVideo(join(dir, "anim.gif"), r, k, { loops })) made.push(join(dir, "anim.gif"));
    if (flags.mp4 && writeVideo(join(dir, "anim.mp4"), r, k, { loops: Math.max(loops, fx.meta.loop ? 3 : 1) })) made.push(join(dir, "anim.mp4"));
    if (flags.sheet) {
      const name = id.split("/")[1], s = spriteSheet(fx, r, name);
      made.push(save(join(dir, `${name}.png`), s.png), save(join(dir, `${name}.json`), JSON.stringify(s.json, null, 1)));
    }
    console.log(`${id}  ${r.n} frames  ->  ${made.join("  ")}`);
  } catch (e) {
    failed++;
    console.error(`${id}  FAILED: ${e.stack ?? e}`);
  }
}
process.exit(failed ? 1 : 0);
