import SwiftUI
import UIKit

// The approved inline transition is shared by owner and member profiles.
// DEBUG previews can still select the earlier review variants.
enum ProfileMotionSource: Hashable { case avatar, name, navigation, bio }

extension View {
    @ViewBuilder
    func profileMotionSource(_ source: ProfileMotionSource?) -> some View {
        if let source {
            modifier(ProfileMotionSourceModifier(source: source))
        } else {
            self
        }
    }

    @ViewBuilder
    func profileHeaderMotionOverlay<A: View, N: View>(avatar: A, name: String, navigation: N) -> some View {
        modifier(ProfileMotionOverlayModifier(avatar: avatar, name: name, navigation: navigation))
    }
}

enum ProfileHeaderMotionVariant: String, CaseIterable {
    case solid, blur, leading, compact

    var title: String {
        switch self {
        case .solid: "01 · Compact arc"
        case .blur: "02 · Blurred arc"
        case .leading: "03 · Name beside photo"
        case .compact: "04 · Inline blur"
        }
    }

    var usesBlur: Bool { self == .blur || self == .compact }

    #if DEBUG
    static func resolved(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        guard let index = arguments.firstIndex(of: "-ProfileHeaderMotion"),
              arguments.indices.contains(index + 1) else { return nil }
        return Self(rawValue: arguments[index + 1])
    }

    #endif

    var animation: Animation { .easeInOut(duration: self == .compact ? 0.55 : 0.8) }
}

struct ProfileHeaderMotionState {
    private(set) var expanded = false
    private(set) var previousOffset: CGFloat = 0

    mutating func update(offset: CGFloat, originalAvatar: CGRect, entryBoundary: CGFloat? = nil, restoreBoundary: CGFloat? = nil) -> Bool {
        let wasExpanded = expanded
        // Boundaries are measured below the pinned controls. The compact
        // option overrides entry with the name edge and restoration with the bio.
        if offset > previousOffset, offset >= (entryBoundary ?? originalAvatar.midY) {
            expanded = true
        } else if offset < previousOffset, offset <= (restoreBoundary ?? originalAvatar.maxY) {
            expanded = false
        }
        previousOffset = offset
        return expanded != wasExpanded
    }
}

enum ProfileHeaderPhotoLayout {
    /// Hold the photo in the header until its inline position catches up on
    /// return. The bio/name transition can run while that position is offscreen.
    static func center(inlineFrame: CGRect, pinnedY: CGFloat) -> CGPoint {
        CGPoint(x: inlineFrame.midX, y: max(inlineFrame.midY, pinnedY))
    }
}

private struct ProfileHeaderMotionKey: EnvironmentKey {
    static let defaultValue: ProfileHeaderMotionVariant? = .compact
}
extension EnvironmentValues {
    // Preserve the original reading layout at accessibility text sizes.
    var resolvedProfileHeaderMotion: ProfileHeaderMotionVariant? {
        dynamicTypeSize.isAccessibilitySize ? nil : profileHeaderMotion
    }

    var profileHeaderMotion: ProfileHeaderMotionVariant? {
        get { self[ProfileHeaderMotionKey.self] }
        set { self[ProfileHeaderMotionKey.self] = newValue }
    }
}

private struct ProfileMotionAnchors: PreferenceKey {
    static var defaultValue: [ProfileMotionSource: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [ProfileMotionSource: Anchor<CGRect>], nextValue: () -> [ProfileMotionSource: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct ProfileMotionSourceModifier: ViewModifier {
    @Environment(\.resolvedProfileHeaderMotion) private var variant
    let source: ProfileMotionSource

    func body(content: Content) -> some View {
        if variant != nil {
            content
                .opacity(source == .bio ? 1 : 0)
                .accessibilityHidden(source != .bio)
                .allowsHitTesting(source == .bio)
                .anchorPreference(key: ProfileMotionAnchors.self, value: .bounds) { [source: $0] }
        } else {
            content
        }
    }
}

private struct ProfileMotionOverlayModifier<A: View, N: View>: ViewModifier {
    @Environment(\.resolvedProfileHeaderMotion) private var variant
    let avatar: A
    let name: String
    let navigation: N

    func body(content: Content) -> some View {
        if let variant {
            content.scrollClipDisabled(variant == .compact)
                .overlayPreferenceValue(ProfileMotionAnchors.self) { anchors in
                    GeometryReader { proxy in
                        if let a = anchors[.avatar], let n = anchors[.name], let bar = anchors[.navigation] {
                            ProfileMotionOverlay(
                                variant: variant, avatar: avatar, name: name, navigation: navigation,
                                avatarRect: proxy[a], nameRect: proxy[n], navigationRect: proxy[bar],
                                bioRect: anchors[.bio].map { proxy[$0] }, width: proxy.size.width,
                                height: proxy.size.height, topInset: max(0, proxy.frame(in: .global).minY)
                            )
                        }
                    }
                }
        } else {
            content
        }
    }
}

private struct ProfileMotionOverlay<A: View, N: View>: View {
    @Environment(\.astirBrandMode) private var brandMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let variant: ProfileHeaderMotionVariant
    let avatar: A
    let name: String
    let navigation: N
    let avatarRect: CGRect
    let nameRect: CGRect
    let navigationRect: CGRect
    let bioRect: CGRect?
    let width: CGFloat
    let height: CGFloat
    let topInset: CGFloat
    @State private var initialAvatar: CGRect?
    @State private var initialNavigation: CGRect?
    @State private var entryAvatar: CGRect?
    @State private var entryName: CGRect?
    @State private var motion = ProfileHeaderMotionState()
    @State private var photoProgress: CGFloat = 0
    @State private var nameProgress: CGFloat = 0
    @State private var surfaceProgress: CGFloat = 0

    private var toolbarBottom: CGFloat { (initialNavigation ?? navigationRect).maxY + 8 }
    private var surfaceBottom: CGFloat { variant == .compact ? 166 : 208 }
    private var contrastingBackground: Color {
        brandMode == .editorialLight ? .black : AstirBrandMode.editorialLight.background
    }
    private var contrastingText: Color {
        brandMode == .editorialLight ? AstirTheme.paper.color : AstirTheme.ink.color
    }
    private var destination: CGPoint {
        switch variant {
        case .solid, .blur: CGPoint(x: width / 2, y: 122)
        case .leading: CGPoint(x: width - 24 - 51.6, y: 122)
        case .compact: CGPoint(x: avatarRect.midX, y: 111)
        }
    }

    private func displayName(color: Color) -> some View {
        Text(name)
            .font(AstirTypography.sheetTitle)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: nameRect.width, height: nameRect.height)
            .allowsHitTesting(false)
    }

    private var expandedName: some View {
        Text(name)
            // 1.4× in the previous render, now 55% of that size: 0.77×.
            .font(AstirTypography.sheetTitle)
            .foregroundStyle(contrastingText)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .scaleEffect(0.77, anchor: variant == .leading ? .leading : .center)
            .frame(width: variant == .leading ? width - 168 : width - 32,
                   height: 28, alignment: variant == .leading ? .leading : .center)
            .position(x: variant == .leading ? 24 + (width - 168) / 2 : width / 2,
                      y: (variant == .leading ? 122 : 191) + 12 * (1 - nameProgress))
            .opacity(nameProgress)
            .allowsHitTesting(false)
    }

    /// A clear starting state reveals the native backdrop from the screen's top
    /// in sync with the name. Keep backdrop colors visible through the lighter
    /// material and feather the moving lower edge into the scrolling content.
    private var continuousHeaderBlur: some View {
        Group {
            if reduceTransparency {
                brandMode.background
            } else {
                ProfileMotionBackdropBlur(isDark: brandMode.prefersDarkInterface)
            }
        }
        .frame(width: width, height: topInset + surfaceBottom)
        .mask(alignment: .top) {
            VStack(spacing: 0) {
                Color.white
                LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 32)
            }
            .frame(height: (topInset + surfaceBottom) * surfaceProgress)
            .clipped()
        }
        .offset(y: -topInset)
        .contentShape(Rectangle())
        .onTapGesture { /* Keep obscured scroll content from receiving taps. */ }
        .allowsHitTesting(motion.expanded)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var photo: some View {
        if variant == .compact {
            avatar.position(ProfileHeaderPhotoLayout.center(inlineFrame: avatarRect, pinnedY: destination.y))
        } else {
            avatar
                .modifier(ProfileMotionTransform(
                    progress: photoProgress, source: motion.expanded ? (entryAvatar ?? avatarRect) : avatarRect,
                    destination: destination, scale: 1.2, arc: -16
                ))
        }
    }

    private var identity: some View {
        ZStack(alignment: .topLeading) {
            if variant == .compact {
                displayName(color: brandMode.primaryText)
                    .position(x: nameRect.midX, y: nameRect.midY)
                    .opacity(1 - nameProgress)
                    .accessibilityHidden(true)
                displayName(color: brandMode.primaryText)
                    .modifier(ProfileMotionTransform(
                        progress: nameProgress, source: motion.expanded ? (entryName ?? nameRect) : nameRect,
                        destination: CGPoint(x: nameRect.midX, y: 111),
                        scale: 1, arc: 0
                    ))
                    .opacity(nameProgress)
                    .accessibilityHidden(false)
                    .accessibilityIdentifier("profile.header.name")
            } else {
                displayName(color: brandMode.primaryText)
                    .position(x: nameRect.midX, y: nameRect.midY)
                    .opacity(1 - surfaceProgress)
                expandedName
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if variant == .compact {
                continuousHeaderBlur
                identity.mask(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: toolbarBottom)
                        Color.white
                    }
                }
            } else {
                Group {
                    if variant.usesBlur {
                        Rectangle().fill(.ultraThinMaterial)
                            .environment(\.colorScheme, brandMode == .editorialLight ? .dark : .light)
                    } else {
                        contrastingBackground
                    }
                }
                .frame(height: surfaceBottom - toolbarBottom)
                .offset(y: toolbarBottom)
                .opacity(surfaceProgress)
                .allowsHitTesting(false)
                photo
                identity
                brandMode.background.frame(height: toolbarBottom).allowsHitTesting(false)
                brandMode.background.frame(height: topInset).offset(y: -topInset).allowsHitTesting(false)
            }
            navigation
                .frame(width: navigationRect.width, height: navigationRect.height)
                .position(x: width / 2, y: (initialNavigation ?? navigationRect).midY)
            if variant == .compact {
                // The photo must stay above both the toolbar and its text mask.
                // Keep one live control throughout scrolling and restoration.
                photo
            }
        }
        .onAppear {
            if initialAvatar == nil {
                // A tab or overlay can first appear with a restored scroll
                // position. Recover the content origin from its toolbar spacer.
                let offset = WanderTheme.spacing3 - navigationRect.minY
                initialAvatar = avatarRect.offsetBy(dx: 0, dy: offset)
                initialNavigation = navigationRect.offsetBy(dx: 0, dy: offset)
            }
            updateMotion()
        }
        .onChange(of: avatarRect.minY) { _, _ in updateMotion() }
    }

    private func updateMotion() {
        guard let initialAvatar else { return }
        let offset = initialAvatar.minY - avatarRect.minY
        let viewportTop = initialNavigation?.maxY ?? 0
        let viewportAvatar = initialAvatar.offsetBy(dx: 0, dy: -viewportTop)
        // Normalize current geometry instead of caching the bio/name. Editing
        // the profile or relayout must immediately use the new boundaries.
        let restoreBoundary = variant == .compact ? bioRect.map { $0.maxY + offset - viewportTop } : nil
        let entryBoundary = variant == .compact ? max(0, nameRect.minY + offset - viewportTop) : nil
        guard motion.update(offset: offset, originalAvatar: viewportAvatar,
                            entryBoundary: entryBoundary, restoreBoundary: restoreBoundary) else { return }
        if motion.expanded {
            entryAvatar = avatarRect
            entryName = nameRect
        }
        let target: CGFloat = motion.expanded ? 1 : 0
        withAnimation(reduceMotion ? nil : variant.animation) { photoProgress = target }
        withAnimation(reduceMotion ? nil : (variant == .compact ? .easeInOut(duration: 0.55) : .easeOut(duration: 0.24).delay(motion.expanded ? 0 : 0.3))) {
            surfaceProgress = target
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.56).delay(variant == .compact ? 0 : 0.2)) {
            nameProgress = target
        }
    }

}

/// Keep the blur layer opaque as a compositor while reducing the material's
/// intensity. Lowering the view alpha would reveal a second, sharp copy of
/// scrolling text under the name and clock.
struct ProfileMotionBackdropBlur: UIViewRepresentable {
    let isDark: Bool

    func makeUIView(context: Context) -> BackdropView {
        let view = BackdropView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: BackdropView, context: Context) {
        view.setAppearance(isDark ? .dark : .light)
    }

    static func dismantleUIView(_ view: BackdropView, coordinator: ()) {
        view.stop()
    }

    final class BackdropView: UIVisualEffectView {
        private var animator: UIViewPropertyAnimator?

        init() { super.init(effect: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { configure() } else { stop() }
        }

        func setAppearance(_ appearance: UIUserInterfaceStyle) {
            guard overrideUserInterfaceStyle != appearance else { return }
            overrideUserInterfaceStyle = appearance
            if window != nil { configure() }
        }

        func stop() {
            animator?.stopAnimation(true)
            animator = nil
        }

        #if DEBUG && targetEnvironment(simulator)
        private var diagnosticFinishOnConfigure = false
        private(set) var diagnosticBeforeFinish: [String: Any]?
        private(set) var diagnosticAfterFinish: [String: Any]?
        private var diagnosticInstanceOrdinal: Int?
        private var diagnosticConfigurationOrdinal = 0
        private(set) var diagnosticPostFraction: [String: Any]?

        func assignComponentIdentity(_ ordinal: Int) {
            precondition(ProfileBlurLifecycleDiagnostic.componentStyle != nil && window == nil)
            precondition(diagnosticInstanceOrdinal == nil && (1...2).contains(ordinal))
            diagnosticInstanceOrdinal = ordinal
        }

        func enableImmediateFinishForDiagnostic() {
            precondition(ProfileBlurLifecycleDiagnostic.componentStyle != nil && window == nil)
            diagnosticFinishOnConfigure = true
        }

        var diagnosticState: [String: Any] {
            var state: [String: Any] = [
                "retained": animator != nil, "windowAttached": window != nil,
                "observedAt": ProcessInfo.processInfo.systemUptime,
                "instanceOrdinal": diagnosticInstanceOrdinal ?? -1,
                "configurationOrdinal": diagnosticConfigurationOrdinal,
                "bounds": [Double(bounds.minX), Double(bounds.minY), Double(bounds.width), Double(bounds.height)]
            ]
            if let animator {
                state["state"] = animator.state.rawValue
                state["running"] = animator.isRunning
                state["fraction"] = Double(animator.fractionComplete)
            }
            return state
        }

        @discardableResult
        func finishAtCurrentForDiagnostic() -> Bool {
            guard ProfileBlurLifecycleDiagnostic.admitted,
                  let animator, animator.state == .active else { return false }
            diagnosticBeforeFinish = diagnosticState
            animator.stopAnimation(false)
            animator.finishAnimation(at: .current)
            diagnosticAfterFinish = diagnosticState
            self.animator = nil
            return true
        }
        #endif

        private func configure() {
            stop()
            effect = nil
            let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
                self?.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            }
            self.animator = animator
            animator.fractionComplete = 0.25
            #if DEBUG && targetEnvironment(simulator)
            // Component-only observation at the same lifecycle point for both
            // real instances, before either candidate finishing operation.
            if diagnosticInstanceOrdinal != nil {
                diagnosticConfigurationOrdinal += 1
                if diagnosticPostFraction == nil { diagnosticPostFraction = diagnosticState }
            }
            if ProfileBlurLifecycleDiagnostic.finishAppearanceFixture || diagnosticFinishOnConfigure {
                finishAtCurrentForDiagnostic()
            }
            #endif
        }
    }
}

private struct ProfileMotionTransform: AnimatableModifier {
    nonisolated var progress: CGFloat
    let source: CGRect
    let destination: CGPoint
    let scale: CGFloat
    let arc: CGFloat
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content
            .scaleEffect(1 + (scale - 1) * progress)
            .position(
                x: source.midX + (destination.x - source.midX) * progress,
                y: source.midY + (destination.y - source.midY) * progress - sin(progress * .pi) * arc
            )
    }
}


#if DEBUG && targetEnvironment(simulator)
/// Unpublished REC-636 trial. No ordinary, release, or physical-device admission.
@MainActor
enum ProfileBlurLifecycleDiagnostic {
    static let componentArgument = "-WanderProfileBlurLifecycleComponent"
    static var admitted: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let required = ["-WanderMapCapture", "-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                        "-WanderDisableWalkthroughs"]
        guard Bundle.main.bundleIdentifier == "com.grayline.wander",
              required.allSatisfy({ flag in arguments.filter { $0 == flag }.count == 1 }),
              !arguments.contains("-WanderUseLiveAuth"),
              arguments.filter({ $0 == "-WanderInitialTab" }).count == 1,
              let index = arguments.firstIndex(of: "-WanderInitialTab"),
              arguments.indices.contains(index + 1), arguments[index + 1] == "map" else { return false }
        return true
    }
    static var componentStyle: UIUserInterfaceStyle? {
        let arguments = ProcessInfo.processInfo.arguments
        guard admitted, arguments.filter({ $0 == componentArgument }).count == 1,
              let index = arguments.firstIndex(of: componentArgument), arguments.indices.contains(index + 1)
        else { return nil }
        switch arguments[index + 1] {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
    static var finishAppearanceFixture: Bool {
        admitted && !ProcessInfo.processInfo.arguments.contains(componentArgument)
    }
}

/// Real compositor surface, not a drawHierarchy snapshot of a visual-effect view.
struct ProfileBlurLifecycleDiagnosticHost: UIViewRepresentable {
    let style: UIUserInterfaceStyle
    func makeUIView(context: Context) -> Host { Host(style: style) }
    func updateUIView(_ view: Host, context: Context) {}

    final class Pattern: UIView {
        override func draw(_ rect: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else { return }
            for y in stride(from: 0, to: Int(bounds.height), by: 4) {
                for x in stride(from: 0, to: Int(bounds.width), by: 4) {
                    let coarse: CGFloat = (x / 48) % 2 == 0 ? 0.15 : 0.65
                    let checker: CGFloat = ((x / 4 + y / 4) % 2 == 0) ? 0.0 : 0.2
                    context.setFillColor(UIColor(white: coarse + checker, alpha: 1).cgColor)
                    context.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 4, height: 4))
                }
            }
        }
    }

    final class Host: UIView {
        private let reference = ProfileMotionBackdropBlur.BackdropView()
        private let immediate = ProfileMotionBackdropBlur.BackdropView()
        private let full = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        private let panels = (0..<4).map { _ in Pattern() }
        private let state = UILabel()
        private let finish = UIButton(type: .system)
        private var finished = false
        private var attachedEffects = false
        private var pairedLater: [String: Any]?

        init(style: UIUserInterfaceStyle) {
            precondition(ProfileBlurLifecycleDiagnostic.componentStyle == style)
            super.init(frame: .zero)
            overrideUserInterfaceStyle = style
            backgroundColor = .systemBackground
            reference.assignComponentIdentity(1)
            immediate.assignComponentIdentity(2)
            immediate.enableImmediateFinishForDiagnostic()
            reference.setAppearance(style)
            immediate.setAppearance(style)
            for panel in panels { panel.isOpaque = true; addSubview(panel) }
            for effect in [reference, immediate, full] { effect.isUserInteractionEnabled = false }
            finish.setTitle("Finish retained blur", for: .normal)
            finish.accessibilityIdentifier = "profile.blur.lifecycle.finish"
            finish.addTarget(self, action: #selector(finishReference), for: .touchUpInside)
            addSubview(finish)
            state.text = "Synthetic blur lifecycle"
            state.isHidden = true // The original existence wait admits only a paired, laid-out observation.
            state.isAccessibilityElement = true
            state.accessibilityIdentifier = "profile.blur.lifecycle.state"
            addSubview(state)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            // Fixed synthetic viewport rectangles; tests crop the same screen-pixel regions.
            for (index, panel) in panels.enumerated() {
                panel.frame = CGRect(x: 24, y: CGFloat(100 + index * 108), width: bounds.width - 48, height: 88)
            }
            reference.frame = panels[1].bounds
            immediate.frame = panels[2].bounds
            full.frame = panels[3].bounds
            // UIKit invokes didMoveToWindow during attachment. Establish real
            // geometry first so configure never depends on a zero-frame order.
            if !attachedEffects, window != nil,
               bounds.width.isFinite, bounds.height.isFinite,
               bounds.width > 300, bounds.height >= 700 {
                attachedEffects = true // Set before attachment can cause layout.
                panels[1].addSubview(reference)
                panels[2].addSubview(immediate)
                panels[3].addSubview(full)
                // One paired later observation; no timer, polling or repair.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let started = ProcessInfo.processInfo.systemUptime
                    let referenceState = self.reference.diagnosticState
                    let candidateState = self.immediate.diagnosticState
                    self.pairedLater = ["startedAt": started,
                        "finishedAt": ProcessInfo.processInfo.systemUptime,
                        "reference": referenceState, "candidate": candidateState]
                    self.updateObservation()
                }
            }
            finish.frame = CGRect(x: 24, y: 548, width: bounds.width - 48, height: 48)
            state.frame = CGRect(x: 24, y: 604, width: bounds.width - 48, height: 44)
            updateObservation()
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { setNeedsLayout() }
        }
        @objc private func finishReference() {
            guard !finished else { return }
            finished = reference.finishAtCurrentForDiagnostic()
            updateObservation()
        }
        private func updateObservation() {
            let ready = window != nil && bounds.width > 300 && bounds.height >= 700
                && window?.bounds.size == bounds.size && convert(bounds, to: window).origin == .zero
                && attachedEffects && pairedLater != nil
            let value: [String: Any] = [
                "schema": 1, "fixture": "profile-blur", "ready": ready, "finished": finished,
                "viewportWidth": Double(bounds.width), "viewportHeight": Double(bounds.height),
                "reference": reference.diagnosticState,
                "referencePostFraction": reference.diagnosticPostFraction ?? [:],
                "candidatePostFraction": immediate.diagnosticPostFraction ?? [:],
                "pairedLater": pairedLater ?? [:],
                "referenceBefore": reference.diagnosticBeforeFinish ?? [:],
                "referenceAfter": reference.diagnosticAfterFinish ?? [:],
                "immediateBefore": immediate.diagnosticBeforeFinish ?? [:],
                "immediateAfter": immediate.diagnosticAfterFinish ?? [:],
                "immediate": immediate.diagnosticState
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                  data.count <= 4096, let text = String(data: data, encoding: .utf8) else {
                state.accessibilityValue = "invalid"; finish.isEnabled = false; return
            }
            state.accessibilityValue = text
            state.isHidden = !ready
            finish.isEnabled = ready && !finished
        }
    }
}
#endif
