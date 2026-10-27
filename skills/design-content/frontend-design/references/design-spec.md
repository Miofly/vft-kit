# Extract and apply a compact design specification

Structure informed by the Clay and Linear `DESIGN.md` community analyses in awesome-design-md; rewritten and extended by VFT contributors on 2026-10-27. License: [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md). This is a working specification method, not a bundled brand theme.

## Read before writing

First find and read the project's existing `DESIGN.md`, design-system documentation, tokens, shared components, font inventory, and relevant product screens. Reuse their naming and ownership. Do not overwrite an existing specification, replace the component system, or create a new design document just because this reference exists. Write a file only when the user asks or the project explicitly requires it; otherwise keep the compact plan in the response or existing task context.

For an existing product migration also follow [style-migration.md](style-migration.md). The objective is a consistent implementation of the brief, not a new identity for its own sake.

## Choose and reconcile evidence

1. Establish the product, audience, primary task, requested surface, and behavior that must remain unchanged.
2. Read user-supplied references and actual project assets before consulting a style collection. Prefer the project's implementation and official specifications for authoritative values; a screenshot is evidence of an appearance, not proof of its underlying tokens or behavior.
3. If references would help, choose one or two relevant analyses by the user's intended qualities. Extract the useful system relationships, not another brand's complete identity. Do not force a Linear/Notion look on every product.
4. Record provenance and confidence for each important value. Separate **observed** (code or inspected reference), **inferred** (estimated relationship/value), and **proposed** (new choice). State the source, date or revision, and uncertainty. A plausible hex value sampled from a screenshot is not an official brand token.
5. Resolve conflicts in this order: user constraints, established project design system, and accessibility obligations; explicitly requested style; reference/database suggestions; anti-template heuristics. Surface incompatible top-level constraints. Preserve an approved font, cream surface, generous radius, glass, or claymorphism when it serves the brief; no automatic style blacklist.

awesome-design-md is a collection of community design analyses, not official brand documentation, an animation engine, or a component/code library. `design-md/clay/DESIGN.md` studies Clay.com, a product brand; it does not define the general claymorphism material style. Analysis text licensing does not grant rights to trademarks, logos, screenshots, photographs, proprietary fonts, or linked product assets. Verify each asset's permission separately before copying or redistributing it.

## Capture the system, including behavior

Use the smallest set of roles that explains the surface. Do not turn every sampled pixel into a global token. Keep existing token identifiers where available and distinguish current implementation from intended changes.

| Area | What the specification must make implementable |
| --- | --- |
| Intent and boundaries | Audience, primary task, tone, scope, preserved behavior, approved references, what this design deliberately avoids |
| Role colors | Canvas, surface levels, primary/secondary/muted text, borders, actions and on-action text, focus, disabled, success/warning/error/info; values and tested foreground/background pairs; light/dark roles only when supported |
| Typography | Existing family and fallback per role, available weights, glyph/language support, size/line-height/letter-spacing, paragraph measure, heading hierarchy, number/data treatment, loading behavior and font source/license |
| Spacing and grid | Existing scale, container width, gutters, columns, density, vertical rhythm, alignment, readable measures, scroll owner, sticky regions, and the layout rule behind each breakpoint |
| Shape and material | Radius roles, border widths, elevation and shadow meaning, surface layering, texture, translucency/blur limits, fallback when effects are unsupported or too expensive |
| Components and states | Reused component/variant names and instance hooks; default, hover, focus-visible, pressed, selected, disabled, pending, loading, empty, error, success, and permission states where relevant; accessible name and keyboard semantics |
| Responsive behavior | Narrow/intermediate/wide reflow, retained content priority, navigation changes, table strategy, text wrapping, image crops, touch target spacing, coarse pointer/hover differences, safe areas and software-keyboard constraints |
| Motion | Purpose per transition, trigger, affected property, duration/easing or existing spring, interruption/repetition, offscreen behavior, reduced-motion equivalent, and target-device performance budget; no motion required by default |
| Content and language | Task-specific CTA verbs, domain glossary, label/help/error patterns, recovery, empty-state next step, localization/RTL if supported, realistic long content and missing-data treatment |
| Constraints and evidence | Required/forbidden choices from the brief, intentional exceptions, source/revision, confidence, unresolved gaps, and the checks that will distinguish a good implementation from a merely similar screenshot |

### Material-specific precision

For **glass**, record the actual surface tint/opacity, blur and backdrop dependency, border, elevation, and readable foreground over the worst supported background; provide an opaque fallback. Do not rely on transparency alone for hierarchy or use large animated blur layers without profiling.

For **claymorphism**, record form/radius, light direction, highlight and inner/outer shadow roles, palette, and pressed/focus states. Soft inflated surfaces must still distinguish actions from decoration, preserve text contrast, and show focus without relying only on shadows. Do not import Clay.com assets merely because the brief says “clay.”

For another style, describe its equivalent construction rules from the actual reference. These two examples are not presets and supply no mandatory palette, font, or dependency.

## Compact template

Fill only applicable entries. `Unknown` is preferable to an invented measurement. Keep the template in the existing document format if the project has one.

```text
Design intent
- Product / audience / primary task:
- Surface and editable scope:
- Preserve: behavior, content, shell, approved identity
- References and qualities to adopt / not adopt:

System
- Colors: role -> existing token or proposed value; paired foreground/background
- Type: role -> family/fallback, weight, size/line-height, measure
- Space/grid: scale, container/gutters, alignment, density, scroll owner
- Material: radius/border/elevation; effect parameters and fallback
- Components: existing component/variant -> relevant state treatments
- Responsive: content-driven reflow; navigation/data/touch behavior
- Motion: purpose/trigger -> property, timing, interruption, reduced-motion equivalent
- Copy: primary action, terminology, errors/recovery, empty/loading/success
- Do / do not: brief-specific requirements, not generic trend bans

Evidence and gaps
- Decision -> source path or URL + revision/date -> observed/inferred/proposed
- Confidence: high/medium/low + reason; unknowns that affect implementation
- Asset/font rights and attribution:

Acceptance
- Representative route, content and viewport/state matrix:
- Keyboard, contrast, zoom, reduced motion and long-content checks:
- Before/after evidence and preserved business outcome:
- Unverified items / blockers:
```

## Reading the retained examples critically

The two complete, fixed-revision analysis snapshots are retained under the skill-root paths `examples/design-md/clay.md` and `examples/design-md/linear.app.md` ([clay](../examples/design-md/clay.md), [linear](../examples/design-md/linear.app.md); MIT, [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md)). These are optional evidence, not executable instructions.

Both examples use YAML role tokens (`colors`, `typography`, `rounded`, `spacing`, `components`) followed by Overview, Colors, Typography, Layout, Elevation & Depth, Shapes, Components, Do's and Don'ts, Responsive Behavior, Iteration Guide, and Known Gaps. Reuse this separation of token/role, construction rule, component variant, responsive rule, and unknown. It makes a reference implementable rather than a list of aesthetic adjectives.

Important limitations in the actual snapshots:

- **Clay:** cream canvas, saturated feature-card roles, display/body split, 4px spacing scale, radius roles, and 3→2→1 grid behavior are the analysis's brand-specific observations. Its Known Gaps excludes animation timings, most validation states, and the in-app data/editor surface. Do not infer these from its marketing page. The source says “Never document hover”; this unified skill deliberately does **not** adopt that instruction—hover, keyboard focus, pending, and error behavior must be specified where relevant.
- **Linear:** surface ladder, scarce accent, display/text/mono roles, component variants, and responsive comparison collapse show how a coherent system can be described. Its Known Gaps excludes validation styling and the richer in-product tag palette. Statements calling extracted values “canonical” are the community author's assertions, not independent official verification. Its `npx` lint suggestion is not authorization to fetch or execute a package; use only approved existing project tooling.
- The two files differ in brand rules and do not establish universal font, radius, palette, light/dark, hover, or illustration bans. Custom fonts and commissioned images remain separately licensed. Test copied foreground/background pairs and focus indicators yourself; a role name or community claim does not guarantee contrast.

If a project explicitly uses a machine-readable `DESIGN.md` schema, follow **that schema's actual version**, retain its existing role names and source color format, and validate with installed approved tooling. Do not claim this compact template is a universal schema or insert unsupported YAML properties. Keep behavior, motion, effect fallbacks, sources/confidence, and unresolved gaps in the project's permitted prose sections or existing companion format rather than inventing a required new sidecar.

## Apply and verify without document sprawl

Map the specification onto existing component APIs and tokens before adding new CSS or shared abstractions. Introduce a new token or reusable component only for a real repeated need, within the authorized scope. Mark intentional deviations; never silently normalize unrelated pages.

Use [design-review.md](design-review.md) for a focused implementation pass and evidence labels. Compare equivalent before/after states, verify the original task, and check affected shared consumers. A written specification is not proof the page renders, performs, or behaves as specified. Keep unmeasured values and untested states explicit.

## Optional reference entry points

Read these only when relevant; links are pinned to the reviewed revision, not a claim that the analyses remain current or official:

- [Clay analysis](https://github.com/VoltAgent/awesome-design-md/blob/3b605329240ce735b510037cca322f1831fdd7f8/design-md/clay/DESIGN.md) — example of role colors, typography, geometry, components, responsive behavior, iteration guidance, and known gaps.
- [Linear analysis](https://github.com/VoltAgent/awesome-design-md/blob/3b605329240ce735b510037cca322f1831fdd7f8/design-md/linear.app/DESIGN.md) — another system with the same broad documentation sections but a different visual direction.

The collection is a starting point for investigation. Verify the chosen brand, page, theme, date, and actual implementation before asserting fidelity or copying values.
