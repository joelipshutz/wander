# Quick capture exploration — REC-680

Native SwiftUI proposal for a compact Check-in / Wanna sheet with optional
enrichment. This is a separate simulator app, outside the production target.
It uses sample place/person/list data, in-memory saves, and MapKit context.
It never connects to an Astir account, emits analytics, or writes app data.

## Run

```sh
bash preview/rec-680/render-build.sh /private/tmp/rec680-native
xcrun simctl install <simulator-id> /private/tmp/rec680-native/QuickCapturePreview.app
xcrun simctl launch <simulator-id> com.astir.preview.quickcapture --screen quick
```

Launch states: `quick`, `later`, `details`, `wanna`, `saved`, `edit`.
Add `--dark` or `--large-text` for appearance/accessibility captures.
Terminate the harness between deterministic launch states.

The save button dismisses the sheet to a visit card. Add details reopens the
same in-memory record; opening the rating chooser does not assign a score.
Rating choices include all nine half-step values from 1 through 5, plus Remove
rating. Notes, date, audience, silent state and sample section choices are
interactive. Photo picking/upload, invitations, question customization, lists,
search, sync, durable drafts and other app navigation are illustrative only.

`Friends` is the sample account's audience, not a proposed new global default.
The captured place is fictional. Map position supplies visual context only;
the harness does not request device location or verify a visit.

See [the proposal](../../docs/designs/rec-680-quick-capture.md) for product,
data and rollout decisions. Native captures are evidence of visual layout,
not evidence that the production save path supports unrated visits.
