# Existing-product style migration

Apply this alongside the main design guidance when restyling a working page or matching a reference. This is a workflow, not a preset: it supplies no matching palette, typeface, or product-specific component adapter. The optional Geist bundle elsewhere in this skill is not an automatic replacement for the reference fonts.

## Establish the brief from evidence

- Inspect the dirty worktree, target page, imported components, shared layout, and actual reference pages before editing. Preserve overlapping user changes; do not replace an in-progress implementation wholesale.
- Treat the user's chosen style and verified existing product conventions as fixed parts of the brief. The main skill's warnings about generic defaults are not permission to redesign an approved identity.
- Derive color, type, spacing, geometry, texture, focus, overlay, scrollbar, and responsive behavior from the real reference. Separate observed values from proposed ones; report unavailable references or assets instead of inventing a preset or claiming fidelity.
- Reuse the target's actual font inventory before adding files. Verify weight, glyph coverage, loading, fallback, source, and license. Carry required attribution and license files with any copied asset; do not assume this skill contains fonts.
- Define one requested route or surface, its behavior contract, editable files, and focused validation. Do not convert the whole site or edit global design tokens as a side effect.

## Preserve behavior and ownership

Keep APIs, routing, state, view models, exports, authenticated and management controls, loading/error/empty states, keyboard semantics, and component behavior intact. Restyle existing components rather than replacing their interactions with look-alikes.

Keep business content page-owned and system chrome layout-owned. Ordinary restyles preserve the shared shell. If the brief explicitly requests an independent page, use a page-owned root while reusing the existing navigation; remove obsolete shell overrides and update affected tests. Do not duplicate navigation, loading infrastructure, back-to-top controls, or shell components. Add an abstraction only after stable repetition demonstrates the need.

Scope page CSS beneath a unique root marker. Inspect shared components before changing their defaults. Use documented per-instance hooks for feedback, overlays, and loading rather than global selectors that alter unrelated pages.

## Scroll and overlays

- Inspect the real ancestor chain and identify the actual scroll owner. A viewport-height host with `overflow: hidden` may require an independent root with `height: 100dvh; overflow-y: auto`; `min-height` alone can clip lower controls. Do not change global body overflow to hide the symptom.
- Style the owning scroll container, not every layout or backdrop. Distinguish the outer page scrollbar from compact dialog-list scrollbars. Keep existing navigation and scroll behavior unless the brief changes it.
- Teleported/portaled selects, pickers, dialogs, tooltips, loading masks, and imperative messages may live outside the page root. Pass explicit instance classes through the component's supported API, then scope global overlay rules under those classes. Check the panel, actions, close state, nested popovers, and actual dialog-body scroll owner.
- Style the complete form wrapper; use one coherent `:focus-within`/focus-visible treatment, not stacked outlines. Keep placeholder/icon contrast and `currentColor` SVG behavior.
- Remove a migrated page's obsolete theme switches and conditional hooks only when its brief fixes one theme. Do not remove application-wide theme infrastructure or break shared consumers that still need it.

## States and motion

Use fullscreen loading only for route entry or the minimum data gate. Slower sections retain their final layout with local, page-scoped skeletons. Loading, error, and empty copy describes the current workflow rather than borrowing another page's wording. Preserve retry and recovery actions.

Prefer CSS for simple transitions; reuse existing animation integration only for genuine orchestration. Respect `prefers-reduced-motion`, SSR safety, touch targets, dialog semantics, keyboard operation, and complete mobile content. Inspect continuous loaders for visible restart pauses.

## Focused validation and fidelity gate

1. Run the target's existing layout/behavior tests and the smallest relevant static checks. Do not build, start a local service, publish, or deploy unless separately authorized.
2. For visual validation, first run `command -v ego-browser`. If present, use the `ego-browser` skill and ego-lite: create an isolated `taskSpace("style-migration")`, print and reuse its `spaceId`, use `task.handOff()` for CAPTCHA/QR/2FA, and finish with `task.finish({ keep: [] })`. Only use Playwright if ego-browser is absent; do not choose an `auto` backend or fall back while ego-browser is available.
3. Compare the reference and result at desktop and mobile widths, including longest content, font loading, focus, reduced motion, loading/error/empty states, overflow, scrollbars, open popovers/dialogs, console errors, and the preserved business interactions. Use an already available preview or authorized environment; if none exists, report visual validation blocked rather than starting a service implicitly.
4. Navigate to an unrelated page and verify that shell classes, copy, feedback styling, overlays, and scrollbar treatment do not leak.
5. Report the exact surface changed and checks actually performed. Screenshots or command exit codes alone do not prove behavior. Without a browser comparison, label fidelity unverified; never mark this gate passed from static tests alone.

Keep private repository paths, routes, selectors, credentials, cookies, authenticated endpoints, and account conventions in a separate private profile. Use only user-approved artifact locations and never copy private data into a public skill.
