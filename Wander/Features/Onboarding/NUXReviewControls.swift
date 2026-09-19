import SwiftUI

#if DEBUG
struct NUXReviewControls: View {
    @AppStorage("nux.review.manual") private var manual = false
    let replay: (WalkthroughTargetID) -> Void

    var body: some View {
        Menu {
            Menu("Playback · applies on replay") {
                Toggle("Advance manually", isOn: $manual)
                Text("Map → your Feed · Next or automatic")
            }
            Menu("Map tour") {
                scene("M01 · Featured / replay", .mapFeatured)
                scene("M02 · Friends", .mapFriends)
                scene("M03 · More", .mapMoreFilters)
                scene("M04 · Search", .mapSearch)
                scene("M05 · Plus", .mapAdd)
                scene("M06 · Pin legend", .mapPinLegend)
            }
            Menu("Feed and first-use hints") {
                scene("C01 · Nearby search", .addNearby)
                scene("C01 · Import saved places", .addImport)
                scene("C02 · Feed", .feedActivity)
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
