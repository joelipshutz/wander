import SwiftUI

enum LiveDrawerDragPolicy {
    static func height(base: CGFloat, translation: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(maximum, max(minimum, base - translation))
    }
    static func target(start: Int, translation: CGFloat, predicted: CGFloat) -> Int {
        let travel = abs(predicted) > abs(translation) ? predicted : translation
        guard abs(travel) >= 24 else { return start }
        return min(2, max(0, start + (travel < 0 ? 1 : -1)))
    }
}

/// Only this lightweight shell tracks touch samples. The map and Feed projections
/// stay stable until the finger releases and the next detent is committed.
struct LiveFeedDrawer<Header: View, Content: View>: View {
    let height: CGFloat
    let minimum: CGFloat
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
                            translation: value.translation.height, predicted: value.predictedEndTranslation.height))
                    })
            content()
        }
        .frame(height: enabled ? LiveDrawerDragPolicy.height(base: height, translation: translation,
                                                              minimum: minimum, maximum: maximum) : height,
               alignment: .top)
    }
}
