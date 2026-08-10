# REC-236 iOS Design Review

Date: 2026-08-09
Branch: `codex/rec-236-onboarding-walkthroughs`
Scope: first-visit walkthrough, the complete add-place save flow, page-to-page guidance, launch lessons, and final Map sendoff

## Review Method

No paired physical iPhone was available, so the live-device review used the strongest available fallback: automated SwiftUI interaction and screenshot inspection on iPhone 17 and iPhone 17e simulators running iOS 26.5. The documented iPhone 16 Plus / iOS 18.6 simulator is not installed on this machine.

The reviewed captures were produced by `OnboardingUITests` and cover:

- `REC-236 selectable multiple place results`
- `REC-236 neutral Check In or Wanna Go choice`
- `REC-236 editable save flow rating step`
- `REC-236 all tags selected without blocking save`
- `REC-236 seeded place memory fallback`
- `REC-236 connected bottom-tab coach mark`
- `REC-236 list map focused place-card lesson`
- `REC-236 Profile history passive coach mark`
- `REC-236 final Map sendoff`

## Findings

| Dimension | Result | Evidence |
|---|---|---|
| Caret alignment | Pass | Every reviewed card connects directly to its highlighted result list, save control, navigation pill, profile section, or final Map search surface. |
| Scrim coverage | Pass | The non-highlighted viewport remains consistently dimmed from status bar through bottom navigation. Multi-result search exposes the complete selectable result group, and Profile exposes the complete Activity section. |
| Card sizing | Pass | Copy-driven cards fit without the prior unused vertical space and remain readable on iPhone 17e. |
| Search-result choice | Pass | Multiple matching places remain visible and tappable inside one spotlight, and the selected candidate is the one carried into the save flow. |
| Status choice | Pass | Check In and Wanna Go begin visibly unselected. Continue to Details is absent until the user chooses either status, and both choices complete their relevant save flow. |
| Save-flow completeness | Pass | The walkthrough covers date, place type/category/cuisine, rating, friends, photos, More Options, note, tags/labels, privacy, and final submission. Optional fields remain interactive and use Next; More Options and submission require the described action. |
| Tag stability | Pass | The tag lesson uses one stable toggle grid instead of moving tags between selected and suggestion shelves. The complete visible grid is spotlighted, overflow can scroll inside the spotlight, and an end-to-end test selects every suggestion before continuing through privacy and Save. |
| Place-memory realism | Pass | A completed tutorial save is preferred. Otherwise the walkthrough presents an ordinary, fully populated check-in card rather than a detached or fake-looking map annotation. |
| List-map place card | Pass | Opening a list map advances to a dedicated place-card lesson, focuses the tutorial-saved place when that place belongs to the list, and otherwise uses the first current-user place. Next returns to list detail for the actions lesson. |
| Navigation continuity | Pass | Import Next dismisses Add automatically; the walkthrough routes Map → Feed → Lists → Profile and finishes back on Map with a motivating prompt. |
| Interaction discipline | Pass | Passive lessons expose Next. Required actions advance through the highlighted control, while save-detail spotlights allow the highlighted controls to remain editable. |
| Accessibility baseline | Pass with follow-up | Existing labels and 44pt controls remain intact. Physical-device VoiceOver and large Dynamic Type verification remain outstanding. |

No P0 or P1 visual defect was found in the reviewed flows. The compact layout does not clip coach cards or highlighted content. The bottom-navigation spotlight includes the complete native floating pill, the tag grid and Next button remain usable after every tag is selected, the list-map place card is fully exposed, the Profile Activity spotlight includes visible history rows, and the final sendoff remains fully visible above the Map.

## Validation

- Full combined suite: 979 passed, 0 failed, 0 skipped on iPhone 17 / iOS 26.5 (959 unit tests and 20 UI tests).
- Compact targeted UI pass: neutral status choice, every-tag selection followed by a successful save, native tab spotlight, and list-map place-card lesson passed on iPhone 17e / iOS 26.5.
- Focused shared-anchor regression: Map search and final Map sendoff both passed after consolidating their context-aware target.
- Xcode result: `DerivedData/Logs/Test/Test-Wander-2026.08.09_22-53-46--0700.xcresult`.

## Status

`DONE_WITH_CONCERNS`: simulator acceptance is met on regular and compact phones. A physical-device pass remains advisable for VoiceOver, Dynamic Type, and real touch behavior before release.
