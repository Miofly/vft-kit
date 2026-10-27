# Evidence-led design review and refinement

Adapted and substantially rewritten by VFT contributors on 2026-10-27 from Impeccable's Apache-2.0 design workflows. License and NOTICE: [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md). This is guidance inside `frontend-design`, not a new command, plugin, detector, or installation step.

## Establish the task and constraints

Start with the real user: what must they understand, decide, or accomplish on this surface? Identify the audience, primary task, current route/component, representative content, supported devices, and explicit scope. For an existing product, also read [style-migration.md](style-migration.md); for design-system extraction, read [design-spec.md](design-spec.md).

Read existing design guidance, shared components, tokens, and neighboring screens before proposing changes. Preserve working behavior, user edits, approved identity, and ownership boundaries. Constraint order is: user requirements, established project design system, and accessibility obligations first; the specified visual direction next; reference/database suggestions next; anti-template heuristics last. If top-level requirements conflict, surface that conflict rather than silently dropping accessibility or changing the brief.

Cream surfaces, Inter, large radii, cards, glass, claymorphism, dark themes, or restrained layouts are not defects by themselves. Evaluate whether they serve this product, not whether they resemble a trend. Clay the brand is not a synonym for claymorphism.

## Select the smallest useful pass

Use these as task labels, not slash commands. Choose only the passes the request needs; do not perform every pass or create a backlog file automatically.

| Pass | Use when | Deliverable |
| --- | --- | --- |
| Audit | Need technical quality findings | Evidence-backed accessibility, responsiveness, performance, state, and implementation issues; no unsolicited redesign |
| Critique | Need judgment on UX and visual direction | What works, primary-task friction, hierarchy and identity issues, top 3–5 improvements |
| Normalize | Existing UI drifts from an approved system | Replace accidental one-offs with existing tokens/components; preserve intentional exceptions and business behavior |
| Clarify | Labels, errors, instructions, or CTA outcomes confuse users | Consistent vocabulary, explicit outcomes, recovery guidance; retain necessary domain terms |
| Distill | Decoration or complexity obstructs the task | Remove redundancy and unnecessary steps without deleting content, controls, recovery, or required disclosure |
| Adapt | A surface fails on another viewport or input method | Content-driven reflow and equivalent access; not a scaled-down desktop screenshot |
| Harden | Real content or adverse conditions break the UI | Long/localized/missing data, failed requests, repeated actions, and boundary states handled safely |
| Animate | Motion can explain feedback, continuity, or hierarchy | One purposeful motion treatment with reduced-motion behavior; omit if it adds no meaning |
| Polish | The direction and behavior already work | Coherent spacing, typography, alignment, states, icons, and interaction finish across the complete path |

A review-only request produces findings, not edits. A repair request starts with the highest-impact issue and makes the narrowest complete correction. Do not redesign an entire application to fix one surface.

## Inspect the complete task path

Walk from entry to outcome, not only the hero or default screenshot. Use actual product content or explicitly labeled representative fixtures. Do not invent successful network responses, business results, testimonials, or usage metrics to make the design look complete.

| Dimension | Questions and checks |
| --- | --- |
| Task and hierarchy | Is the primary action discoverable? Are its consequence and next step clear? Do heading structure, grouping, proximity, emphasis, and reading order match information importance? Are secondary actions competing with it? |
| Layout and density | Are alignment, spacing rhythm, grid, and whitespace consistent? Can users compare related values without remembering another screen? Does density fit the task rather than forcing every item into a card? |
| Typography | Are role, scale, weight, line height, and line length deliberate? Check real font loading/fallback, CJK and other supported glyphs, zoom, wrapping, long identifiers, numbers/units, and scanability. Do not silently change an approved typeface. |
| Color and material | Check actual foreground/background pairs, including muted text, controls, focus, errors, and translucent overlays. Color must not be the only signal. Glass/blur and soft clay shadows still need clear boundaries and readable content. |
| Accessibility | Check semantic headings, links/buttons, programmatic labels, accessible names, alt text, and state announcements. For WCAG AA, normal text generally needs 4.5:1 contrast, large text 3:1, and relevant control boundaries/state indicators 3:1; document applicability and exceptions rather than asserting compliance from a screenshot. |
| Keyboard and overlays | Complete the task using keyboard: logical focus order, visible and unobscured focus, no trap, correct dialog focus/return, Escape where appropriate, and reachable menus/popovers. Hover cannot be the only way to discover or operate an essential control. |
| Mobile and input | Check narrow, intermediate, and wide layouts; touch targets and spacing, coarse pointers, software keyboard, safe areas, orientation, zoom, scroll ownership, sticky elements, and overflow. Preserve essential information and actions. Emulation is not physical-device evidence. |
| Forms and states | Check default, hover, focus, active/selected, disabled, pending, loading, empty, error, success, and permission states where applicable. Labels survive entered values; errors associate with fields, explain recovery, preserve valid input, and do not rely only on color. Repeated submission must not create duplicate actions. |
| Content and localization | Match visible labels to accessible names and action outcomes. Use complete translatable messages; test realistic long names, CJK, RTL if supported, number/date/currency formats, and expansion. Avoid truncating information required to act. |
| Dense data and performance | Check readable headers, sort/filter/pagination state, numeric alignment/units, large-result behavior, empty results, and retained context. Inspect loading/layout shift, interaction latency, costly blur/paint, image/font cost, and DOM size at the expected data volume. Reuse existing pagination or virtualization only when needed; do not claim speed gains without measurements. |

Run destructive, purchase, publishing, or external-write actions only with explicit authorization and safe fixtures. Preserve permission checks and validation; styling is not a reason to weaken them.

## Concrete inspection and repair protocols

Apply only protocols relevant to the requested surface. The numbers below distinguish accessibility requirements from useful starting points; neither a heuristic score nor a passing screenshot certifies the product.

### Task mode, heuristics, and cognitive load

Classify the **surface**, not the company: **Persuade** helps a visitor decide/act; **Operate** completes work; **Read** supports understanding; **Experience** presents the work itself. A dashboard's marketing page may be Persuade while its editor is Operate. Focal motion and display typography can lead a showcase; task UI earns ambition through speed, precision, and familiar controls.

For critique, inspect these ten lenses against the primary task: system status; user/domain language; control/escape/undo; consistency; error prevention; recognition rather than memory; expert efficiency; purposeful hierarchy; error diagnosis/recovery; contextual help. Record the failed step or element and a concrete fix, not ten generic opinions. Mark irrelevant lenses `n/a` with a reason. If the user wants scores, define the rubric and use `4 × applicable lenses` as the denominator; scores are review judgments, not measured user success.

Check eight cognitive-load questions: single focus, digestible chunks, meaningful grouping, obvious hierarchy, one decision at a time, manageable choices, no memory bridge between screens, and discoverable progressive disclosure. Upstream's four-item working-memory heuristic is a prompt to inspect grouping, not a universal ban on five navigation links or a dense expert table. Reduce extraneous effort without hiding the information the real task requires.

Walk the same task as 2–3 relevant perspectives: first-timer, frequent/power user, keyboard/screen-reader user, interrupted mobile user, or boundary-data tester. Use actual audience evidence; do not invent personas or predict abandonment percentages. Record where each would hesitate, lose work, or fail, then distinguish reasoning from a browser-reproduced failure.

### Measurable baseline and boundary matrix

| Check | Criterion or test input | Correction and verification |
| --- | --- | --- |
| Text contrast | AA: normal text 4.5:1; large text 3:1 (about 24 CSS px regular or 18.7 CSS px bold). Relevant non-text controls/state indicators 3:1, subject to applicable exceptions | Measure the actual composited pair, not raw translucent tokens. Adjust the semantic role, inspect every affected state/theme, and keep color-independent cues |
| Target size | AA SC 2.5.8 generally requires 24 × 24 CSS px or an applicable exception; spacing exception uses a 24px circle centered on the target. 44 × 44px is a useful touch design goal, not the universal AA threshold | Enlarge the hit area or separation without overlapping neighbors. Recheck the actual target and gesture, not just icon dimensions |
| Text stress | 200% zoom; ordinary web body around 1rem/16px unless the task justifies another role; 45–75ch is a prose starting range, not a CJK or data-table law | Remove fixed-height text clipping; use `min-width: 0` on shrinking flex/grid children; preserve zoom and full task-critical content. Check font fallback and the longest supported language |
| Content extremes | Empty, one item, expected maximum; 100+ character names/IDs; 1000+ rows or the actual larger expected dataset; 50+ options when relevant; emoji/CJK and RTL when supported | Reuse pagination/search/virtualization suited to real volume. Avoid loading every record or truncating the only usable identifier. Measure response/scroll behavior at that volume |
| Localization | A 30–40% expansion fixture is a useful stress test, not a guaranteed bound; include locale-specific numbers/dates/plurals | Allow content-sized controls, logical properties, and complete translatable messages. Preserve meaningful Unicode; do not strip joiners or rewrite stored user text for visual convenience |
| Network and concurrency | Slow/offline/timeout; relevant 400/401/403/404/429/500 states; repeated submit (up to ten safe fixture attempts) | Keep valid input, explain recovery, avoid whole-page failure for a local section, and prevent duplicates/races. Never repeat a real payment or external write as a stress test |
| Custom drag controls | Drag through completion; scroll across the control; release outside; second pointer; `pointercancel`, lost capture, and window blur; then drag again | Follow the actual pointer, keep page scroll usable, clear drag state/capture on all exit paths, and record input/engine/device. A resized viewport is not touch evidence |
| Runtime cleanup | Navigate away/back and repeat the interaction; inspect listeners, observers, timers, subscriptions, pending requests, and animation frames | Disconnect/cancel only resources owned by the surface. No detached loops, retained offscreen canvases, or stale responses overwriting newer state |

Keep intrinsic image dimensions/aspect ratios and appropriate responsive sources to avoid layout shift. Do not indiscriminately lazy-load the initially visible/LCP image. Check existing bundle/interaction profiles before adding memoization or dependencies. Enable only supported themes; lack of dark mode is not a defect when it is outside the brief.

### Normalize and polish at the right ownership level

Classify each mismatch before changing it: **missing reusable token**, **one-off implementation of an existing component**, **conceptual task-flow mismatch**, or **local incomplete state**. A local defect gets a local fix; an approved shared primitive stays shared. Do not fix page-specific spacing with global overrides.

Use existing semantic tokens and variant APIs first. Upstream extraction uses three or more repetitions **with the same intent** as a useful signal for a shared abstraction; visual similarity alone is not enough. When authorized extraction is warranted, enumerate consumers, introduce the shared definition, migrate all in-scope instances, verify visual/behavior parity, then remove obsolete code. Do not create a token for every pixel value.

Polish order: blocked/unsafe/inaccessible tasks → missing states → flow/hierarchy/responsive/system drift → visual/motion details → dead-code/assets cleanup. Recheck the whole path, including arrival, save/submit, recovery, permission changes, and adjacent screens. A beautiful default state with a broken error path is unfinished.

### Clarify without removing meaning

For each message identify the fact needed now, next action, decision-changing context, and tone. Actions name their outcome; destructive confirmations name the object and consequence rather than `OK`/`Yes`. Prefer reversible recovery where already supported, not an invented undo promise. Persistent labels remain after input; format rules precede submission; errors say what failed, what is known about why, and how to recover. Empty states distinguish first use, no results/filters, denied access, and failure. Progress and success must reflect real state. Preserve factual/legal meaning and established domain terms.

Distill redundant wrappers, decoration, duplicate labels, and needless steps only when their removal improves the task. Do not inherit upstream's fixed palette/font-count limits, “never nested cards,” mandatory single-column layouts, or sidebar removal as blanket rules. Required data, keyboard labels, recovery, and accessible alternatives remain reachable.

### Purposeful motion parameters and lifecycle

From upstream `skill/reference/animate.md`, use these starting ranges, tuned to the existing motion language rather than applied mechanically:

| Meaning | Starting duration |
| --- | --- |
| Immediate control feedback | 100–150ms |
| Routine state change | 150–300ms |
| Layout, overlay, or view continuity | 300–500ms |
| Deliberate focal entrance | 500–800ms |

Exits are usually faster than entrances. `cubic-bezier(0.16, 1, 0.3, 1)` is an upstream example of an arrival curve; bounce/elastic is not a default. Stagger siblings only when they appear as a meaningful group, and cap total waiting time. Operate/Read surfaces must not make users wait through marketing choreography.

Choose the material by meaning: shared-element/FLIP/view transitions for continuity; bounded depth/blur for focus; clip/mask/crop for reveal; the smallest visible state change for feedback. CSS suits bounded declarative sequences; use Web Animations API or an already installed library for dynamic sequencing/interruption. Scroll-driven effects need a meaningful scroll relationship and a static fallback. Do not add a library just to reproduce a simple transition.

Content is visible before enhancement and when scripts fail. Avoid casual layout-property animation; isolate and bound blur, filters, shadows, canvas, and shaders. `will-change` is temporary and targeted, not an all-page performance fix. Stop nonessential loops offscreen/hidden; disconnect observers, cancel animations/frames/timers, and remove listeners on teardown. A reduced-motion path removes or reduces spatial movement while keeping meaningful state/feedback legible; a global `0.01ms` override is not a designed alternative. Verify interruption, repeated use, keyboard/touch, offscreen pause, reduced motion, and target-device frame behavior. For scene-specific implementation recipes, use the unified skill's motion reference when that task actually needs it.

## Rank by user impact, not personal taste

| Severity | Meaning | Priority |
| --- | --- | --- |
| P0 — blocking | A critical task cannot be completed, or the interface creates a serious data/safety risk | Fix before cosmetic work; stop unsafe validation |
| P1 — major | Significant task friction, inaccessible essential interaction, or an applicable accessibility requirement fails | Address before calling the affected path ready |
| P2 — minor | Local confusion or inconsistency with a practical workaround | Next focused pass |
| P3 — polish | Finish or preference with little demonstrated task impact | Only after higher-impact work |

For each finding record: severity, location, affected user/task, evidence, consequence, smallest fix, and verification. Group repeated issues under their shared cause. State uncertainty; an imagined failure is a hypothesis, not a reproduced defect. Keep 2–3 concrete strengths so fixes do not erase what already works. Avoid unsupported numerical design scores or claims of universal aesthetic superiority.

## Iterate with comparable evidence

1. Record the baseline at the actual target route and state. When browser access is available, capture desktop and narrow-screen screenshots, plus the relevant open overlay or error state. Use the project's approved browser workflow and artifact location. Do not start a service, install packages, deploy, or send page data elsewhere merely to obtain evidence.
2. Select the highest-impact issue or coherent group. State what user-visible improvement the change should produce. Reuse the shared design system and existing implementation; preserve unrelated behavior and routes.
3. Make the smallest complete change. Clarify structure and hierarchy before adding decoration. Motion must explain action/state or a deliberate visual idea, tolerate interruption and repetition, and respect `prefers-reduced-motion`. Prefer existing runtime capabilities; do not add an animation dependency for a simple transition.
4. Repeat screenshots at the same route, viewport, data, theme, and state. Compare the entire affected path, not only a cropped attractive region. Check mobile, keyboard, reduced motion, long content, and state changes affected by the edit. Run the smallest existing relevant static/behavior checks.
5. Check adjacent/shared consumers for regressions, especially overlays, global styles, scroll containers, and focus. If the intervention does not improve the original task, revise or revert it; do not rationalize the new look as success.
6. Stop when scoped acceptance criteria are met and high-impact findings are resolved or explicitly blocked. Do not run endless aesthetic passes or silently expand the scope.

A screenshot supports a visual observation, not successful form submission or backend persistence. A clean static check does not establish usable keyboard navigation. If no approved preview/browser exists, report the visual and interaction checks as blocked; do not manufacture a pass.

## Report evidence honestly

Use distinct labels:

- **Static finding** — source/token/semantic evidence with file and line; runtime consequence remains untested unless separately observed.
- **Browser verified** — actual route, viewport, browser/input method, content/state, action, and observed outcome; include before/after artifact locations when captured. Identify emulated versus physical-device checks.
- **Unverified / blocked** — exact check not run, why, and what evidence is needed. A proposed fix or visual preference belongs here until tested.

Compact handoff:

```text
Scope and primary task:
Kept intact:
[P1] Location — affected task — evidence label — consequence — fix
Before/after evidence and checks actually run:
Resolved / remaining issues:
Unverified checks and limitations:
```

Do not mark a page functional, accessible, performant, or faithful solely because it looks better. Report the specific task outcome actually observed and leave untested claims explicit.
