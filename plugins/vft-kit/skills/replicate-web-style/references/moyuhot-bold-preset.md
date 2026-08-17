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
  --frame-ink: var(--ink);
  --control-ink: var(--ink);
  --on-accent: var(--ink);
  --text-soft: #574f46;
  --muted: #776b5f;
  --placeholder: #9a8c7b;
  --scroll-track: var(--paper-deep);
  --scroll-thumb: var(--pink);
  --scroll-thumb-hover: var(--blue);
  --scroll-edge: #fffaf0;
  --border: 2.5px solid var(--ink);
  --frame-border: 3px solid var(--frame-ink);
  --frame-shadow: 7px 8px 0 #111;
  --card-shadow: 5px 6px 0 var(--ink);
  --card-shadow-hover: 7px 8px 0 var(--ink);
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
- Cards: 12–20px radius, 2–2.5px ink border, and a smaller zero-blur hard shadow—about 5px right / 6px down at rest, growing to 7–8px right / 8–9px down on hover.
- Rotate only stamps, tape, notes, and selected cards by roughly `-3deg` to `3deg`; remove most rotation on narrow screens.
- Use structural labels, rankings, dividers, and issue metadata to encode real content, not as empty decoration.

## Components

When the target uses VFT, apply the complete [VFT component style adapter](vft-component-adapter.md). The rules below define the Bold visual treatment; the adapter defines VFT anatomy, Teleport hooks, and state coverage.

- Top bar: narrow issue strip, date/status metadata, compact pill navigation, active item in inverted ink/paper colors.
- Hero: three-line handwritten title, yellow taped highlight, pink offset phrase, short editorial lead, right-side note or almanac card.
- Metric card: pastel surface, oversized number, tiny monospaced label, optional miniature line/bar mark.
- Content card: platform-colored header, compact icon or letter mark, ranked rows, timestamps, and a hard-shadow hover lift.
- Modal: centered paper/white panel, dark overlay, thick border, 10px hard shadow, obvious close control, short entrance.
- System chrome: adapt shared scrollbars, route loading, and back-to-top controls only through an explicit page/theme marker. Use a compact ink-outlined sticker surface with a single hard shadow for back-to-top, preserve a clear focus outline, and keep non-Bold pages unchanged.
- Select popover: treat teleported dropdowns as separate themed surfaces; give the trigger enough width for its longest value, use a 2px ink outline and compact hard shadow on the menu, and keep selected/hover rows fully readable rather than truncated.
- Text-field focus: preserve the outer ink frame, switch the complete field surface to a deliberate accent such as yellow, and grow its hard shadow. Remove nested browser/library focus rings that draw a second inset rectangle.

### Form controls

Use warm neutrals that belong to the paper palette: body and selected text use `--ink`, supporting text and control icons use `--text-soft` or `--muted`, and placeholders use `--placeholder`. Keep placeholder contrast readable and do not dim it again with low opacity. Avoid inherited cool slate/blue-gray component defaults.

Apply focus to the complete control wrapper with `:focus-within`: retain the ink border, use an accent surface such as `--yellow`, and increase the hard shadow. Remove the inner input's native/library outline and shadow only after the wrapper provides an equally obvious keyboard focus state. Check text, placeholder, clear/search icons, and select carets together in light and dark modes.

### Dark adaptation

The Bold reference is light-first. Skip this section for a light-only target; do not add a theme toggle or dark token branch. When a target must support dark mode, preserve its geometry and editorial hierarchy instead of mechanically inverting every light token. Use a neutral near-black canvas, a clearly lighter charcoal surface, and one raised surface; avoid covering the whole page with a purple tint unless the reference explicitly does so.

Decouple text, structural frames, and internal controls. Main text may stay warm and bright, major frame outlines should use a quieter warm mid-tone, and internal controls should use a still lower-contrast border. Wide bands such as table or section headers use restrained antique gold rather than the full light-mode yellow. Reserve saturated pink, blue, and green for selected, actionable, or status-bearing elements.

```css
.zine-page.is-dark {
  --paper: #101116;
  --paper-deep: #202128;
  --surface: #18191f;
  --surface-raised: #202128;
  --ink: #f3ead8;
  --text-soft: #c7bcaa;
  --muted: #968d7e;
  --placeholder: #8f877a;
  --frame-ink: #9b8f78;
  --control-ink: #6f685b;
  --on-accent: #17130d;
  --yellow: #b7862d;
  --pink: #ff4f8b;
  --blue: #687dff;
  --green: #43c884;
  --shadow: #050506;
  --frame-shadow: 7px 8px 0 var(--shadow);
  --card-shadow: 5px 6px 0 var(--shadow);
  --card-shadow-hover: 7px 8px 0 var(--shadow);
}
```

Keep the same single-layer zero-blur right-bottom shadow geometry used in light mode for both structural frames and content cards. Make it legible through three luminance levels: a neutral near-black canvas, a visibly lighter charcoal module surface, and a darker near-black shadow. Keep only the structural border warm gray. Never wrap the shadow in a bright outline or add a contrasting second shadow; that creates an unwanted double-line or neon effect.

### Scroll surfaces

Theme the element that actually owns `overflow: auto|scroll`, not merely an outer dialog or card. Use both Firefox and WebKit rules; keep a roughly 10px visual width, a paper-toned track, an accent thumb, a contrasting hover state, and a surface-colored thumb border.

```css
.zine-scroll {
  scrollbar-color: var(--scroll-thumb) var(--scroll-track);
  scrollbar-width: auto;
}
.zine-scroll::-webkit-scrollbar { width: 10px; height: 10px; }
.zine-scroll::-webkit-scrollbar-track { background: var(--scroll-track); }
.zine-scroll::-webkit-scrollbar-thumb {
  border: 2px solid var(--scroll-edge);
  border-radius: 999px;
  background: var(--scroll-thumb);
}
.zine-scroll::-webkit-scrollbar-thumb:hover { background: var(--scroll-thumb-hover); }

html.dark .zine-page,
.zine-page.is-dark {
  --text-soft: #c7bcaa;
  --muted: #968d7e;
  --placeholder: #8f877a;
  --scroll-track: #202128;
  --scroll-thumb: #ff4f8b;
  --scroll-thumb-hover: #687dff;
  --scroll-edge: #18191f;
}
```

Do not accept browser-blue scroll thumbs, `scrollbar-width: thin` when the reference calls for a visible tactile control, or low-contrast gray-on-gray dark scrollbars. Verify the thumb color at rest and hover, then scroll to both ends with mouse/trackpad and keyboard.

## Motion

- Hover lift: `translate(-2px, -3px)` with shadow growing from about `6px 6px` to `8px 9px`, 120–250ms.
- Note float: subtle vertical movement over 6s.
- Issue stamp sway: small rotation over roughly 4.5s.
- Online indicator pulse: 1.6s.
- Modal entrance: about 220ms using opacity and transform.
- Avoid heavy scroll animation. Under `prefers-reduced-motion: reduce`, remove continuous motion and reduce nonessential transitions to near-zero.

## Responsive behavior

At `<=1100px`, stack the hero, reduce the title, simplify rotation, and collapse dense grids. At `<=640px`, use about 14px page padding, a roughly 74px hero title, full-width cards, and complete single-column content without hiding information. Verify 390px and a narrower 320px viewport for overflow.
