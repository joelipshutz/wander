# REC-373 SwiftUI mockup

Design-only checkpoint for making Feed Featured tile photos full-bleed on the
top, leading, and trailing edges. It records the visual checkpoint that preceded
the matching production `FeedFeaturedCard` implementation.

Geometry used in the mockup:

- Card width: 184 pt (unchanged)
- Card height: 226 pt (fixed to the current rendered height)
- Baseline photo: 88 pt tall with 12 pt card padding
- Proposed photo: 100 pt tall, reclaiming the 12 pt top inset while keeping the
  photo's lower edge and the card's lower edge in place
- Text/social content: 12 pt inset below the photo (unchanged)

`FeedFeaturedFullBleedMockup.swift` is intentionally kept outside the app target.
The screenshots were rendered from this view in a temporary debug-only launch
harness, then that harness was removed before the production implementation was
added.

Rendered references:

- `featured-full-bleed-swiftui.png`: iPhone 17 Pro
- `featured-full-bleed-small-phone.png`: iPhone SE (3rd generation)
