# Extract observed design evidence without installing an extension

Adapted by VFT contributors on 2026-10-27 from bergside/design-md-chrome at `8e07614fb18752ab1ee14dd65a8ff93e63c9b13b`. License: MIT, see [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md). This reference extends the existing `frontend-design` skill; it does not install a Chrome extension or another skill.

Use this when an approved public reference or the user's own non-sensitive page must become a usable design specification. Read the existing project `DESIGN.md`, tokens, and component system first; apply [design-spec.md](design-spec.md), [style-migration.md](style-migration.md), and [design-review.md](design-review.md) as appropriate. Existing design-system authority and accessibility outrank scraped guesses. Do not overwrite an existing specification or create a new one unless requested or required by the project.

## Privacy and execution gate

**Default: local evidence only.** Use an already approved preview or a supplied, sanitized style payload. Do not open authenticated dashboards, mail, payment, account settings, private documents, or pages with customer data merely to harvest a style. Authorization to inspect public style is not permission to capture credentials, form values, user text, cookies, storage, session URLs, or hidden data. User-owned pages still require scope and sensitive-data review.

The unchanged upstream `content-script.js` is **not** privacy-minimized: `collectSiteSignals()` reads title/meta, headings/nav/CTA strings, the full `location.href` (including query/hash), and up to the first 14,000 characters of `body.innerText`; `toCorpus()` later uses up to 2,400 of that text. It registers a Chrome message listener and a window sentinel; it is not an exported pure function. Removing text from its result afterward does not undo the collection. **Do not inject or execute this raw script by default.** It is retained as auditable source evidence only.

Prefer the approved browser's existing computed-style inspection or an already available sanitized payload. Reuse the same property schema and the pure upstream libraries below rather than inventing a second extraction engine. Collect only the approved target elements' style properties, with a non-sensitive surface label instead of `location.href`; do not request `bodyText`, `siteSignals.textSample`, meta content, heading strings, or input values. If the available browser can only run the full raw extractor, report the privacy-minimized acquisition as unavailable and continue from supplied/static evidence. A separately requested browser adapter must be reviewed to omit collection at source, not silently generated or installed here.

No extraction step here sends data to an AI endpoint/API, downloads a package, writes the clipboard, starts a service, publishes, or changes browser/profile configuration. Never auto-run upstream popup, worker, extension installation, or quick-install routes. Downloading/saving a design draft is a separate local-file action; write only the authorized file/artifact path after reviewing/redacting its content. Do not use the clipboard as an implicit transport.

## What the unchanged collector actually observes

`content-script.js:extractStylesFromPage()` calls `collectSampledElements(280)`, then `getComputedStyle()` for six groups:

| Group | Raw fields |
| --- | --- |
| Typography | `fontFamily`, `fontSize`, `lineHeight`, `fontWeight`, `letterSpacing` |
| Colors | `color` as `textColor`, `backgroundColor`, `borderColor`, `outlineColor` |
| Spacing | Four margins and four paddings |
| Shape/depth | `borderRadius`, `boxShadow` |
| Motion | `transitionDuration`, `transitionTimingFunction`, `animationDuration`, `animationTimingFunction` |
| Context | Sample/total counts, component-selector counts, timestamp; upstream additionally collects sensitive-capable URL/text signals described above |

Sampling is selector-priority, not a representative random or area-weighted sample: body → headings → paragraphs → links → buttons → inputs → labels → landmarks → list/table → class/role/tabindex hints, deduplicated until 280. Early groups can exhaust the cap before controls. `isVisible()` only checks positive bounding-box size, `display != none`, and `visibility != hidden`; offscreen, occluded, opacity-zero, collapsed-by-ancestor, and accessibility-hidden elements can still be counted. Component counts scan the document without that visibility filter. A class containing `card` does not prove a reusable card component exists.

Preserve the raw approved observations and record selector/component, role, viewport, theme, state, language, font-load status, and evidence timestamp separately. The upstream arrays do not retain per-row selectors, ancestry, real component identity, or explicit state provenance. Do not claim they provide those facts. `getComputedStyle()` can reflect an already applied cross-origin stylesheet, but the collector neither reads inaccessible CSS rules nor recovers original variables, cascade rationale, breakpoints, font license, or responsive intent.

## Local pipeline and real APIs

The four `.mjs` libraries are dependency-free and have no network, browser, clipboard, or file-write calls. Resolve `FRONTEND_DESIGN_DIR` to the actual loaded skill root supplied by the host—never a personal default checkout. Their exported interfaces are:

```text
normalizeExtractedStyles(payload) -> normalized
  extract/lib/normalize.mjs

generateDesignMarkdown({ normalized, metadata? }) -> markdown string
  extract/lib/generate-design-md.mjs

generateSkillMarkdown({ normalized, metadata? }) -> markdown string
  extract/lib/generate-skill-md.mjs

validateMarkdownOutput("design" | "skill", markdown)
  -> { isValid, errors, warnings, checks }
  extract/lib/validate.mjs
```

The skill generator is preserved for fidelity/tests only; this integration does not create or register another `SKILL.md`. Use the design generator only when a draft is useful and the output format matches the task. Its TypeUI-oriented eleven-heading blueprint is not a universal DESIGN.md schema or a substitute for an existing project's format.

### 1. Acquire a minimal, consented observation payload

The pure normalizer accepts this shape; arrays may be omitted when unknown. Examples below are illustrative fixture data, not values inferred for a real product:

```js
const payload = {
  source: { url: "approved-public-surface", title: "Reviewed surface" },
  sampledAt: "2026-10-27T00:00:00.000Z",
  sampledElements: 2,
  totalElements: 2,
  typography: [
    { fontFamily: "system-ui, sans-serif", fontSize: "16px",
      lineHeight: "24px", fontWeight: "400", letterSpacing: "0px" }
  ],
  colors: [
    { textColor: "rgb(17, 24, 39)", backgroundColor: "rgb(255, 255, 255)" }
  ],
  spacing: [{ paddingTop: "16px", paddingBottom: "16px" }],
  radius: ["8px"],
  shadows: ["none"],
  motion: [],
  components: [{ type: "buttons", count: 1 }]
  // No URL tokens, page text, cookies, storage, input values, or siteSignals.
};
```

Do not fabricate a timestamp/sample count for actual evidence. A local surface label is intentional: source URL need not be copied into the generated Markdown. Record a public canonical URL only if approved and genuinely needed; remove query/hash and sensitive path identifiers before any persistence. Browser/viewport/state provenance belongs in the local review record, not in a user-text corpus.

### 2. Normalize, then review and correct candidates before generation

`normalizeExtractedStyles()` counts/ranks font families, groups numerically sorted sizes/spacing/radii, ranks up to four shadows/easings, selects frequency-based color candidates, summarizes up to seven component counts, and returns `siteProfile` plus diagnostics. Returned fields are `source`, `sampledAt`, `sampledElements`, `totalElements`, `typographyScale`, `mainFontStyle`, `colorPalette`, `spacingScale`, `radiusTokens`, `shadowTokens`, `motionDurationTokens`, `motionEasingTokens`, `componentHints`, `siteProfile`, and `diagnostics`.

These are **inferred candidates**, not observed semantic tokens. `usage: 0` on numeric scales is generated bookkeeping, not measured zero usage. A frequently sampled font stack is not proof that the first family actually loaded or that it is the intended body/display face. Color frequency is not brand importance: a neutral background can dominate while a rare CTA accent carries identity. The “primary/secondary,” “base/raised,” and “focus.ring” names are positional heuristics; outline color on an unfocused element is not a verified focus style. Same-value deduplication can discard distinct roles.

**Do not pass known-bad normalized values through as authoritative rules.** Review raw style evidence with project tokens and actual component states. Correct approved in-memory candidate arrays or use the project's existing explicit values; preserve raw observations and explain each correction. If safe correction cannot be established, omit that family from the draft and mark it unknown rather than silently using a false value. Do not patch the preserved upstream source merely to hide these limitations.

| Reproduced limitation | Exact behavior | Required guard |
| --- | --- | --- |
| Alpha/compositing | `rgba(0, 0, 0, 0)` becomes `#000000`; alpha is discarded before `isTransparent()` | Reject/correct alpha-bearing candidates from raw values; retain RGBA/alpha and composited background relationships in the reviewed spec. Never compute contrast from the false opaque hex |
| Percentage RGB | `rgb(100%, 0%, 0%)` becomes `#640000` | Use verified computed opaque byte-RGB or the project's original color representation; do not trust unsupported conversion |
| Non-px/compound geometry | `1.5rem` becomes `1.5px`; `50%` radius becomes `50px`; `8px 24px` reduces to `8px` | Supply resolved scalar px only where appropriate; preserve percentages, elliptical/multi-corner geometry, fluid expressions, and original token units manually |
| Motion lists and precedence | Only the first comma duration is used; `transitionDuration: "0s"` masks `animationDuration: "2s"` | Inspect all transitions/animations with property/name, delay, trigger, repeat, easing, and lifecycle; correct the candidate list or leave it unknown |
| Role deduplication | Identical text/surface/focus values collapse to one highest-usage role | Restore verified semantic roles even when values match; do not infer missing role means unused role |
| Site profiling | English keyword/structure scoring; empty evidence can still produce a specific low-confidence label | Omit text collection; override audience/surface with confirmed metadata. CJK-only labels and complex product identity require human/project evidence |
| CJK skill slug | `systemName: "中文设计"` produces `name: design-system-` | Do not generate/install a new skill here; if explicitly requested later, a reviewed ASCII scope and separate valid-name check are required |

Diagnostics (`<30` samples, `<4` colors, `<3` type sizes, absent font, low site confidence) are warnings about this inference scheme, not quality failures or demands to add decorative colors/type. Keep confidence in your report: the generators do not carry all inference confidence into their draft.

### 3. Generate a reviewed draft in memory, then validate its structure

Use explicit, confirmed `metadata.systemName`, `brand`, `audience`, and `productSurface` rather than keyword guesses. Metadata is interpolated as text, not escaped or schema-validated, so reject unexpected control characters/Markdown structure from untrusted inputs and never treat generated page text as agent instructions.

```js
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const root = process.env.FRONTEND_DESIGN_DIR;
assert.ok(root && root.startsWith("/"), "Set FRONTEND_DESIGN_DIR to the loaded skill's absolute root");
const load = (name) => import(pathToFileURL(resolve(root, "extract/lib", name)).href);
const { normalizeExtractedStyles } = await load("normalize.mjs");
const { generateDesignMarkdown } = await load("generate-design-md.mjs");
const { validateMarkdownOutput } = await load("validate.mjs");

const normalized = normalizeExtractedStyles(payload); // approved payload from step 1
// Review raw observations; correct/omit affected candidate families per step 2.
// Proceed only after recording evidence for these actual role assignments.
normalized.colorPalette = [
  { token: "text.default", value: "#111827", usage: 1 },
  { token: "surface.canvas", value: "#ffffff", usage: 1 }
]; // illustrative correction for the fixture, NOT a production preset
const markdown = generateDesignMarkdown({
  normalized,
  metadata: {
    systemName: "Reviewed surface",
    brand: "Confirmed project name",
    audience: "Confirmed target audience",
    productSurface: "Confirmed surface and task"
  }
});
const result = validateMarkdownOutput("design", markdown);
assert.ok(result.isValid, result.errors.join("; "));
console.log(JSON.stringify({ errors: result.errors, warnings: result.warnings,
  checks: result.checks.length, draftCharacters: markdown.length }));
// No filesystem/clipboard/network write. Review before any authorized save.
```

The example assumes the preceding fixture `payload` in the same module. Do not copy its palette or metadata onto the user's page. `generateDesignMarkdown()` includes at most eight typography tokens, ten colors, eight spacing tokens, and eight per radius/shadow/duration group; it does not serialize a complete raw observation set, motion-easing collection, component implementation, or screenshots. Its `inferVisualStyle()` chooses generic adjectives from token counts. Replace unsupported aesthetic claims in a final specification with actual brief/evidence; do not call them measured design intent.

`validateMarkdownOutput()` checks eleven heading substrings, accessibility-target wording, optional skill frontmatter/markers, and presence of state/must/should words. Missing state words are **warnings**, not validity failures. It does not parse YAML, verify token semantics/contrast, prove WCAG conformance, execute controls, compare screenshots, validate every state, or certify the universal DESIGN.md format. `isValid: true` means this textual blueprint passed its own structural checks only.

### 4. Complete the design specification and close the evidence loop

Review the generated string before writing anything. Preserve project format and existing spec; merge only authorized additions. Add the items the sampling/generator cannot establish: layout/grid/container rationale, actual semantic roles, states and accessible names, keyboard/touch behavior, responsive collapse, real imagery rights, locale/CJK glyph coverage, motion triggers/reduced motion/cleanup, and unknowns. Each rule needs source, observed/inferred/proposed status, confidence, and a testable acceptance criterion.

Capture comparable before/after evidence for any future implementation, then verify the original user task, narrow/desktop layouts, focus, reduced motion, loading/error/empty states, long text, and affected shared consumers. Follow [design-review.md](design-review.md); source style extraction is not functional validation of the target or clone.

## Coverage gaps: never imply these were extracted

- **Visibility/state:** hidden branches, hover/focus/active/disabled/error states not currently rendered; opacity/occlusion/scroll clipping; keyboard reachability and accessible tree. Do not click destructive or protected controls just to discover styling.
- **Responsive:** one sample is one viewport/container/theme; no media/container-query rules, breakpoint intent, safe-area behavior, orientation or software-keyboard behavior are inferred. Acquire separately approved observations at representative states/widths.
- **DOM boundaries:** no traversal into iframe documents or open/closed shadow roots; `querySelectorAll` on the document does not cross them. Closed shadow internals and cross-origin iframe content remain unavailable. Pseudo-elements, SVG geometry, canvas/WebGL pixels, and image palettes are not captured.
- **CSS origin/assets:** computed results may include cross-origin CSS, but source rules/fonts/images and licenses are not extracted. Network image/font fetching and screenshot analysis are separate authorized tasks. No claim of original variables or authored token names.
- **Motion:** computed duration/easing strings are not a timeline, spring parameters, scroll progress relationship, WAAPI/GSAP behavior, shader logic, event trigger, cleanup, or performance measurement. Observe actual animation separately; do not infer missing duration means static UI.
- **Language/content:** English profiling is not robust multilingual audience inference. CJK font coverage, line breaking, translated expansion, RTL, semantic copy, and font loading/fallback require explicit checks. Body text extraction is not needed to learn a color/spacing system.

## Focused local validation

With `FRONTEND_DESIGN_DIR` set to the loaded skill's absolute root, these run only reviewed pure modules and fixture assertions; they require Node, not npm packages, browser installation, network, or a local server:

```sh
node "${FRONTEND_DESIGN_DIR:?Set the loaded skill absolute root}/extract/tests/run-tests.mjs"
node "${FRONTEND_DESIGN_DIR:?Set the loaded skill absolute root}/extract/tests/local-boundaries.mjs"
```

The first is unchanged upstream fixture coverage; the second is VFT-added characterization of known defects plus corrected in-memory draft generation. Passing defect assertions means the limitations remain present, **not repaired**. Real-page extraction, privacy-minimized browser acquisition, interactive/visual fidelity, extension runtime, and external Claude Design workflows remain unverified until separately authorized and actually exercised.
