# REC-236 iOS Design Review

Date: 2026-08-09
Branch: `codex/rec-236-onboarding-walkthroughs`
Scope: first-visit walkthrough, the complete add-place save flow, and the place-memory lesson

## Review Method

No paired physical iPhone was available, so the live-device review used the strongest available fallback: automated SwiftUI interaction and screenshot inspection on iPhone 17 and iPhone 17e simulators running iOS 26.5. The documented iPhone 16 Plus / iOS 18.6 simulator is not installed on this machine.

The reviewed captures were produced by `OnboardingUITests` and cover:

- `REC-236 full save flow rating step`
- `REC-236 full save flow optional details`
- `REC-236 seeded place memory fallback`

## Findings

| Dimension | Result | Evidence |
|---|---|---|
| Caret alignment | Pass | Every reviewed card connects directly to its highlighted rating, tags, or place-memory surface. |
| Scrim coverage | Pass | The non-highlighted viewport remains consistently dimmed from status bar through bottom navigation. |
| Card sizing | Pass | Copy-driven cards fit without the prior unused vertical space and remain readable on iPhone 17e. |
| Save-flow completeness | Pass | The walkthrough covers date, place type, rating, friends, photos, More Options, note, tags, privacy, and final submission. Optional fields use Next; More Options and submission require the described action. |
| Place-memory realism | Pass | A completed tutorial save is preferred. Otherwise the walkthrough presents an ordinary, fully populated check-in card rather than a detached or fake-looking map annotation. |
| Interaction discipline | Pass | Passive lessons expose Next. Action steps block the rest of the screen and advance only through the highlighted control. |
| Accessibility baseline | Pass with follow-up | Existing labels and 44pt controls remain intact. Physical-device VoiceOver and large Dynamic Type verification remain outstanding. |

No P0 or P1 visual defect was found in the reviewed flows. The compact layout does not clip the coach card or highlighted content, and the place-memory card remains above the bottom navigation.

## Validation

- Full test suite: 974 passed, 0 failed, 0 skipped on iPhone 17 / iOS 26.5.
- Focused onboarding UI pass: 2 passed on iPhone 17.
- Compact onboarding UI pass: 2 passed on iPhone 17e.
- Xcode result: `DerivedData/Logs/Test/Test-Wander-2026.08.09_00-19-26--0700.xcresult`.

## Status

`DONE_WITH_CONCERNS`: simulator acceptance is met on regular and compact phones. A physical-device pass remains advisable for VoiceOver, Dynamic Type, and real touch behavior before release.
