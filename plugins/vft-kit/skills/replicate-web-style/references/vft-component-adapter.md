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
| Icon / icon text | inherit `currentColor`; preserve intrinsic SVG | none | alignment, disabled color, button/control inheritance |

Verify rendered DOM before adding a selector. VFT versions can change internal BEM elements even when the component prop stays stable.

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
- repeat the check in light and dark modes.

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

Inventory `Message`, `Notification`, and message-box calls, but do not add unscoped `.vft-message*` rules. If the service lacks a reliable per-call class, preserve the shared application presentation and record that boundary.

## Verification

For every component present on the target page:

1. Inspect computed background, color, border, shadow, font, and focus indicator.
2. Exercise rest, hover, focus-visible/focus-within, active/selected, disabled, loading, empty, and open states that apply.
3. Inspect each teleported layer under `body` and confirm the page hook exists only for the active theme.
4. Repeat in light and dark modes, then at desktop and narrow mobile widths.
5. Check keyboard operation, touch target size, overflow, clipping, console errors, and reduced motion.

Do not claim complete VFT adaptation from trigger-only screenshots or source inspection. Completion requires the rendered open overlays and interactive states.
