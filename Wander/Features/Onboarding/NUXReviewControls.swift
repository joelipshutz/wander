import SwiftUI

#if DEBUG
struct NUXReviewControls: View {
    @AppStorage("nux.review.manual") private var manual = false
    let replay: (WalkthroughTargetID) -> Void

    var body: some View {
        Menu {
            Menu("Playback · applies on replay") {
                Toggle("Advance manually", isOn: $manual)
                Text("Slide/fade · original quote · 5 seconds")
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
