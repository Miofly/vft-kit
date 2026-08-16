# High-fidelity web style checklist

Use this checklist before editing and during final browser verification.

## Source and scope

- Identify the exact reference URL, route, source commit, and target route.
- Record desktop and mobile viewport sizes and capture reference screenshots.
- List business behavior and user-owned changes that must not change.
- Confirm which brand assets and fonts may legally be reused.

## Visual system

- Extract semantic colors, texture layers, gradients, borders, radii, and shadows.
- Record every font role, face, weight, style, line-height, letter-spacing, and fallback.
- Record container widths, grid columns, gaps, section spacing, card padding, and density.
- Record hover, focus-visible, active, disabled, loading, empty, error, and modal states.
- Record breakpoint behavior rather than merely shrinking desktop dimensions.

## Implementation

- Scope the theme under one page root or existing theme boundary.
- Reuse existing components, tokens, icons, and animation dependencies.
- Keep routes, APIs, state, links, form behavior, and DOM semantics intact.
- Serve fonts locally when bundled; preserve license text and upstream provenance.
- Preload only critical fonts; confirm no font 404, unwanted fallback, or major layout shift.
- Animate transforms and opacity where possible; honor `prefers-reduced-motion`.
- Preserve keyboard focus, touch targets, contrast, headings, labels, and dialog semantics.

## Browser verification

- Build or type-check with the target project's own commands.
- Verify desktop, tablet, and mobile with no horizontal overflow or clipped text.
- Compare matching reference/target screenshots for hierarchy, geometry, typography, density, and color.
- Exercise navigation, links, controls, hover, keyboard focus, loading, empty/error states, and dialogs.
- Check computed font families, network requests, console errors, and reduced-motion mode.
- Treat screenshot diff thresholds as a signal, then perform a human visual review; dynamic content must be masked or stabilized.

## Stop conditions

Do not claim completion while fonts fall back, responsive layout merely scales down, visible states are untested, reference and target viewports differ, or business behavior regresses.
