# Feed activity scenarios

A standalone native SwiftUI review gallery for REC-494. Open `index.html` to
compare simulator captures without an iPhone. The gallery has six scenarios,
including collapsed and expanded captures for the combined and multiple-list
cases.

The mock app compiles the **production `FeedActivityDisclosure.swift`** directly.
The surrounding postcard, vector storefront, sample events, and destination
sheets are preview-only. `MockSupport.swift` supplies isolated type adapters;
it does not replace production types or exercise production grouping logic.
The scenario fixtures illustrate the grouping contract already covered by
`FeedModelsTests`.

## Run the interactive SwiftUI app

From this directory:

```sh
xcodegen generate --spec project.yml
open FeedActivityMock.xcodeproj
```

Choose `FeedActivityMock` and an iPhone simulator. No account, backend, package
dependencies, or signing is needed for simulator use. The scenario tabs switch
examples; View activity expands and collapses; list and event rows open sample
destination sheets. The sun/moon button changes appearance. Launch with
`--scenario 0` through `--scenario 5` to select an example, and `--light` for
Light appearance. `#Preview` is also available in `FeedActivityMock.swift`.

Validation: the standalone arm64 simulator build passed, all six scenarios
were visually inspected on iPhone 16 Plus, and the production disclosure was
expanded and collapsed. The broader application automated-test gate remains
documented in PR #632; this gallery does not resolve it.
