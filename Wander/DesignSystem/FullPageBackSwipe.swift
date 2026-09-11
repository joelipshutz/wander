import SwiftUI

enum FullPageBackSwipePolicy {
    static func canBegin(velocity: CGPoint) -> Bool {
        velocity.x > 0 && velocity.x > abs(velocity.y)
    }

    static func shouldComplete(translation: CGFloat, velocity: CGFloat, width: CGFloat) -> Bool {
        guard width > 0, translation > 0 else { return false }
        return translation >= width * 0.3
            || (translation >= 24 && velocity > 600)
    }
}

extension View {
    /// Opt in only at a full-page boundary, never on a sheet or inline step.
    func fullPageBackSwipe(isEnabled: Bool = true, containerOffset: Binding<CGFloat>? = nil, onBack: @escaping () -> Void) -> some View {
        modifier(FullPageBackSwipeModifier(isEnabled: isEnabled, containerOffset: containerOffset, onBack: onBack))
    }
}

private struct FullPageBackSwipeModifier: ViewModifier {
    let isEnabled: Bool
    let containerOffset: Binding<CGFloat>?
    let onBack: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var offset: CGFloat = 0
    @State private var isVisible = false
    @State private var isCompleting = false
    @State private var completionID = UUID()
    @GestureState private var isDragging = false
    @State private var tracking: Bool?

    private var translation: Binding<CGFloat> { containerOffset ?? $offset }
    private var canSwipe: Bool { isEnabled && isVisible && !isCompleting && scenePhase == .active }

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .offset(x: containerOffset == nil ? offset : 0)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8, coordinateSpace: .global)
                        .updating($isDragging) { _, active, _ in active = true }
                        .onChanged { value in
                            guard canSwipe else { return }
                            if tracking == nil {
                                tracking = value.startLocation.x <= 24
                                    && FullPageBackSwipePolicy.canBegin(velocity: CGPoint(
                                        x: value.translation.width, y: value.translation.height
                                    ))
                            }
                            guard tracking == true else { return }
                            translation.wrappedValue = min(geometry.size.width, max(0, value.translation.width))
                        }
                        .onEnded { value in
                            let shouldComplete = canSwipe && tracking == true
                                && FullPageBackSwipePolicy.shouldComplete(
                                    translation: value.translation.width,
                                    velocity: value.velocity.width,
                                    width: geometry.size.width
                                )
                            tracking = nil
                            guard shouldComplete else { restore(); return }
                            isCompleting = true
                            let id = UUID()
                            completionID = id
                            withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.16)) {
                                translation.wrappedValue = geometry.size.width
                            } completion: {
                                guard completionID == id, isVisible, isEnabled else { return }
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) { onBack() }
                            }
                        }
                )
        }
        .onChange(of: isDragging) { _, active in
            if !active && !isCompleting { restore() }
        }
        .onAppear { isVisible = true; restore() }
        .onDisappear { isVisible = false; restore() }
        .onChange(of: isEnabled) { _, enabled in if !enabled { restore() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { restore() } }
    }

    private func restore() {
        completionID = UUID()
        isCompleting = false
        tracking = nil
        withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.2)) { translation.wrappedValue = 0 }
    }
}
