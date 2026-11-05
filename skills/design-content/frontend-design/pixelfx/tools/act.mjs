#!/usr/bin/env node
// See an effect acted out: the character, the target, the freeze on contact. Motion is what you are judging, so the
// strip shows consecutive 12 fps steps, not a sample.
//
//   node tools/act.mjs melee/sword-slash                strip: records/act/melee-sword-slash.png
//   node tools/act.mjs melee/sword-slash --mp4          video: records/act/melee-sword-slash.mp4
//   node tools/act.mjs melee/sword-slash --sheet        the whole act, character and all, as a transparent sprite sheet
//
// Options: --from S --to S (strip range) --step S (default 1/12) --cols N --zoom N --bg KIND --out FILE --no-target --seconds S

import { join } from "node:path";
import { ROOT, resolveIds, loadEffect, renderAct, spriteSheet, canvas, upscale, save, writeVideo } from "./lib/fxlib.mjs";

const args = process.argv.slice(2), flags = {}, pos = [];
for (let i = 0; i < args.length; i++) {
  if (["--mp4", "--no-target", "--sheet"].includes(args[i])) flags[args[i].slice(2)] = true;
  else if (args[i].startsWith("--")) flags[args[i].slice(2)] = args[++i];
  else pos.push(args[i]);
}
const ids = resolveIds(pos);
for (const id of ids) {
  const fx = await loadEffect(id);
  if (flags.sheet) {
    const r = renderAct(fx, { fps: fx.meta.fps, bg: "none", target: !flags["no-target"], hold: 0 }), name = id.split("/")[1], base = join(ROOT, "records", "act", id.replace("/", "-"));
    const s = spriteSheet(fx, r, name);
    s.json.meta.pixelfx.pivot = r.pivot;
    save(`${base}.sheet.png`, s.png);
    save(`${base}.sheet.json`, JSON.stringify(s.json, null, 1));
    console.log(`${id}  ${r.n} frames of ${r.w} x ${r.h}  ->  ${base}.sheet.png`);
    continue;
  }
  const r = renderAct(fx, { fps: 60, bg: flags.bg, target: !flags["no-target"], seconds: flags.seconds ? +flags.seconds : undefined });
  const base = join(ROOT, "records", "act", id.replace("/", "-"));
  if (flags.mp4) {
    const k = +(flags.zoom ?? Math.max(2, Math.min(8, Math.floor(960 / Math.max(r.w, r.h)))));
    const file = flags.out ?? base + ".mp4";
    writeVideo(file, r, k);
    console.log(`${id}  ${r.frames.length} frames  ${(r.frames.length / r.fps).toFixed(2)} s  ->  ${file}`);
  } else {
    const from = +(flags.from ?? r.frames[0].t), to = +(flags.to ?? r.frames[r.frames.length - 1].t), step = +(flags.step ?? 1 / 12), list = [];
    let held = 0;
    for (const f of r.frames) {
      if (f.t < from - 1e-6 || f.t > to + 1e-6) continue;
      if (f.t + 1e-6 >= from + list.length * step) list.push(f);
      else if (f.frozen) held++;
    }
    const k = +(flags.zoom ?? 3), cols = +(flags.cols ?? 8), rows = Math.ceil(list.length / cols);
    const img = canvas(cols * (r.w * k + 4), rows * (r.h * k + 18));
    list.forEach((f, j) => {
      const x = (j % cols) * (r.w * k + 4), y = Math.floor(j / cols) * (r.h * k + 18);
      img.text(f.t.toFixed(2), x + 2, y + 3, 2);
      img.paste(upscale(f.color, r.w, r.h, k), r.w * k, r.h * k, x, y + 16);
    });
    const file = flags.out ?? base + ".png";
    save(file, img.png());
    console.log(`${id}  ${list.length} steps  ->  ${file}`);
  }
}
