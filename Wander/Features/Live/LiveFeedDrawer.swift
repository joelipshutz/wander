import SwiftUI

enum LiveDrawerDragPolicy {
    static func height(base: CGFloat, translation: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(maximum, max(minimum, base - translation))
    }
    static func target(start: Int, translation: CGFloat, predicted: CGFloat, heights: [CGFloat]) -> Int {
        guard heights.count == 3, heights.indices.contains(start),
              heights.allSatisfy(\.isFinite), translation.isFinite, predicted.isFinite,
              heights[0] <= heights[1], heights[1] <= heights[2] else { return start }
        let remainingTravel = predicted - translation
        let flick = abs(remainingTravel) >= 24
        let travel = flick ? remainingTravel : (abs(predicted) > abs(translation) ? predicted : translation)
        guard abs(travel) >= 24 else { return start }
        let currentHeight = height(base: heights[start], translation: translation,
                                   minimum: heights[0], maximum: heights[2])
        let projectedHeight = flick ? currentHeight - remainingTravel : currentHeight
        // Choose from detents beyond the finger's current position. A long drag
        // can cross both detents without snapping back against its release.
        let candidates = heights.indices.filter { travel < 0 ? heights[$0] > currentHeight : heights[$0] < currentHeight }
        return candidates.min { abs(heights[$0] - projectedHeight) < abs(heights[$1] - projectedHeight) }
            ?? (travel < 0 ? 2 : 0)
    }
}

/// Only this lightweight shell tracks touch samples. The map and Feed projections
/// stay stable until the finger releases and the next detent is committed.
struct LiveFeedDrawer<Header: View, Content: View>: View {
    let height: CGFloat
    let minimum: CGFloat
    let middle: CGFloat
    let maximum: CGFloat
    let detent: Int
    let enabled: Bool
    let onDetent: (Int) -> Void
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @GestureState private var translation: CGFloat = 0
    var body: some View {
        VStack(spacing: 0) {
            header()
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3)
                    .updating($translation) { value, state, transaction in
                        guard enabled else { return }
                        transaction.animation = nil
                        state = value.translation.height
                    }
                    .onEnded { value in
                        guard enabled else { return }
                        onDetent(LiveDrawerDragPolicy.target(start: detent,
                            translation: value.translation.height, predicted: value.predictedEndTranslation.height,
                            heights: [minimum, middle, maximum]))
                    })
            content()
        }
        .frame(height: enabled ? LiveDrawerDragPolicy.height(base: height, translation: translation,
                                                              minimum: minimum, maximum: maximum) : height,
               alignment: .top)
    }
}
