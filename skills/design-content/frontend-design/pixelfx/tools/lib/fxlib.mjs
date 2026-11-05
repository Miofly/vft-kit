// Shared by the tools: find effects, render their frames, lay frames out, write PNG, GIF and MP4.

import { readdirSync, existsSync, statSync, writeFileSync, mkdirSync } from "node:fs";
import { join, dirname, relative, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";
import { createFrame, clearFrame, createFx, createAct, actBounds, actTiming, composite, painterFor, drawActor, stockActor, backdrop, actorAlphaOf } from "../../src/core/index.js";
import { rasterText, textWidth } from "../../src/core/font.js";
import { encodePNG } from "./png.mjs";

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
export const FX_DIR = join(ROOT, "src", "fx");

/** Every effect id ("fire/torch"), sorted. Files starting with _ are helpers, not effects. */
export function allIds(dir = FX_DIR) {
  const out = [];
  if (!existsSync(dir)) return out;
  for (const cat of readdirSync(dir).sort()) {
    const d = join(dir, cat);
    if (cat.startsWith("_") || !statSync(d).isDirectory()) continue;
    for (const f of readdirSync(d).sort()) if (f.endsWith(".js") && !f.startsWith("_")) out.push(`${cat}/${f.slice(0, -3)}`);
  }
  return out;
}

/** Ids matching patterns: "fire/torch", "fire" (a category), "fire/*", "*torch*", or a file path. */
export function resolveIds(patterns, dir = FX_DIR) {
  const all = allIds(dir), out = new Set();
  for (let p of patterns) {
    if (p.endsWith(".js")) p = relative(dir, p.startsWith("/") ? p : join(process.cwd(), p)).split(sep).join("/").replace(/\.js$/, "");
    const re = new RegExp("^" + p.split("*").map((s) => s.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*") + "$");
    const hits = all.filter((id) => id === p || id.startsWith(p + "/") || re.test(id));
    if (!hits.length) console.error(`no effect matches ${p}`);
    hits.forEach((h) => out.add(h));
  }
  return [...out];
}

/** Import an effect module fresh. */
export async function loadEffect(id, dir = FX_DIR) {
  const file = join(dir, id + ".js");
  const mod = await import(pathToFileURL(file).href + `?v=${statSync(file).mtimeMs}`);
  const meta = { fps: 30, bg: "dark", loop: false, duration: 1, tags: [], options: {}, ...mod.meta };
  if (!mod.meta) throw new Error(`${id}: no meta export`);
  if (!mod.draw && !mod.create) throw new Error(`${id}: exports neither draw nor create`);
  return { id, file, mod: { ...mod, meta }, meta };
}

/**
 * Render an effect's frames. Returns { w, h, fps, n, frames: [{ t, color: RGBA over the backdrop,
 * clear: RGBA on transparency }] }. opts: { fps, seed, bg, margin, options (passed to the effect) }.
 */
export function renderFrames(fx, opts = {}) {
  const { meta } = fx, [W, H] = meta.size, [OX, OY] = meta.origin, m = opts.margin ?? 0;
  const w = W + m * 2, h = H + m * 2, fps = opts.fps ?? meta.fps;
  const n = Math.max(1, Math.round(meta.duration * fps) + (meta.loop ? 0 : 1));
  const shown = createFrame(w, h, -m, -m), bare = createFrame(w, h, -m, -m);
  const bgKind = opts.bg ?? meta.bg;
  const bg = bgKind === "none" ? null : backdrop(bgKind, w, h, OY + m);
  const inst = createFx(fx.mod, { x: OX, y: OY, ...(opts.seed !== undefined ? { seed: opts.seed } : {}), ...(opts.options ?? {}) });
  const actor = meta.actor && opts.actor !== false ? inst.options.actor ?? stockActor() : null;
  const fade = m === 0 && !isScreen(meta);
  const frames = [];
  for (let i = 0; i < n; i++) {
    if (i > 0) inst.update(1 / fps);
    // `shown` has the backdrop and the stand-in actor; `bare` is the effect alone, for sprite sheets
    clearFrame(shown);
    clearFrame(bare);
    inst.draw(bare);
    inst.draw(shown, "back");
    if (actor) drawActor(painterFor(shown).place(OX, OY, !!opts.options?.flip), actor, actorAlphaOf(fx.mod, fx.meta.loop ? inst.t % fx.meta.duration : Math.min(inst.t, fx.meta.duration), inst.options));
    inst.draw(shown, "front");
    if (fade) (edgeFade(bare), edgeFade(shown));
    frames.push({
      t: i / fps,
      color: composite(shown, new Uint8ClampedArray(w * h * 4), bg),
      clear: composite(bare, new Uint8ClampedArray(w * h * 4), null),
      raw: bare.color.slice(),
      light: bare.light.slice(),
    });
  }
  return { w, h, fps, n, frames, margin: m };
}

/**
 * An effect acted out: the character, the target, the freeze, the shake, on a canvas big enough for all of it.
 * Returns { w, h, fps, n, frames: [{ t (effect time, negative before it starts), frozen, color }] }.
 */
export function renderAct(fx, opts = {}) {
  const { meta } = fx, fps = opts.fps ?? 60, b = actBounds(fx.mod), pad = opts.pad ?? 6;
  const w = b.x1 - b.x0 + pad * 2, h = b.y1 - b.y0 + pad * 2, X = pad - b.x0, Y = pad - b.y0;
  const frame = createFrame(w, h), bgKind = opts.bg ?? meta.bg, bg = bgKind === "none" ? null : backdrop(bgKind, w, h, Y);
  const act = createAct(fx.mod, { x: X, y: Y, ...(opts.seed !== undefined ? { seed: opts.seed } : {}), ...(opts.options ?? {}) });
  const frames = [], max = Math.round((opts.seconds ?? (meta.loop ? meta.duration * 2 - act.t : 8)) * fps);
  const show = () => {
    clearFrame(frame);
    act.draw(frame, { body: opts.actor !== false, target: opts.target !== false });
    const rgba = composite(frame, new Uint8ClampedArray(w * h * 4), bg), [sx, sy] = act.shake;
    frames.push({ t: act.t, frozen: act.frozen, color: sx || sy ? shifted(rgba, w, h, sx, sy) : rgba, clear: rgba });
  };
  show();
  for (let i = 0; i < max && !act.done(); i++) {
    act.update(1 / fps);
    show();
  }
  // a beat on the end, so a video doesn't cut off the last pose
  if (!meta.loop) for (let i = 0; i < fps * (opts.hold ?? 0.3); i++) {
    act.update(1 / fps);
    show();
  }
  return { w, h, fps, n: frames.length, frames, pivot: [X, Y] };
}
function shifted(rgba, w, h, sx, sy) {
  const out = new Uint8ClampedArray(w * h * 4);
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const X = Math.max(0, Math.min(w - 1, x - sx)), Y = Math.max(0, Math.min(h - 1, y - sy)), d = (y * w + x) * 4, s = (Y * w + X) * 4;
      out[d] = rgba[s]; out[d + 1] = rgba[s + 1]; out[d + 2] = rgba[s + 2]; out[d + 3] = rgba[s + 3];
    }
  return out;
}

/** Full-screen effects (transitions, weather, impact frames): 16:9 and at least 320 wide. They fill the screen. */
export const isScreen = (meta) => meta.size[0] >= 320 && Math.abs(meta.size[0] / meta.size[1] - 16 / 9) < 0.05;

/**
 * A glow cut off by the canvas edge shows as a box once a frame sits in a game. Ease the light out over the last
 * E pixels of the canvas, in place. Colour is left alone.
 */
export function edgeFade(f, E = 8) {
  const { w, h, light: L } = f;
  for (let y = 0; y < h; y++) {
    const ey = Math.min(y, h - 1 - y);
    for (let x = 0; x < w; x++) {
      const e = Math.min(ey, x, w - 1 - x);
      if (e >= E) { x = w - 1 - E; continue; }
      const i = y * w + x, l = L[i];
      if (!(l & 0xffffff)) continue;
      const u = (e + 0.5) / E, k = u * u * (3 - 2 * u);
      L[i] = (l & 0xff000000) | Math.round((l & 255) * k) | (Math.round(((l >>> 8) & 255) * k) << 8) | (Math.round(((l >>> 16) & 255) * k) << 16);
    }
  }
}

/** Nearest-neighbour upscale of RGBA. */
export function upscale(rgba, w, h, k) {
  if (k === 1) return rgba;
  const out = new Uint8ClampedArray(w * k * h * k * 4), src = new Uint32Array(rgba.buffer, rgba.byteOffset, w * h);
  const dst = new Uint32Array(out.buffer);
  for (let y = 0; y < h * k; y++) {
    const sy = (y / k) | 0;
    for (let x = 0; x < w * k; x++) dst[y * w * k + x] = src[sy * w + ((x / k) | 0)];
  }
  return out;
}

/** A blank RGBA canvas with helpers to paste images and write labels. */
export function canvas(w, h, fill = [12, 11, 16, 255]) {
  const data = new Uint8ClampedArray(w * h * 4);
  for (let i = 0; i < w * h; i++) data.set(fill, i * 4);
  return {
    w, h, data,
    paste(src, sw, sh, x, y) {
      for (let yy = 0; yy < sh; yy++) {
        const ty = y + yy;
        if (ty < 0 || ty >= h) continue;
        for (let xx = 0; xx < sw; xx++) {
          const tx = x + xx;
          if (tx < 0 || tx >= w) continue;
          const s = (yy * sw + xx) * 4, d = (ty * w + tx) * 4, a = src[s + 3] / 255;
          for (let c = 0; c < 3; c++) data[d + c] = src[s + c] * a + data[d + c] * (1 - a);
          data[d + 3] = Math.max(data[d + 3], src[s + 3]);
        }
      }
    },
    text(str, x, y, k = 2, rgb = [200, 196, 214], font = "mini") {
      rasterText(str, font, (gx, gy) => {
        for (let yy = 0; yy < k; yy++)
          for (let xx = 0; xx < k; xx++) {
            const tx = x + gx * k + xx, ty = y + gy * k + yy;
            if (tx >= 0 && ty >= 0 && tx < w && ty < h) data.set([...rgb, 255], (ty * w + tx) * 4);
          }
      });
    },
    rect(x, y, rw, rh, rgba) {
      for (let yy = Math.max(0, y); yy < Math.min(h, y + rh); yy++) for (let xx = Math.max(0, x); xx < Math.min(w, x + rw); xx++) data.set(rgba, (yy * w + xx) * 4);
    },
    png() {
      return encodePNG(w, h, data);
    },
  };
}

export { textWidth };

/** Which frames a contact sheet shows: all of them up to max, else evenly spaced. */
export function pickFrames(n, max = 16) {
  if (n <= max) return [...Array(n).keys()];
  return Array.from({ length: max }, (_, i) => Math.round((i * (n - 1)) / (max - 1)));
}

/** A contact sheet: frames in a grid, labelled, scaled to stay readable. Returns a PNG buffer. */
export function contactSheet(fx, r, { max = 16, width = 1600, title, zoom } = {}) {
  const { w, h, frames, fps } = r, idx = pickFrames(frames.length, max);
  const k = zoom ?? Math.max(1, Math.min(6, Math.floor((width - 16) / Math.min(idx.length, 6) / (w + 6))));
  const cw = w * k, ch = h * k, pad = 8, label = 16;
  const cols = Math.max(1, Math.min(idx.length, Math.floor((Math.max(width, cw + pad * 2) - pad) / (cw + pad))));
  const rows = Math.ceil(idx.length / cols), head = 30;
  const img = canvas(pad + cols * (cw + pad), head + rows * (ch + label + pad) + pad);
  const m = fx.meta;
  img.text(title ?? `${fx.id}  ${m.size[0]}x${m.size[1]}  ${m.duration}S  ${frames.length}F @${fps}  ${m.loop ? "LOOP" : "ONE-SHOT"}`, pad, 8, 3);
  idx.forEach((fi, j) => {
    const x = pad + (j % cols) * (cw + pad), y = head + Math.floor(j / cols) * (ch + label + pad);
    img.text(`${fi}  ${frames[fi].t.toFixed(2)}`, x, y, 2, [140, 134, 160]);
    img.paste(upscale(frames[fi].color, w, h, k), cw, ch, x, y + label);
  });
  return img.png();
}

/** A sprite sheet (transparent frames in a grid) plus Aseprite-style JSON that most engines import. */
export function spriteSheet(fx, r, name) {
  const { w, h, frames, fps } = r, n = frames.length;
  const cols = Math.min(n, Math.max(1, Math.ceil(Math.sqrt((n * h) / w)))), rows = Math.ceil(n / cols);
  const img = canvas(cols * w, rows * h, [0, 0, 0, 0]);
  const json = { frames: [], meta: {} };
  frames.forEach((f, i) => {
    const x = (i % cols) * w, y = Math.floor(i / cols) * h;
    img.paste(f.clear, w, h, x, y);
    json.frames.push({
      filename: `${name} ${i}`, frame: { x, y, w, h }, rotated: false, trimmed: false,
      spriteSourceSize: { x: 0, y: 0, w, h }, sourceSize: { w, h }, duration: Math.round(1000 / fps),
    });
  });
  const m = fx.meta;
  json.meta = {
    app: "https://github.com/patch-gg/pixelfx", version: "1", image: `${name}.png`, format: "RGBA8888",
    size: { w: cols * w, h: rows * h }, scale: "1",
    frameTags: [{ name: name, from: 0, to: n - 1, direction: "forward" }],
    pixelfx: { id: fx.id, name: m.name, fps, loop: m.loop, frames: n, frameSize: [w, h], pivot: m.origin, columns: cols, ...(fx.mod.act ? { act: actTiming(fx.mod) } : {}) },
  };
  return { png: img.png(), json };
}

/** Animated preview through ffmpeg (GIF or MP4), scaled k times. Returns false if ffmpeg is missing. */
export function writeVideo(file, r, k, { loops = 1 } = {}) {
  const { w, h, frames, fps } = r, W = w * k, H = h * k;
  const evenW = W + (W % 2), evenH = H + (H % 2), mp4 = file.endsWith(".mp4");
  const parts = [];
  for (let l = 0; l < loops; l++) for (const f of frames) parts.push(Buffer.from(upscale(f.color, w, h, k).buffer));
  const vf = mp4
    ? `pad=${evenW}:${evenH}:0:0:black,format=yuv420p`
    : "split[a][b];[a]palettegen=max_colors=255:stats_mode=full[p];[b][p]paletteuse=dither=none";
  const args = ["-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", `${W}x${H}`, "-r", String(fps), "-i", "-", "-vf", vf];
  if (mp4) args.push("-c:v", "libx264", "-crf", "14", "-preset", "slow", "-movflags", "+faststart");
  else args.push("-loop", "0");
  args.push(file);
  mkdirSync(dirname(file), { recursive: true });
  const res = spawnSync("ffmpeg", args, { input: Buffer.concat(parts), maxBuffer: 1 << 30 });
  if (res.error) return false;
  if (res.status !== 0) throw new Error(`ffmpeg failed: ${res.stderr}`);
  return true;
}

export function save(file, buf) {
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, typeof buf === "string" ? buf : buf);
  return file;
}
