import SwiftUI

enum NUXCoachMotion: String, CaseIterable {
    case pop, slide

    static let selected: Self = .slide

    var transition: AnyTransition {
        switch self {
        case .pop: .asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity),
                              removal: .offset(y: -10).combined(with: .opacity))
        case .slide: .asymmetric(insertion: .offset(y: 18).combined(with: .opacity),
                                removal: .offset(y: -14).combined(with: .opacity))
        }
    }
}

enum NUXPlaceIntroductionTiming {
    static let arrivalMilliseconds = 450
    static let focusMilliseconds = 3_500
    static let glimmerMilliseconds = 1_400
    static let blurRadius: CGFloat = 6
}

private struct NUXPlaceIntroductionFocusKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var nuxPlaceIntroductionIsFocused: Bool {
        get { self[NUXPlaceIntroductionFocusKey.self] }
        set { self[NUXPlaceIntroductionFocusKey.self] = newValue }
    }
}

/// A single first-visit moment: arrive, soften the actual page for 3.5
/// seconds, then sweep the two still-live native buttons once. No Next/Skip.
struct NUXPlaceActionIntroduction: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasStarted = false
    @State private var isGlimmering = false
    @State private var glimmerProgress: CGFloat = 0
    let step: WalkthroughStep
    let target: CGRect
    let additionalTargets: [WalkthroughTargetID: CGRect]
    let size: CGSize
    let safeTop: CGFloat
    @Binding var isFocused: Bool
    let finish: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isFocused {
                NUXGuidanceOverlay(step: step, target: target, additionalTargets: additionalTargets,
                                   size: size, safeTop: safeTop, next: {}, showsNext: false)
                    .transition(.opacity)
            }
            if isGlimmering, !reduceMotion {
                ForEach([WalkthroughTargetID.placeCheckIn, .placeWanna], id: \.rawValue) { id in
                    if let frame = additionalTargets[id] {
                        NUXButtonGlimmer(progress: glimmerProgress)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                if hasStarted {
                    isFocused = false
                    finish()
                }
                return
            }
            guard !hasStarted else { return }
            hasStarted = true
            do {
                try await Task.sleep(for: .milliseconds(NUXPlaceIntroductionTiming.arrivalMilliseconds))
                withAnimation(.easeInOut(duration: 0.2)) { isFocused = true }
                // Only deterministic screenshot/review mode can hold the moment.
                guard !FirstVisitWalkthroughContent.holdsAutomaticAdvanceForCapture else { return }
                try await Task.sleep(for: .milliseconds(NUXPlaceIntroductionTiming.focusMilliseconds))
                withAnimation(.easeInOut(duration: 0.2)) { isFocused = false }
                try await Task.sleep(for: .milliseconds(200))
                if !reduceMotion, !UIAccessibility.isVoiceOverRunning {
                    isGlimmering = true
                    await Task.yield()
                    withAnimation(.easeInOut(duration: Double(NUXPlaceIntroductionTiming.glimmerMilliseconds) / 1_000)) {
                        glimmerProgress = 1
                    }
                    try await Task.sleep(for: .milliseconds(NUXPlaceIntroductionTiming.glimmerMilliseconds))
                }
                finish()
            } catch {
                isFocused = false
            }
        }
        .onDisappear { isFocused = false }
    }
}

private struct NUXButtonGlimmer: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(colors: [.clear, .white.opacity(0.65), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 32, height: hypot(proxy.size.width, proxy.size.height) * 2)
                .rotationEffect(.degrees(-45))
                .position(x: proxy.size.width * (-0.45 + 1.9 * progress),
                          y: proxy.size.height * (1.45 - 1.9 * progress))
        }
        .clipShape(RoundedRectangle(cornerRadius: PlaceProfileFloatingActions.compactCornerRadius))
        .accessibilityHidden(true)
    }
}

enum NUXFeedScrollTarget: Equatable {
    case top, recent
}

enum NUXFeedIntroductionTiming {
    static let arrivalMilliseconds = 200
    static let readinessMilliseconds = 350
    static let focusMilliseconds = 2_200
    static let clearMilliseconds = 150
    static let scrollMilliseconds = 350
    static let totalMilliseconds = arrivalMilliseconds + focusMilliseconds * 2 + clearMilliseconds * 2 + scrollMilliseconds * 2
}

enum NUXFeedFocus: String, CaseIterable {
    case circle, recent

    var target: WalkthroughTargetID { self == .circle ? .feedCircle : .feedRecent }
    var message: String {
        self == .circle ? "Connect with\nyour circle" : "Keep up with\ntheir moments"
    }

    func visibleFrame(in targets: [WalkthroughTargetID: CGRect], size: CGSize, safeTop: CGFloat) -> CGRect? {
        guard let target = targets[self.target], target.width >= 60, target.height >= 60 else { return nil }
        let viewport = CGRect(x: 12, y: safeTop + 70, width: max(0, size.width - 24),
                              height: max(0, size.height - safeTop - 170))
        guard target.intersects(viewport) else { return nil }
        // The recent tile is centered by the real Feed scroll view. Preserve
        // its entire bounds, including attribution and engagement actions.
        return target
    }
}

/// A takeover of the current Feed: people, then the complete latest activity,
/// then back to the top. Only the real scroll view moves; no copied/example card.
struct NUXFeedIntroduction: View {
    private enum Phase: String { case arriving, circle, centering, recent, returning, finished }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.astirBrandMode) private var brand
    @State private var hasStarted = false
    @State private var phase: Phase = .arriving
    @State private var latestTargets: [WalkthroughTargetID: CGRect] = [:]
    let targets: [WalkthroughTargetID: CGRect]
    let size: CGSize
    let safeTop: CGFloat
    let scroll: (NUXFeedScrollTarget?) -> Void
    let finish: () -> Void

    private var ink: Color { brand.prefersDarkInterface ? .white : .black }
    private var focus: NUXFeedFocus? {
        switch phase { case .circle: .circle; case .recent: .recent; default: nil }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let focus, let frame = focus.visibleFrame(in: latestTargets, size: size, safeTop: safeTop) {
                NUXFeedBackdropBlur()
                    .mask {
                        NUXFeedSpotlightCutout(frame: frame.insetBy(dx: -3, dy: -3))
                            .fill(.black, style: FillStyle(eoFill: true))
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                annotation(focus, frame: frame)
                    .allowsHitTesting(false)
                Button("Next", systemImage: "arrow.right") {
                    move(to: phase == .circle ? .centering : .returning)
                }
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(brand.primaryText)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(.regularMaterial, in: Capsule())
                .buttonStyle(.plain)
                .accessibilityIdentifier("walkthrough.next.feed.feedActivity")
                .position(x: size.width - 62, y: max(82, safeTop + 28))
            }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: targets, initial: true) { _, value in latestTargets = value }
        .task(id: "\(phase.rawValue)-\(scenePhase)") {
            guard scenePhase == .active else {
                if hasStarted { scroll(nil); finish() }
                return
            }
            hasStarted = true
            let runningPhase = phase
            do {
                switch runningPhase {
                case .arriving:
                    scroll(.top)
                    try await Task.sleep(for: .milliseconds(NUXFeedIntroductionTiming.arrivalMilliseconds))
                    try await waitForTarget(.circle)
                    #if DEBUG
                    if FirstVisitWalkthroughContent.holdsAutomaticAdvanceForCapture,
                       ProcessInfo.processInfo.arguments.contains("-WanderNUXFeedRecent") {
                        move(to: .centering)
                        return
                    }
                    #endif
                    move(to: frame(for: .circle) == nil ? .centering : .circle)
                case .circle, .recent:
                    guard !FirstVisitWalkthroughContent.holdsAutomaticAdvanceForCapture,
                          !UIAccessibility.isVoiceOverRunning else { return }
                    try await Task.sleep(for: .milliseconds(NUXFeedIntroductionTiming.focusMilliseconds))
                    guard phase == runningPhase, !Task.isCancelled else { return }
                    move(to: runningPhase == .circle ? .centering : .returning)
                case .centering:
                    try await Task.sleep(for: .milliseconds(NUXFeedIntroductionTiming.clearMilliseconds))
                    scroll(.recent)
                    try await Task.sleep(for: .milliseconds(NUXFeedIntroductionTiming.scrollMilliseconds))
                    try await waitForTarget(.recent)
                    move(to: frame(for: .recent) == nil ? .returning : .recent)
                case .returning:
                    try await Task.sleep(for: .milliseconds(NUXFeedIntroductionTiming.clearMilliseconds))
                    scroll(.top)
                    try await Task.sleep(for: .milliseconds(NUXFeedIntroductionTiming.scrollMilliseconds))
                    move(to: .finished)
                case .finished:
                    scroll(nil)
                    finish()
                }
            } catch { /* Phase changes cancel only the previous beat's timer. */ }
        }
        .onDisappear { scroll(nil) }
    }

    private func frame(for focus: NUXFeedFocus) -> CGRect? {
        focus.visibleFrame(in: latestTargets, size: size, safeTop: safeTop)
    }

    private func waitForTarget(_ focus: NUXFeedFocus) async throws {
        for _ in 0..<(NUXFeedIntroductionTiming.readinessMilliseconds / 50) {
            if frame(for: focus) != nil { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func move(to value: Phase) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { phase = value }
    }

    private func annotation(_ focus: NUXFeedFocus, frame: CGRect) -> some View {
        let beside = focus == .circle && size.width - frame.maxX > 135
        let width = beside ? min(180, size.width - frame.maxX - 24) : min(320, size.width - 40)
        let x = beside ? frame.maxX + 12 + width / 2 : size.width / 2
        let y = beside ? frame.midY - 12 : max(safeTop + 100, frame.minY - 62)
        let start = beside ? CGPoint(x: x - width / 2 + 8, y: y + 38) : CGPoint(x: x, y: y + 32)
        let end = beside ? CGPoint(x: frame.maxX + 5, y: frame.midY + 28) : CGPoint(x: frame.midX, y: frame.minY - 8)
        return ZStack(alignment: .topLeading) {
            NUXHandDrawnOval()
                .stroke(ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: frame.width + 12, height: frame.height + 12)
                .position(x: frame.midX, y: frame.midY)
                .accessibilityHidden(true)
            NUXHandDrawnArrow(start: start, end: end, bend: beside ? -12 : 20)
                .stroke(ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .accessibilityHidden(true)
            Text(focus.message)
                .font(.custom("Noteworthy-Bold", size: 20, relativeTo: .title3))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width)
                .rotationEffect(.degrees(-3))
                .position(x: x, y: y)
                .accessibilityLabel(focus.message.replacingOccurrences(of: "\n", with: " "))
                .accessibilityIdentifier("walkthrough.feed.feedActivity.\(focus.rawValue)")
        }
        .shadow(color: brand.background.opacity(0.95), radius: 2)
    }
}

private struct NUXFeedSpotlightCutout: Shape {
    let frame: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: frame, cornerSize: CGSize(width: 20, height: 20))
        return path
    }
}

/// Keep effect-view alpha at one: reducing alpha washes out the page instead
/// of producing the intended moderate backdrop blur.
private struct NUXFeedBackdropBlur: UIViewRepresentable {
    final class Coordinator {
        var animator: UIViewPropertyAnimator?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: nil)
        view.isUserInteractionEnabled = false
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) {
            view.effect = UIBlurEffect(style: .systemUltraThinMaterial)
        }
        animator.pausesOnCompletion = true
        animator.fractionComplete = 0.35
        // Retain the interpolation while this short-lived spotlight is visible.
        // Finishing at .current resets UIKit's backdrop effect to no blur.
        context.coordinator.animator = animator
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}

    static func dismantleUIView(_ uiView: UIVisualEffectView, coordinator: Coordinator) {
        coordinator.animator?.stopAnimation(true)
        coordinator.animator = nil
        uiView.effect = nil
    }
}

/// Native coach chrome shared by the production tour and simulator review.
/// Decorative elements never intercept touches to the real app underneath.
struct NUXGuidanceOverlay: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var entered = false
    let step: WalkthroughStep
    let target: CGRect
    let additionalTargets: [WalkthroughTargetID: CGRect]
    let size: CGSize
    let safeTop: CGFloat
    let next: () -> Void
    var showsNext = true

    private var handwritten: Bool { step.surface == .add || step.target == .placeSaveActions }
    private var ink: Color { brand.prefersDarkInterface ? .white : .black }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if step.surface == .add {
                    NUXFeedBackdropBlur()
                        .mask {
                            NUXFeedSpotlightCutout(frame: target.insetBy(dx: -3, dy: -3))
                                .fill(.black, style: FillStyle(eoFill: true))
                        }
                        .accessibilityHidden(true)
                    addAnnotation
                } else if handwritten {
                    annotations
                } else {
                    if step.surface == .map, step.target != .mapMoreFilters {
                        RoundedRectangle(cornerRadius: min(24, target.height / 2))
                            .stroke(brand.accentText.opacity(entered ? 0.5 : 0.9), lineWidth: 2)
                            .frame(width: target.width + 8, height: target.height + 8)
                            .scaleEffect(entered ? 1 : 1.12)
                            .position(x: target.midX, y: target.midY)
                            .accessibilityHidden(true)
                    }
                    coach
                }
            }
            .allowsHitTesting(false)

            if showsNext {
                Button(action: next) {
                    HStack(spacing: 5) {
                        Text("Next")
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
                    }
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(brand.primaryText)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(brand.border.opacity(0.6), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("walkthrough.next.\(step.id)")
                .position(x: size.width - (step.surface == .add ? 104 : 55),
                          y: step.surface == .add ? max(32, safeTop + 24) : step.surface == .placeDetail ? max(126, safeTop + 70) : max(82, safeTop + 26))
            }
        }
        .frame(width: size.width, height: size.height)
        .task {
            withAnimation(reduceMotion || handwritten ? nil : .spring(duration: 0.42, bounce: 0.18)) {
                entered = true
            }
        }
    }

    private var coach: some View {
        let isUpper = target.midY < size.height * 0.46
        let normalTop = isUpper ? min(target.maxY + 24, size.height * 0.46) : max(150, target.minY - 164)
        let top = step.target == .mapMoreFilters ? min(target.maxY + 16, size.height - 224) : normalTop
        let width = min(size.width - 40, typeSize.isAccessibilitySize ? 370 : 320)
        return VStack(alignment: .leading, spacing: 9) {
            if step.surface == .map {
                Text("A QUICK LOOK AROUND · DEMO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(brand.accentText)
            }
            Text(step.title)
                .font(AstirTypography.cardTitle)
                .foregroundStyle(brand.primaryText)
            Text(step.message)
                .font(AstirTypography.bodySmall)
                .foregroundStyle(brand.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(19)
        .frame(width: width, alignment: .leading)
        .background(brand.raisedBackground.opacity(0.96), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(brand.border.opacity(0.7), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.09), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("walkthrough.\(step.id)")
        .scaleEffect(reduceMotion || entered || NUXCoachMotion.selected == .slide ? 1 : 0.94)
        .offset(x: min(max(target.midX - width / 2, 20), size.width - width - 20),
                y: top + (reduceMotion || entered ? 0 : 16))
        .opacity(entered ? 1 : 0)
    }

    private var addAnnotation: some View {
        let isImport = step.target == .addImport
        let text = isImport ? "Import your saved places\nfrom Instagram, TikTok\nand Google Maps" : "Search nearby places"
        let y = max(76, target.minY - (isImport ? 76 : 38))
        return ZStack(alignment: .topLeading) {
            NUXHandDrawnOval()
                .stroke(ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: target.width + 10, height: target.height + 10)
                .position(x: target.midX, y: target.midY)
                .accessibilityHidden(true)
            NUXHandDrawnArrow(start: CGPoint(x: size.width / 2, y: y + (isImport ? 44 : 15)),
                              end: CGPoint(x: target.midX, y: target.minY - 6), bend: 18)
                .stroke(ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .accessibilityHidden(true)
            Text(text)
                .font(.custom("Noteworthy-Bold", size: 19, relativeTo: .title3))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: size.width - 44)
                .rotationEffect(.degrees(-2))
                .position(x: size.width / 2, y: y)
                .accessibilityIdentifier("walkthrough.\(step.id)")
        }
    }

    @ViewBuilder
    private var annotations: some View {
        if step.target == .placeSaveActions {
            if let checkIn = additionalTargets[.placeCheckIn] {
                annotation("Places you’ve\nbeen", target: checkIn, side: -1)
            }
            if let wanna = additionalTargets[.placeWanna] {
                annotation("Places you\nwanna go", target: wanna, side: 1)
            }
        } else {
            annotation("Your nearby places\nwill show up here", target: target, side: 1)
        }
    }

    private func annotation(_ text: String, target: CGRect, side: CGFloat) -> some View {
        let nearby = step.target == .addNearby
        let width: CGFloat = nearby ? min(182, size.width * 0.46) : min(150, size.width * 0.40)
        let x = nearby ? size.width - width / 2 - 18 : size.width * (side < 0 ? 0.25 : 0.75)
        let y = nearby ? target.midY - 13 : max(136, target.minY - 100)
        let start = nearby ? CGPoint(x: x - width / 2 + 6, y: y - 2) : CGPoint(x: x, y: y + 32)
        let end = nearby ? CGPoint(x: target.maxX + 8, y: target.midY - 4) : CGPoint(x: target.midX, y: target.minY - 7)
        return ZStack(alignment: .topLeading) {
            NUXHandDrawnOval()
                .stroke(ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: target.width + 14, height: target.height + 12)
                .position(x: target.midX, y: target.midY)
                .accessibilityHidden(true)
            NUXHandDrawnArrow(start: start, end: end, bend: nearby ? -10 : side * 22)
                .stroke(ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .accessibilityHidden(true)
            Text(text)
                .font(.custom("Noteworthy-Bold", size: nearby ? 18 : 20, relativeTo: .title3))
                .multilineTextAlignment(.center)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width)
                .rotationEffect(.degrees(side * -3))
                .position(x: x, y: y)
                .accessibilityLabel(text.replacingOccurrences(of: "\n", with: " "))
                .accessibilityIdentifier("walkthrough.\(step.id)\(nearby || side < 0 ? "" : ".wanna")")
        }
        .shadow(color: brand.background.opacity(0.95), radius: 2)
    }

}

struct NUXHandDrawnOval: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.19, y: rect.height * 0.09))
        path.addCurve(to: CGPoint(x: rect.width * 0.88, y: rect.height * 0.12),
                      control1: CGPoint(x: rect.width * 0.4, y: -3),
                      control2: CGPoint(x: rect.width * 0.76, y: 0))
        path.addCurve(to: CGPoint(x: rect.width * 0.89, y: rect.height * 0.87),
                      control1: CGPoint(x: rect.width + 10, y: rect.height * 0.25),
                      control2: CGPoint(x: rect.width + 3, y: rect.height * 0.71))
        path.addCurve(to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.89),
                      control1: CGPoint(x: rect.width * 0.69, y: rect.height + 3),
                      control2: CGPoint(x: rect.width * 0.27, y: rect.height + 5))
        path.addCurve(to: CGPoint(x: rect.width * 0.28, y: rect.height * 0.045),
                      control1: CGPoint(x: -12, y: rect.height * 0.74),
                      control2: CGPoint(x: -3, y: rect.height * 0.03))
        return path
    }
}

struct NUXHandDrawnArrow: Shape {
    let start: CGPoint
    let end: CGPoint
    let bend: CGFloat
    func path(in rect: CGRect) -> Path {
        let control = CGPoint(x: start.x + bend, y: (start.y + end.y) / 2)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        let angle = atan2(end.y - control.y, end.x - control.x)
        for offset in [-0.55, 0.55] {
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x - 10 * cos(angle + offset), y: end.y - 10 * sin(angle + offset)))
        }
        return path
    }
}
