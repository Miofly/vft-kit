# MoyuHot Bold preset

Use this preset for requests referencing `moyuhot.com/bold`, MoyuHot Bold, Chinese handwritten zine, cream-paper editorial, or the same visual direction. Reproduce the design language; remove the original brand, copy, platform data, and business logic.

## Signature

Combine a cream paper canvas, dark ink outlines, offset hard shadows, oversized handwritten Chinese display type, monospaced data, saturated sticker accents, pastel information cards, occasional inverted black cards, controlled rotation, dense editorial grids, and short playful motion.

## Tokens

```css
.zine-page {
  --paper: #fff4d6;
  --paper-deep: #ffe9a8;
  --ink: #1a1714;
  --pink: #ff3d7f;
  --blue: #2540d9;
  --yellow: #ffc93c;
  --green: #1f9f5f;
  --orange: #ff6b2c;
  --purple: #b080ff;
  --pink-soft: #ffd7e5;
  --blue-soft: #dbe2ff;
  --green-soft: #d7f1df;
  --border: 2.5px solid var(--ink);
  --frame-border: 3px solid var(--ink);
  --frame-shadow: 7px 8px 0 #111;
  --shadow-sm: 3px 3px 0 var(--ink);
  --shadow-md: 6px 6px 0 var(--ink);
  --shadow-lg: 9px 10px 0 var(--ink);
}
```

Use a paper base with low-opacity corner radial gradients, a subtle fractal-noise overlay, and an optional 7px halftone dot layer. Keep contrast high and texture opacity low enough that text remains clean.

## Fonts

Copy `assets/fonts/*.woff2` from this Skill to a stable public path in the target. Copy `assets/fonts/OFL-1.1.txt` and `assets/fonts/SOURCES.md` with them.

```css
@font-face { font-family: "Bagel Fat One"; src: url("/fonts/bagel-fat-one-ui.woff2") format("woff2"); font-display: swap; }
@font-face { font-family: "Fraunces"; src: url("/fonts/fraunces-ui.woff2") format("woff2"); font-style: normal; font-display: swap; }
@font-face { font-family: "Fraunces"; src: url("/fonts/fraunces-italic-ui.woff2") format("woff2"); font-style: italic; font-display: swap; }
@font-face { font-family: "Ma Shan Zheng"; src: url("/fonts/ma-shan-zheng-common-cn.woff2") format("woff2"); font-display: swap; }
@font-face { font-family: "Space Mono"; src: url("/fonts/space-mono-regular-ui.woff2") format("woff2"); font-weight: 400; font-display: swap; }
@font-face { font-family: "Space Mono"; src: url("/fonts/space-mono-bold-ui.woff2") format("woff2"); font-weight: 700; font-display: swap; }
@font-face { font-family: "ZCOOL KuaiLe"; src: url("/fonts/zcool-kuaile-ui.woff2") format("woff2"); font-display: swap; }
```

| Role | Family | Use |
|---|---|---|
| Hero | Ma Shan Zheng | Oversized Chinese handwritten title |
| Stamp and ranking | Bagel Fat One | Issue marks, numerals, playful badges |
| Editorial accent | Fraunces | Intro copy, quotes, italic annotations |
| Data and utility | Space Mono | Time, status, metadata, controls |
| Chinese card title | ZCOOL KuaiLe | Short headings and stickers |

Hero size: `clamp(74px, 11.5vw, 170px)` with tight line-height. Use the decorative faces sparingly; dense body copy stays in a readable system Chinese fallback.

## Geometry and layout

- Desktop page width: approximately 1380px with compact outer gutters.
- Hero: asymmetric two-column composition near `1.55fr / .9fr`; mobile becomes one column.
- Keep about 28–40px of visible vertical space between the hero title treatment and its lead. Handwritten glyphs, rotated words, and highlight strips must not intrude into the lead's breathing room.
- Statistics: four equal cards; `<=1100px` becomes two; `<=640px` becomes one.
- Dense content wall: four columns on wide screens, two where content permits, one on narrow screens.
- Major structural frames such as the hero, control deck, and primary content sections must use a 2.5–3px high-contrast ink outline plus a zero-blur hard shadow offset about 6–8px right and 7–9px down. Both the right and bottom shadow faces must remain visibly exposed without becoming a dominant black slab; reserve enough surrounding gutter to prevent clipping. Keep this distinct from the smaller cards' diagonal offset hard shadows.
- In dark mode, retain a clearly contrasting frame outline and keep the right-and-bottom slab near black; do not soften either into low-contrast tonal shadows.
- Cards: 12–20px radius, 2–2.5px ink border, 5–10px zero-blur shadow.
- Rotate only stamps, tape, notes, and selected cards by roughly `-3deg` to `3deg`; remove most rotation on narrow screens.
- Use structural labels, rankings, dividers, and issue metadata to encode real content, not as empty decoration.

## Components

- Top bar: narrow issue strip, date/status metadata, compact pill navigation, active item in inverted ink/paper colors.
- Hero: three-line handwritten title, yellow taped highlight, pink offset phrase, short editorial lead, right-side note or almanac card.
- Metric card: pastel surface, oversized number, tiny monospaced label, optional miniature line/bar mark.
- Content card: platform-colored header, compact icon or letter mark, ranked rows, timestamps, and a hard-shadow hover lift.
- Modal: centered paper/white panel, dark overlay, thick border, 10px hard shadow, obvious close control, short entrance.
- Select popover: treat teleported dropdowns as separate themed surfaces; give the trigger enough width for its longest value, use a 2px ink outline and compact hard shadow on the menu, and keep selected/hover rows fully readable rather than truncated.
- Text-field focus: preserve the outer ink frame, switch the complete field surface to a deliberate accent such as yellow, and grow its hard shadow. Remove nested browser/library focus rings that draw a second inset rectangle.

## Motion

- Hover lift: `translate(-2px, -3px)` with shadow growing from about `6px 6px` to `8px 9px`, 120–250ms.
- Note float: subtle vertical movement over 6s.
- Issue stamp sway: small rotation over roughly 4.5s.
- Online indicator pulse: 1.6s.
- Modal entrance: about 220ms using opacity and transform.
- Avoid heavy scroll animation. Under `prefers-reduced-motion: reduce`, remove continuous motion and reduce nonessential transitions to near-zero.

## Responsive behavior

At `<=1100px`, stack the hero, reduce the title, simplify rotation, and collapse dense grids. At `<=640px`, use about 14px page padding, a roughly 74px hero title, full-width cards, and complete single-column content without hiding information. Verify 390px and a narrower 320px viewport for overflow.
