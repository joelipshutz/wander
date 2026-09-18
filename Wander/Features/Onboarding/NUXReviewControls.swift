import SwiftUI

#if DEBUG
struct NUXReviewControls: View {
    @AppStorage("nux.review.manual") private var manual = false
    @AppStorage("nux.review.motion") private var motion = "pop"
    @AppStorage("nux.review.originalQuote") private var originalQuote = false
    @AppStorage("nux.review.finaleSeconds") private var finaleSeconds = 6
    let replay: (WalkthroughTargetID) -> Void

    var body: some View {
        Menu {
            Menu("Playback · applies on replay") {
                Toggle("Advance manually", isOn: $manual)
                Picker("Coach motion", selection: $motion) {
                    Text("Pop and settle").tag("pop")
                    Text("Slide and fade").tag("slide")
                }
                Toggle("N25 · Original quote", isOn: $originalQuote)
                Picker("N25 · Duration", selection: $finaleSeconds) {
                    Text("4 seconds").tag(4)
                    Text("6 seconds").tag(6)
                }
            }
            Menu("Map tour") {
                scene("M01 · Featured / replay", .mapFeatured)
                scene("M02 · Friends", .mapFriends)
                scene("M03 · More", .mapMoreFilters)
                scene("M04 · Search", .mapSearch)
                scene("M05 · Plus", .mapAdd)
                scene("M06 · Pin legend", .mapPinLegend)
                scene("N25 · Map ending", .mapSendoff)
            }
            Menu("First voluntary visits") {
                scene("C01 · Nearby Places", .addNearby)
                scene("C02 · Feed", .feedActivity)
                scene("C03 · Lists", .listsScope)
                scene("C04 · Check In / Wanna", .placeSaveActions)
            }
        } label: {
            Label("Scenes", systemImage: "play.rectangle")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 44)
                .background(.regularMaterial, in: Capsule())
        }
        .accessibilityIdentifier("nux.review.scenes")
    }

    private func scene(_ title: String, _ target: WalkthroughTargetID) -> some View {
        Button(title) { replay(target) }
    }
}
#endif

/// Kept opt-in while the Feed scroll treatment is being evaluated.
enum NUXFeedRevealPolicy {
    static var isEnabled: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-WanderNUXReview") || args.contains("-WanderNUXFeedReveal")
        #else
        return false
        #endif
    }
}
