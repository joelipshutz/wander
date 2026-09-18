# Native NUX implementation review

Scope: finish the existing PR #663 SwiftUI review, using the T04/T05 brief and
the production Map, Plus, Feed, Lists and place-profile surfaces. Reuse the
existing coordinator, account-scoped enrollment, anchor preferences, native
controls and debug Scenes menu. Sequential implementation: the work shares
the walkthrough coordinator and its view overlays.

## Engineering review

```
new-user enrollment -> M01..M06 -> N25 -> usable Map
                           | actual navigation
                           +---------------------> usable chosen surface
voluntary entry -> C01 / C02 / C03 / C04 -> dismiss or real action
debug Scenes -> replay same coordinator and production views
```

- Architecture: keep demonstration models detached from SwiftData; never create
  a personal save, follow or remote list to illustrate onboarding. Preserve
  native action handlers and the existing analytics boundary.
- Code quality: the More demonstration scrolls to `nux.more.bottom`, but the
  existing panel does not attach that ID. Add the actual destination. Keep
  layout calculations bounded by safe areas and measured content.
- Tests: verify Next and automatic progression, real control taps, ending on
  usable Map, demo cleanup, replay, and contextual dismissal. Confirm the
  previous You-filter failure against the current simulator before changing
  its wait or hit-testing behavior. Unit tests cover deterministic layout and
  state policies; UI tests exercise native handlers, not duplicate logic.
- Performance: bounded demo pins and at most twenty existing Feed groups; no
  extra server fetches. Cancel timed motion when leaving the surface, changing
  appearance/accessibility behavior or interacting. Avoid continuous animation
  in the handwritten hints.

Failure checks: missing target anchors must not trap navigation; More scrolling
must actually move; short/empty Feed must remain truthful; replay must not reuse
stale scene state; large text must not push Next or copy outside the viewport.

## Design review

| Pass | Starting assessment | Implementation requirement |
| --- | --- | --- |
| Hierarchy | 8/10 | One target, one explanation, top-right Next; retain visible Map. |
| Interaction states | 7/10 | Real taps work; short/empty/denied content stays truthful. |
| Journey | 9/10 | End on Map; other lessons require voluntary entry. |
| Specificity | 9/10 | Actual native controls and ring styles; no substitute screens. |
| Design system | 8/10 | Adaptive Astir paper/ink, coral, editorial type and local glass. |
| Accessibility | 6/10, unverified | Current/compact phones, both appearances, large text, manual Reduce Motion/VoiceOver path. |
| Unresolved choices | Reviewable | Pop/slide and original/connection finale remain selectable. |

The desired arc is orientation on Map, recognition of the controls, a short
connection-focused ending, then freedom to use the app. Nearby and place-action
annotations remain stationary after entrance and do not intercept controls.

## Delivery and boundaries

Deliver a launchable native review, continuous simulator recordings, and stills
for the same M01–M06/N25/C01–C04 identifiers. Record actual validation results,
including failures and runtime differences, separately from design approval.

Starter-list names/content/ownership, N27 hardware demonstrations, and the
N28/N29 permission product decision are not silently resolved by this pass.
Existing setup-guide and conditional permission behavior remain available.
Final creative selection and production merge are separate from this review.

## Findings resolved during native verification

- Attached the More scroll destination to its real explanatory footer. Selecting
  a category exits the demonstration through the selection handler, preserving
  the choice without an ancestor tap gesture competing with native buttons.
- Restored the complete Feed content inset after the optional reveal, and made
  scene activity and Reduce Motion changes cancel the running task.
- Limited coach accessibility grouping to the actual card/labels. A full-screen
  accessibility container made underlying controls fail hittability checks.
  The strengthened C04 test now opens the real Check In editor.
- Bound Next callbacks to their originating step. A callback from an outgoing
  coach must not advance the newly entered step; a regression test covers it.
- Grouped Scenes into three native submenus so playback choices and individual
  lessons remain manageable on an iPhone.

Actual test counts, outstanding performance thresholds, capture limitations and
restart commands are maintained in [native-validation.md](native-validation.md).
