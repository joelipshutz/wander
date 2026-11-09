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
        // Choose from detents beyond the finger's current position. A long drag
        // can cross both detents without snapping back against its release.
        // Velocity supplies direction, not a license for a tiny flick to skip
        // the middle stop. Only finger travel can cross an intermediate detent.
        let candidates = heights.indices.filter { travel < 0 ? heights[$0] > currentHeight : heights[$0] < currentHeight }
        return candidates.min { abs(heights[$0] - currentHeight) < abs(heights[$1] - currentHeight) }
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
    var dragHandleHeight: CGFloat? = nil
    let onDetent: (Int) -> Void
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState(resetTransaction: Transaction(animation: .snappy(duration: 0.3))) private var translation: CGFloat = 0
    var body: some View {
        VStack(spacing: 0) {
            draggableHeader
            content()
        }
        // Keep the expensive Feed viewport stable during touch samples. Only
        // the outer reveal window changes; the Feed resizes at the next detent.
        .frame(height: height, alignment: .top)
        .frame(height: enabled ? LiveDrawerDragPolicy.height(base: height, translation: translation,
                                                              minimum: minimum, maximum: maximum) : height,
               alignment: .top)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil; transaction.disablesAnimations = true }
        }
    }

    @ViewBuilder private var draggableHeader: some View {
        if let dragHandleHeight {
            // Keep native Menu/Button taps outside the drag recognizer in the
            // compact review header, as the existing overlaid shortcuts are.
            header()
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) {
                    Color.clear.frame(height: dragHandleHeight)
                        .contentShape(Rectangle())
                        .gesture(drawerDrag)
                        .accessibilityHidden(true)
                }
        } else {
            header()
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(drawerDrag)
        }
    }

    private var drawerDrag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
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
            }
    }
}

/// Location is independent of the shared filters. Keep both the current scope
/// and its reset action reachable even when the activity drawer is collapsed.
struct LiveFeedScopeControls: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let scope: LiveFeedLocationScope
    let summary: String
    let showsReset: Bool
    let onScope: (LiveFeedLocationScope) -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                scopeButtons
                if showsReset { resetButton }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        scopeButtons
                        Spacer(minLength: 0)
                        if showsReset { resetButton }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        scopeButtons
                        if showsReset { resetButton }
                    }
                }
            }
            Text(summary).font(AstirTypography.caption)
                .foregroundStyle(brand.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("live.filter.summary")
        }
        .buttonStyle(.plain)
    }

    private var scopeButtons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            ForEach(LiveFeedLocationScope.allCases) { option in
                Button { onScope(option) } label: {
                    Text(option.title)
                        .font(AstirTypography.bodySmall.weight(scope == option ? .semibold : .regular))
                        .foregroundStyle(scope == option ? brand.accentText : brand.primaryText)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) {
                            if scope == option { Rectangle().fill(brand.accent).frame(height: 2) }
                        }
                }
                .accessibilityAddTraits(scope == option ? .isSelected : [])
                .accessibilityValue(scope == option ? "Selected" : "")
                .accessibilityIdentifier("live.feed.scope.\(option.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity location")
    }

    private var resetButton: some View {
        Button("Reset filters", action: onReset)
            .font(AstirTypography.bodySmall)
            .foregroundStyle(brand.accentText)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 44)
            .accessibilityHint("Clears people, category, activity and time filters. Keeps the selected area.")
            .accessibilityIdentifier("live.resetFilters")
    }
}
