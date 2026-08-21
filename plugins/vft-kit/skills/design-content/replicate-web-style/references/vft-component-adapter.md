# VFT component style adapter

Use this reference when the target renders components from `vft` / `@vft-ui`. It defines reusable component anatomy and theme-hook rules only. Keep project routes, business names, wrapper classes, and project-prefixed selectors in the target's private profile.

## Inventory before styling

Inspect direct page markup, nested shared components, directives, and imperative services:

```bash
rg -n -o '<vft-[a-z0-9-]+' <target> -g '*.vue' | sort -u
rg -n "from 'vft'|v-loading|v-spin|popper-class|modal-class|append-to-body" <target> -g '*.vue'
```

Do not stop at the route entry. Follow imported components until every VFT surface reachable from the page is accounted for. Include closed states that render only after authentication or interaction.

Classify each surface as:

- **In-root:** descendant selectors under the page theme root can reach it.
- **Teleported:** pass an explicit theme class through the component's supported hook.
- **Imperative shared overlay:** style only when the service supports a scoped custom class; never use a page task to globally restyle every message or notification.

## Adapter matrix

| VFT surface | In-root anatomy | Teleported anatomy / hook | Required states |
|---|---|---|---|
| Input | `.vft-input__wrapper`, `.vft-input__inner`, `__prefix`, `__suffix`, clear icon | none | rest, placeholder, hover, full-wrapper `:focus-within`, clear, disabled, invalid |
| Select | `.vft-select__wrapper`, `__selected-item`, `__placeholder`, `__caret`, `__clear` | `popper-class`; `.vft-popper`, `.vft-select-dropdown`, `__list`, `__item`, `__empty`, `.vft-popper__arrow` | closed, open, hover row, selected row, disabled row, empty, clear |
| Button | `.vft-button`, `.vft-button--primary` | same selectors inside an explicit dialog hook | default, primary, hover, `:focus-visible`, loading, disabled |
| Pagination | `.vft-pagination`, `.btn-prev`, `.btn-next`, `.vft-pager li` | `popper-class` only when the sizes control is present | rest, hover, active page, disabled previous/next, total text |
| Dialog | none when appended to body | `modal-class`; `.vft-overlay-dialog`, `.vft-dialog`, `__header`, `__title`, `__headerbtn`, `__body`, `__footer` | overlay, panel, close, scroll owner, footer actions, focus trap |
| Switch | `.vft-switch`, `__input`, `__core`, `__action` | same selectors inside an explicit dialog hook | off, checked, hover, `:focus-within`, loading, disabled |
| Time picker | trigger uses the input wrapper anatomy | `popper-class`; `.vft-picker__popper`, `.vft-time-panel`, `.vft-time-spinner__wrapper`, `__list`, `__item`, `.is-active`, `.is-disabled`, `.vft-time-panel__footer`, `__btn` | closed, open, active time, hover, disabled time, cancel, confirm |
| Loading directive | local `.vft-loading-mask` | loading custom-class; `.vft-loading-spinner`, `.vft-loading-text`, `.circular`, `.path` | local, fullscreen, light, dark, reduced motion |
| Back to top | shared layout root plus icon inheriting `currentColor` | none; pass an explicit theme state from the layout when the control is outside the page root | hidden, visible, hover, `:focus-visible`, click, reduced motion |
| Icon / icon text | inherit `currentColor`; preserve intrinsic SVG | none | alignment, disabled color, button/control inheritance |

Verify rendered DOM before adding a selector. VFT versions can change internal BEM elements even when the component prop stays stable.

## Theme scope

- Implement only the theme modes required by the target. Do not invent a dark/light or classic/redesign toggle for a single-theme page.
- A single-theme migration must make its root and teleported hooks unconditional. Remove obsolete page-level theme state and controls; do not merely hide them.
- Keep a shared component's existing multi-theme API only when another active consumer still needs it. Pass the migrated page's fixed theme explicitly.
- Validate every supported mode, but do not create dark-mode CSS or dark-mode test work for a light-only target.

## Token mapping

Map the target design system to roles rather than hardcoded component colors:

- control surface, control text, muted text, placeholder, icon;
- control border, focus accent, disabled surface/text;
- overlay surface, option hover, option selected, option disabled;
- action default/primary/danger and on-accent text;
- shadow geometry, radius, density, and scrollbar roles.

Use the same roles across triggers and their teleported overlays. A paper-toned select trigger with a generic white/blue dropdown is an incomplete adaptation.

## Controls

- Style the complete wrapper. Keep the outer border visible and put focus on `:focus-within`; remove the inner input ring only after the wrapper has an equally clear keyboard state.
- Do not invent a pink or accent-colored wrapper outline when it is absent from the reference. For MoyuHot Bold, border contrast plus the hard-shadow/offset change is the focus indicator; do not stack an extra outline on top.
- Style entered text, placeholder, prefix/suffix icons, caret, clear icon, hover, disabled, and invalid states together.
- Use `currentColor` for icons when possible. Do not rewrite VFT SVG paths for a page theme.
- Preserve native input semantics, labels, keyboard behavior, and touch targets.

## Select and picker overlays

Pass a page-owned class through `popper-class` for every select or picker that opens a body-level panel. The class belongs to the target implementation; the reusable adapter only defines the contract.

Within the hook:

- style panel, border, single-layer shadow, arrow, list padding, and actual scroll owner;
- keep the longest value readable and give the trigger sufficient width;
- differentiate hover, selected, disabled, and empty states without relying only on color;
- verify keyboard navigation and scrolling at both ends;
- repeat the check in every theme mode the target actually supports.

Do not assume styling one select menu themes sibling selects. Each teleported instance must receive the active theme hook.

## Dialogs and nested components

For `append-to-body` dialogs, pass the active theme through `modal-class`. Scope panel, header, body, footer, close button, and overlay rules under that class.

When a shared component owns the dialog or picker:

1. Give it one optional theme input or explicit class inputs.
2. Forward only `modal-class`, `popper-class`, or the supported loading hook.
3. Keep the Bold CSS in the page/theme stylesheet, not the shared component.
4. Keep the default empty so existing consumers retain their current appearance.

Theme the element that actually scrolls. Confirm `scrollHeight > clientHeight` and computed `overflow-y` before adding scrollbar rules.

## Loading and imperative services

Use the loading directive's custom-class hook for teleported or fullscreen masks. Keep local masks positioned by their owner and fullscreen masks fixed to the viewport.

For a shared loading component, keep the frame, animation, accessibility semantics, and fallback presentation reusable, but let the active page or route provide semantic copy. Prefer explicit props at page-owned loading call sites and route metadata or a route profile for layout-level fallbacks. Do not bake one page's wording into every tool, and do not generate loading copy with CSS `content`. Verify that each distinct workflow names what is actually loading.

Inventory `Message`, `Notification`, and message-box calls, but do not add unscoped `.vft-message*` rules. If the service lacks a reliable per-call class, preserve the shared application presentation and record that boundary.

## Shared shell ownership

Some visible surfaces are owned by a parent layout or rendered as siblings of the themed page: the real scroll container, back-to-top control, route loading fallback, sticky application chrome, and global overlays. Inspect the rendered DOM and classify ownership before writing selectors; a descendant selector under the page root cannot reach these surfaces.

- Give each shell surface one owner. When the parent layout already owns loading, scrolling, navigation chrome, or back-to-top behavior, adapt that implementation and remove page-local duplicates.
- When the shared layout knows the active route or page theme, pass an explicit theme class to the shell control and keep the default class unchanged for other pages.
- When an ancestor scroll owner must react to a descendant theme root, use a narrowly scoped `:has()` selector if the target browser matrix supports it. Otherwise, toggle one layout class with lifecycle cleanup.
- Never restyle a shared shell control through an unscoped global component selector.
- For back-to-top behavior, target the element that actually scrolls, trigger visibility by scrolling that element, click the control, and confirm the same element returns to the top.
- Remove the page/theme marker on route exit so unrelated pages immediately recover their original presentation. Also clean up on theme exit only when the target genuinely supports multiple themes.

## Verification

For every component present on the target page:

1. Inspect computed background, color, border, shadow, font, and focus indicator.
2. Exercise rest, hover, focus-visible/focus-within, active/selected, disabled, loading, empty, and open states that apply.
3. Inspect each teleported layer under `body` and confirm the page hook exists only for the active theme.
4. Repeat in every supported theme mode, then at desktop and narrow mobile widths.
5. Check keyboard operation, touch target size, overflow, clipping, console errors, and reduced motion.
6. Scroll the actual owner and inspect any layout-level scrollbar, loading fallback, sticky chrome, and back-to-top control outside the page root. Confirm both activation and cleanup on a non-themed page.

Do not claim complete VFT adaptation from trigger-only screenshots or source inspection. Completion requires the rendered open overlays and interactive states.
