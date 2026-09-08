# Compact Add sheet approval preview

Approved native SwiftUI design checkpoint for REC-446. `compact.png` is the
approved iPhone 17 Pro screenshot with the MapKit background loaded.

The production AddScreen now follows this proposal: remove the flexible spacer
between Suggested and Import, use a 16-point section gap, and measure the
content to set the resting detent. The 44-point See more control and production
nearby resolver are unchanged. Back to add options restores the measured
resting detent; larger content can scroll or expand to full height.

`CompactAddPreview.swift` is a standalone visual harness outside the app target,
with sample places and illustrative import marks. It does not run production
search, import, or save services. `render-build.sh` compiles it for an arm64 iOS
simulator. The optional `--roundtrip` argument exercises its presentation
states; production behavior is covered by
`AppStoreScreenshotsUITests.testAddOptionsRestoresCompactHeightAfterSeeMore`.

Current validation and merge evidence belong in REC-446 and its PR.
