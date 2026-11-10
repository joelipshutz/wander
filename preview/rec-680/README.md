# Quick capture and later editing — REC-680

A real native SwiftUI design harness, built as a separate simulator app outside
the production target. Fictional places/people/lists, in-memory state, MapKit
context. No account, analytics, backend writes or scheduled notifications.

## Build and run

```sh
bash preview/rec-680/render-build.sh /private/tmp/rec680-native
xcrun simctl install <simulator-id> /private/tmp/rec680-native/QuickCapturePreview.app
xcrun simctl launch <simulator-id> com.astir.preview.quickcapture --screen invitation
```

Start with `invitation` to explore Map → Add details, or `profile` to explore
Profile → Your check-ins → a dated visit. Tap the place profile's Your visits
section to distinguish multiple check-ins at the same place. Save changes
updates the selected event without changing its timestamp or history position.

## Deterministic launch states

| Area | `--screen` values |
|---|---|
| Capture | `quick`, `later`, `details`, `saved` |
| Return | `invitation`, `profile`, `history`, `place`, `visits`, `visit` |
| Editing | `edit`, `rated`, `options` (scrolled optional fields), `updated` |
| Reminder | `notification` (clearly labeled concept), `reminders`, `push-edit` |
| Wanna | `wanna`, `wanna-saved`, `wannas`, `wanna-detail`, `wanna-edit`, `wanna-details` |

Terminate between deterministic states. Add `--dark` or `--large-text`
(accessibility1) for adaptive captures. Large text is applied to the sheet too.

The native slider reads an optional `PreviewRating`: its neutral visual value
is 3 but its stored value is nil. Opening or saving without touching it never
rates a visit. Touching the thumb deliberately selects the midpoint; adjustment
selects half points. Remove rating restores nil. An existing explicit score is
preserved when editing other fields.

Notes, dates, audience, reminder preference, sample selections and navigation
work in memory. Notification preview taps route to the sample event editor;
this is not an APNs or OS banner test. Photo uploads, invitations, full question
customization, sync and durable drafts reuse production contracts in a future
implementation. Discover and unrelated profile capabilities are outside this
scoped harness. `Friends` is the sample account audience, not a global default.

## Model check

```sh
xcrun swiftc preview/rec-680/PreviewModels.swift preview/rec-680/check-model.swift \
  -o /private/tmp/rec680-model-check
/private/tmp/rec680-model-check
```

Covers untouched/midpoint/fractional/cleared ratings, notes without ratings,
stable ID/time/order during edits, existing-score preservation and invitation
eligibility. It does not validate the production save boundary.

## Reproduce screenshots

Use dedicated booted simulators; do not interrupt another task's devices.

```sh
python3 preview/rec-680/capture.py <large-simulator-id> /private/tmp/rec680-captures/large
python3 preview/rec-680/capture.py <compact-simulator-id> /private/tmp/rec680-captures/compact --compact
swift preview/rec-680/compose.swift /private/tmp/rec680-captures /private/tmp/rec680-boards
```

The capture script supports `--only invitation,edit` and `--delay 20` for slower
startup. Inspect resulting images; process completion alone does not guarantee
that a sheet finished appearing. Board composition only scales the original
simulator images and adds captions. Raw images stay outside Git; final boards
must pass `scripts/check-review-storage.py`.

See [the proposal](../../docs/designs/rec-680-quick-capture.md) for the complete
screen set, product tradeoffs, event identity, reminder policy and rollout.
