---
name: replicate-web-style
description: Use when a user asks to high-fidelity copy, reproduce, clone, restyle, or migrate the visual design of a reference website, screenshot, design source, or local frontend into an existing Vue, React, Astro, or static HTML project, especially when typography, fonts, colors, spacing, layout, responsive behavior, interaction states, or motion must closely match.
---

# Replicate Web Style

## Overview

Reproduce a reference site's visual system without replacing the target's business logic. Treat fonts, color, geometry, responsive layout, interaction states, and motion as one fidelity contract.

## Workflow

1. Read the target repository instructions and inspect its framework, routes, shared tokens, component library, icon system, installed animation tools, and dirty worktree. Preserve existing behavior and user changes.
2. Inspect the reference in a real browser at desktop and mobile sizes. When source is available, trace the page route, global styles, font declarations, components, breakpoints, keyframes, and reduced-motion handling.
3. Capture a baseline screenshot of the target before editing. List the visible states that must remain functional: loading, empty, error, hover, focus, active, modal, and data refresh.
4. Extract the reference into six layers: palette and texture; typography; borders/radii/shadows; layout and density; component states; motion and breakpoints. Put reusable values behind a page-scoped root class or existing theme tokens.
5. Reuse the target's components, icons, dependencies, and DOM semantics. Change structure only where the reference's information hierarchy cannot be expressed by the existing markup. Do not replace state management, API calls, routes, or accessibility semantics for visual convenience.
6. Copy font assets only when redistribution is permitted. Preserve their license file, preload only critical faces, use `font-display: swap`, provide fallbacks, and confirm computed fonts in the browser.
7. Implement desktop first, then collapse deliberately at the reference breakpoints. Remove decorative rotation where narrow layouts need stable scanning.
8. Implement motion last. Match easing, duration, transform, and shadow changes; respect `prefers-reduced-motion`; avoid layout-triggering animation when transforms suffice.

When the target imports or renders VFT components, read [references/vft-component-adapter.md](references/vft-component-adapter.md) completely before editing. Use it to inventory nested controls, map supported theme hooks, and verify in-root plus teleported states.

For the MoyuHot Bold / Chinese handwritten zine direction, read [references/moyuhot-bold-preset.md](references/moyuhot-bold-preset.md) completely and copy the licensed fonts from `assets/fonts/` into the target's public asset directory.

## Fidelity Gate

Read [references/fidelity-checklist.md](references/fidelity-checklist.md) before editing and use it again for final review.

**REQUIRED SUB-SKILL:** Use `vft-kit:fe-auto-test` for real browser verification. Compare the reference and target at matching desktop and mobile viewports; verify overflow, console errors, fonts, hover/focus, dialogs, motion, and reduced-motion. Screenshots belong in the repository-approved temporary artifact directory, not the project root.

Do not call the work complete from code inspection alone. Completion requires a functioning page plus visual comparison at the agreed viewports.

## Boundaries

- Do not copy brand names, logos, proprietary illustrations, tracking code, or business data unless the user explicitly owns or authorizes them.
- Do not add a UI or animation dependency when the target or native CSS already covers the need.
- Do not apply a page-specific aesthetic through unscoped global selectors.
- Do not substitute generic gradients, soft shadows, or stock dashboard cards for distinctive reference details.
