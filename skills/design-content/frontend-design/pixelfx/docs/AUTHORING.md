# Writing an effect

An effect is one file, `src/fx/<category>/<name>.js` (kebab-case), drawing pixel art over time into two buffers.
It has no images and no dependencies beyond `src/core`. It can be played live, recolored, mirrored and rendered
to a sprite sheet for any engine.

The quality bar is Sprite Fusion's open-source pixel art VFX by Hugo Duprez
([spritefusion.com/pixel-art-vfx](https://www.spritefusion.com/pixel-art-vfx), MIT). Every effect here should hold up
next to his at the same size on screen: as much detail, as much light, as much life. `src/core/sim.js` is adapted
from his code; read the three references written to that bar first: `src/fx/melee/sword-slash.js`,
`src/fx/ice/frost-nova.js`, `src/fx/explosions/small-explosion.js`.

## Two kinds of effect

**Simulated** (most one-shots: impacts, explosions, spells, anything with debris, sparks, smoke or fire). Export
`create(o)` returning `{ update(dt), draw(p), drawBack?(p) }`. Spawn particles, debris and lights in `create` and
`update`, keep your own `t`, draw from state. The runtime steps it at 120 Hz or finer, so physics looks the same at
any frame rate. Use the seeded `Rng` from `o.seed` for every random number.

```js
import { Particles, Lights, P, PF, Rng, fit, sparkle, smooth } from "../../core/index.js";

export const meta = { name: "Spark pop", desc: "...", tags: ["impact"], size: [96, 72], origin: [48, 56],
  duration: 1.2, loop: false, fps: 30, bg: "ground", options: { palette: [...], seed: 1 } };

export function create(o) {
  const C = fit(o.palette, 7), R = new Rng(o.seed), floor = () => 0;
  const ps = new Particles({ rng: R, ground: floor }), lights = new Lights();
  lights.add(0, -12, 40, C[4], 0.7, 0.4);
  for (let i = 0; i < 40; i++) {
    const a = R.range(0, Math.PI * 2), sp = R.range(80, 260);
    ps.spawn(P.SPARK, 0, -12, Math.cos(a) * sp, Math.sin(a) * sp - 60, R.range(0.2, 0.6));
  }
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); lights.update(dt); },
    draw(p) { if (t < 0.12) sparkle(p, 0, -12, 9 * (1 - t / 0.12), C[5], C[3]); ps.draw(p); lights.draw(p); },
  };
}
```

**Pure** (loops, and shapes that are a function of time: auras, portals, waterfalls, beams, critters). Export
`draw(p, t, o)` (and `drawBack(p, t, o)`): the frame at `t` from `t` alone, so it loops with no seam. Particles
that loop come from `cycle`, motion from `fly`, noise from `loopNoise`/`tileFbm`.

## The contract

- **Scale.** The stock character is 24 x 38 px (`actor: 2`): every effect is drawn at that scale, detail at the
  1 px level. Canvases are as big as the effect needs, often 96 to 320 px wide; transitions are 320 x 180.
- **Local coordinates.** (0, 0) is the anchor: the feet of the character, the point of impact, the base of a
  torch, the muzzle. x right, y down, 1 unit = 1 px. The painter places, mirrors (`flip`) and rotates (`angle`).
  Directional effects face right. Ground effects stand on y = 0, the floor; floor rings, cracks, scorch and
  puddles may draw a little below it as perspective.
- **Time.** One-shots run 0..duration and draw **nothing at t = duration** (set duration long enough for the last
  smoke to clear). Loops are seamless.
- **Options** `o`: `meta.options` merged with the caller's. Honour `o.palette` (main ramp, dark to bright; use
  `fit(o.palette, n)` so any length works) and `o.seed`. Other color ramps as options are resampled too.
  `x`, `y`, `flip`, `angle`, `light` are reserved.
- **Deterministic.** Never `Math.random()` or `Date`.
- **Layers.** `drawBack` for what's behind a character or the far half of a ring; `draw` for the rest.
- **Actor effects** (`actor: 2`) get `o.actor = { mask, pixels, x, y, w, h, head, chest }`: the character's
  silhouette and its own colors (`pixels`, a Uint32Array, 0 where empty) in local space, feet at (0, 0). Recolor
  `pixels` for frozen, poisoned, stone; outline `mask` for auras. Export `actorAlpha(t, o)` (0..1) when the
  character should vanish or appear; previews follow it.
- **Acts** (`export const act`): what the body does around the effect. Any effect with a character should have one; see
  below.
- **Credit.** If you adapt a specific recipe from one of Hugo's files, put a two-line credit at the top of yours:
  `// ... adapted from Sprite Fusion's open-source <name> (https://www.spritefusion.com/pixel-art-vfx/<name>),`
  `// MIT License, Copyright (c) 2026 Hugo Duprez.`

## Acts

An effect shows what the magic does. Its act shows what the character does. Without one, the best effect looks like a
sticker on a mannequin. Replies to the first release said it best: "lack of anticipation and cooldown phases".

```js
const GUARD = { ...READY, weapon: "sword", fx: 12, fy: -19, sa: -0.75 };
const COCK = { ...GUARD, crouch: 4, lean: -4, fx: -9, fy: -33, sa: -2.7, bx: 9, by: -22, armsFront: true };
const CUT = { ...GUARD, crouch: 4, lean: 5, fx: 24, fy: -19, sa: 0.6, ffx: 13, fbx: -10, ghost: 1 };

export const act = {
  target: { x: 58 },                                // or targets: [{ x: 58 }, { x: 104 }]
  poses: [[-0.5, GUARD], [-0.2, COCK], [0.06, CUT, "snap"], [0.7, GUARD]],
  hits: [{ t: 0.06, stop: 0.14, shake: 0.18, amp: 2, push: 2.8, straw: 18, skin: "char" }],
  dust: [{ t: 0.06, x: 12, n: 6, dir: 1 }],
};
```

- **Time** is the effect's own: t = 0 is its first frame, so a negative key is a wind-up. A one-shot's act runs to its last
  key, which may be after the effect has ended. A loop's keys run 0 to `duration` and match at both ends.
- **Poses** only say what differs from standing easy. `src/core/poses.js` lists every field and how the body works: where the feet and
  hands are, crouch, lean, turn, what's held and at what angle. The character is a real skeleton in 3D, drawn down to pixels: hands and
  feet are placed where they should end up, in px from the feet, and elbows, knees, spine and shoulders work themselves out. Between keys, limbs step at 12 fps and the feet's position stays smooth.
  `"snap"` holds the last pose and jumps on the key, `"out"` arrives fast and settles, `"in"` starts slow, `"line"` keeps a
  steady speed.
- **Hits** freeze everything for `stop` seconds and shake it by `amp` px for `shake` seconds; the target takes `push` (negative
  rocks it towards the caster), `straw`, `flash`, a `skin` (char, ice, shock, holy, shadow, red, poison; `null` clears it) and `shiver`.
  `at` picks one of several targets; `target: false` leaves them out of it. Line these up with the effect's own constants.
- **Weapons** are `sword greatsword dagger spear hammer scythe claw bow pistol launcher handle`. `two: true` puts both hands on it.
- **Hold it like you mean it.** An arm reaches about 15 px from its shoulder and bones don't stretch, so step the body (`x`) rather than ask too much,
  and keep a little bend in the elbow. On a swing the blade lags the hand: at mid-swing the arm has gone forward while the blade still points up, so the
  wrist breaks and it whips. Weapons stop at the floor by themselves. A long weapon rests in one hand, butt on the floor, and takes the second hand to swing.
- **Use the third dimension.** He faces right, three-quarters towards us, so for arms raised or open the near hand goes left of the chest (`fx < 0`) and the
  far hand right (`bx > 0`), usually with `turn: 1` so the chest faces us. `yaw` turns the whole body about its feet, weapon included: a spin is really a spin.
- **Line the hand up** with where the effect fires from: if a beam leaves `(15, -24)`, the pose's `fx, fy` are `15, -24` at t = 0.
- **`onBody: true`** when the effect reads `o.actor` (recolors `pixels`, outlines `mask`, exports `actorAlpha`). Draw it against the
  standing body as usual: each pixel of a pose knows which standing pixel it came from, so frost, poison and scan lines follow. What's
  off the body moves with the chest above the belt and stays put on the floor; `follow: 0` keeps it fixed, for a core at the hand.
- **What sells it:** a wind-up in the opposite direction to the blow. A big silhouette change on the release frame. A freeze
  on contact, longer for heavier blows (0.03 to 0.2 s). A follow-through that overshoots. Sword tips and hammer heads that meet the effect's arc.
  Raised hands go behind the head by themselves, so the face stays visible; put wind-ups beside or above the head, not across it.

**Moves** (`src/fx/moves/`) are effects made of effects. `chain` plays other effects as cues; a projectile is an effect whose `x`
is a function of time; `shiftKeys` reuses other effects' acts.

```js
export const create = chain([
  { fx: charge, t: 0.08, until: THROW, palette: PAL.fire },
  { fx: fireball, t: THROW, until: HIT, x: (t) => 28 + (t - THROW) * SPEED, y: -22 },
  { fx: blast, t: HIT, x: TX },
]);
```

Judge acts by their motion: `node tools/act.mjs <id>` shows consecutive 12 fps steps, `--mp4` plays it, and `tools/check.mjs` catches keys out of
order, unknown pose fields, loop seams and hands that teleport.

## The toolkit (`src/core/sim.js`, from Sprite Fusion's code)

- `new Particles({ rng, ground: (x) => floorY, sparks: [head..tail colors], haze: color, onLand })`,
  `ps.spawn(kind, x, y, vx, vy, life, color, size, delay, flags)`, `ps.update(dt)`, `ps.draw(p, "back"|"front")`.
  Kinds `P.*`: `SPARK` (speed-stretched two-tone streak, gravity, bounces on the floor, glows), `MOTE` (streak
  with a dark tail, dithers out), `STREAK` (accelerating dotted line: gathering energy), `FLAKE` (drifting
  speck, a cross when big), `VAPOUR` (soft translucent puff that swells and thins, optional haze glow), `DUST`
  (denser puff), `SMOKE` (three soft discs, lit cap, rises and sways; color 0 uses `SMOKE_RAMP`), `FIRE`
  (a ball of flame cooling down `FIRE_RAMP` as it rises; flag `PF.SMOKES` turns it to smoke when it dies,
  `PF.BIG` for bigger slower smoke), `BRAND` (burning chunk that trails flame and calls `onLand`), `GRIT`
  (falling bits that bounce once and settle), `EMBER` (rising, wandering, cooling), `STAR` (twinkling cross).
  `PF.BACK` draws a particle behind. `delay` holds it back.
- `new Bits({ ground })`, `bits.add({ kind: B.SHARD|B.CHUNK|B.DRIP, x, y, vx, vy, a, va, s, c, ramp, g, drag,
  bounce, life })`: rigid debris that tumbles, bounces and settles (`rest`).
- `new Lights()`, `lights.add(x, y, r, color, k, life)`: lights that flare and die (k falls with life²).
- `new Blazes(ps)`, `blazes.add(x, y, life, power)`: small fires that keep feeding flame where something landed.
- `sparkle(p, x, y, arm, c, tip, k)` star glint; `flare(p, x, y, L, k, ramp)` 8-ray flare;
  `band(p, cx, cy, r, sy, thick, alpha, ramp, keep, hot)` a ring on a tilted plane (sy 0.16 lies on the floor;
  keep `(g) => Math.sin(g) < 0` is the far half); `crystal(p, x, base, h, w, lean, ramp, { a, white, glint })` a
  faceted ice/crystal spike with a lit ridge.
- `GRAVITY` = 950 px/s². Hugo's code uses world units (2 per px): halve his speeds, distances and gravity.

## Painter API

Coordinates local, floats fine. `c` a color number; `a` alpha 0..1 (dithered unless said).

| call | draws |
|---|---|
| `p.px(x, y, c)` / `p.dot(x, y, c, a)` | one pixel, solid / dithered |
| `p.blend(x, y, c, a)` | one pixel, truly translucent |
| `p.disc(x, y, r, c, a)` | translucent disc (smoke, vapour, mist); c, a may be `(d, angle) =>` |
| `p.line(x0, y0, x1, y1, c, a)` | 1 px line; c, a may be `(u) =>` |
| `p.polyline(pts, c, a)`, `p.beam(x0, y0, x1, y1, w, c, a)` | lines through points; thick capsule |
| `p.circle`, `p.ellipse`, `p.ring`, `p.rect`, `p.poly`, `p.tri` | filled shapes; c, a may be functions of the shape's coordinates |
| `p.arc(x, y, r, w, a0, a1, c, a)` | band of a ring, `w` may taper `(u) =>` |
| `p.shade(x0, y0, x1, y1, fn)` | per-pixel shader: `fn(x, y, out)` returns a color or sets `out.c out.a out.l out.k`; x, y are pixel centers |
| `p.glow(x, y, r, c, k)`, `p.glowLine`, `p.glowRing`, `p.light(x, y, c, k)` | additive light |
| `p.sprite(rows, pal, x, y, {scale, a, flip, flipY, tint})` | sprite from strings |
| `p.text(str, x, y, c, {font, scale, align, outline, shadow, a})`, `p.measure` | pixel text (`mini` 3x5, `big` 5x7; use `scale: 2` at this size) |
| `p.mask(m, x, y, c, a)`, `p.outline(m, x, y, c, a)`, `p.get(x, y)` | silhouettes; read back a pixel |

Helpers from `src/core/index.js`: `createAct actTiming READY chain shiftKeys shiftHits skeleton posedParts`, `clamp lerp seg smooth bump ease.* TAU`, `Rng rng rand`, `noise noise2 fbm
loopNoise tileNoise tileFbm`, `fly flyV burst cycle stream`, `bolt forks star ngon trail`, `PAL RAMP ramp fit at
blend mix scale hex rgb luma WHITE`, `stockActor(2) drawActor HERO2 HERO_PAL`.

## The bar

What makes Sprite Fusion's effects good, and what every effect here must do:

1. **Lines and light, not fills.** Build with 1 px rims, rings, trails and sparks, and let light carry the
   brightness. A big flat area of saturated color is almost always wrong. White-hot cores and edges, tinted
   middles, deep color only in shadow.
2. **Light everywhere.** A big soft pool at low k, a tight hot one at the core, a light on every spark and
   glint, `Lights` that flare at the moment of impact and fall away, light along arcs and beams, a warm or cold
   pool on the floor while something burns or freezes.
3. **Translucent volumes.** Smoke, vapour, dust and mist are soft (`SMOKE`, `VAPOUR`, `DUST`, `p.disc`), lit on
   top, swelling and thinning. Never a dithered checkerboard for smoke.
4. **Real motion.** Sparks stretch with speed, fall and bounce. Debris tumbles, bounces, settles and fades.
   Fire rises and cools into smoke. Things that land kick up dust. Use drag: fast burst, slow drift.
5. **Choreography in phases.** Anticipation or charge (things gathering in), release (a 1 to 2 frame white
   hero frame, a flare, light, a burst), spread, hold (twinkles, glints, embers), break or melt, a long decay.
   Many small events, each varied in size, speed, timing and life.
6. **Depth.** Rings on the floor are flat ellipses with a far half behind the character and a near half in
   front. Back rows of crystals or flames are dimmer.
7. **Timing.** Fast attack, slow release. Big effects linger 2 to 4 s while smoke clears and sparkles fade;
   hits are snappy (0.3 to 0.8 s) but still have follow-through.
8. **Reads at 1x** with a clear focal point, no speckle noise inside shapes.
9. **Original.** Generic motifs fine; never a specific game's sprite, character or logo. Don't copy one of
   Hugo's effects wholesale: use his techniques, make the design your own.
10. **Clean.** Fits its canvas, ends empty or loops clean, deterministic, under 2 ms a frame (`tools/check.mjs`).

## The method

The method is Hugo Duprez's ([How to make (good) pixel art effects with
Claude](https://www.spritefusion.com/blog/how-to-make-good-pixel-art-effects-with-claude)): code is clay, trust
your eyes, feed your references.

1. **Reference first.** Find the closest of [his effects](https://www.spritefusion.com/pixel-art-vfx), look at it, and
   read its source for the choreography and numbers. His code uses world units, 2 per pixel.
2. **Say it in one line** with the art direction, then draft.
3. **Render and look**: `node tools/render.mjs <id> --zoom 3` (contact sheet in `records/<id>/contact.png`;
   `--all` every frame, `--mp4` motion).
4. **Benchmark**: put his and yours next to each other at the same height on screen. If his has more detail, light
   or life, yours isn't done.
5. **Fix the worst thing, render again.** Three rounds minimum; showpieces take more.
6. **Act it out** if there's a character: `node tools/act.mjs <id>`. Consecutive frames, not samples.
7. **Check**: `node tools/check.mjs <id>` until it passes clean.
