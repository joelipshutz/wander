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
                #if DEBUG && targetEnvironment(simulator)
                ProfileMotionBackdropBlur(isDark: brandMode.prefersDarkInterface,
                    observationMask: ProfileBlurObservation.admitted
                        ? [Double(surfaceProgress), Double(topInset), Double(surfaceBottom)] : nil)
                #else
                ProfileMotionBackdropBlur(isDark: brandMode.prefersDarkInterface)
                #endif
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
    #if DEBUG && targetEnvironment(simulator)
    var observationMask: [Double]? = nil
    #endif

    func makeUIView(context: Context) -> BackdropView {
        let view = BackdropView()
        #if DEBUG && targetEnvironment(simulator)
        if ProfileBlurObservation.admitted { view.observationMask = observationMask }
        #endif
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: BackdropView, context: Context) {
        #if DEBUG && targetEnvironment(simulator)
        if ProfileBlurObservation.admitted { view.observationMask = observationMask }
        #endif
        view.setAppearance(isDark ? .dark : .light)
    }

    static func dismantleUIView(_ view: BackdropView, coordinator: ()) {
        #if DEBUG && targetEnvironment(simulator)
        ProfileBlurObservation.record(view, .dismantle)
        #endif
        view.stop()
    }

    final class BackdropView: UIVisualEffectView {
        private var animator: UIViewPropertyAnimator?

        init() { super.init(effect: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            #if DEBUG && targetEnvironment(simulator)
            ProfileBlurObservation.record(self, .window)
            #endif
            if window != nil { configure() } else { stop() }
        }

        func setAppearance(_ appearance: UIUserInterfaceStyle) {
            #if DEBUG && targetEnvironment(simulator)
            ProfileBlurObservation.record(self, .appearanceRequested, requestedStyle: appearance.rawValue)
            #endif
            guard overrideUserInterfaceStyle != appearance else { return }
            overrideUserInterfaceStyle = appearance
            #if DEBUG && targetEnvironment(simulator)
            ProfileBlurObservation.record(self, .appearanceChanged)
            #endif
            if window != nil { configure() }
        }

        func stop() {
            #if DEBUG && targetEnvironment(simulator)
            ProfileBlurObservation.record(self, .stopBefore)
            #endif
            animator?.stopAnimation(true)
            animator = nil
            #if DEBUG && targetEnvironment(simulator)
            ProfileBlurObservation.record(self, .stopAfter)
            #endif
        }

        #if DEBUG && targetEnvironment(simulator)
        var observationMask: [Double]?
        var observationAnimator: [String: Any] {
            guard let animator else { return ["retained": false] }
            return ["retained": true, "state": animator.state.rawValue,
                    "running": animator.isRunning, "fraction": ProfileBlurObservation.number(Double(animator.fractionComplete))]
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            ProfileBlurObservation.record(self, .layout)
        }
        #endif

        private func configure() {
            #if DEBUG && targetEnvironment(simulator)
            ProfileBlurObservation.record(self, .configureBefore)
            #endif
            stop()
            effect = nil
            let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
                self?.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            }
            self.animator = animator
            animator.fractionComplete = 0.25
            #if DEBUG && targetEnvironment(simulator)
            ProfileBlurObservation.record(self, .configureAfter)
            ProfileBlurObservation.deferOnce(self)
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
/// Passive, synthetic-only observation. Never changes animator or layer behavior.
@MainActor
private enum ProfileBlurObservation {
    enum Event: String {
        case window, appearanceRequested, appearanceChanged, configureBefore, configureAfter
        case stopBefore, stopAfter, layout, dismantle, deferred
    }
    static let argument = "-WanderActualProfileBlurObservation"
    static let nonce: String? = {
        let args = ProcessInfo.processInfo.arguments
        let required = ["-WanderMapCapture", "-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                        "-WanderDisableWalkthroughs", "-WanderInitialTab", argument]
        guard Bundle.main.bundleIdentifier == "com.grayline.wander",
              Set(args.filter { $0.hasPrefix("-Wander") }) == Set(required),
              required.allSatisfy({ flag in args.filter { $0 == flag }.count == 1 }),
              let tab = args.firstIndex(of: "-WanderInitialTab"), args.indices.contains(tab + 1), args[tab + 1] == "map",
              let index = args.firstIndex(of: argument), args.indices.contains(index + 1),
              UUID(uuidString: args[index + 1]) != nil else { return nil }
        return args[index + 1]
    }()
    static var admitted: Bool {
        guard nonce != nil else { return false }
        _ = firstAdmittedAt
        return true
    }
    final class Instance {
        weak var view: ProfileMotionBackdropBlur.BackdropView?
        let ordinal: Int
        var configurations = 0, layouts = 0, stops = 0, deferredRequests = 0, appearanceRequests = 0
        var lastLayout: NSDictionary?
        var lastRequestedStyle: Int?
        var lastState: [String: Any] = [:]
        var lastStateAt: TimeInterval = 0
        var lastLayers: [[String: Any]] = []
        var lastLayersAt: TimeInterval = 0
        init(_ view: ProfileMotionBackdropBlur.BackdropView, ordinal: Int) { self.view = view; self.ordinal = ordinal }
    }
    static var instances: [Instance] = []
    static var events: [[String: Any]] = []
    static var totalEvents = 0, droppedEvents = 0, droppedInstances = 0, droppedDeferred = 0
    static var layerObservations = 0
    static let firstAdmittedAt = ProcessInfo.processInfo.systemUptime
    static func number(_ value: Double) -> Any { value.isFinite ? value as Any : NSNull() }
    static func state(_ view: ProfileMotionBackdropBlur.BackdropView) -> [String: Any] {
        ["window": view.window != nil, "bounds": [number(Double(view.bounds.width)), number(Double(view.bounds.height))],
         "windowSize": view.window.map { [number(Double($0.bounds.width)), number(Double($0.bounds.height))] } ?? [],
         "hidden": view.isHidden, "alpha": number(Double(view.alpha)), "style": view.overrideUserInterfaceStyle.rawValue,
         "animationsEnabled": UIView.areAnimationsEnabled, "animator": view.observationAnimator,
         "sourceMask": view.observationMask?.map(number) ?? []]
    }
    static func instance(_ view: ProfileMotionBackdropBlur.BackdropView) -> Instance? {
        if let found = instances.first(where: { $0.view === view }) { return found }
        guard instances.count < 4 else { droppedInstances += 1; return nil }
        let found = Instance(view, ordinal: instances.count + 1); instances.append(found); return found
    }
    static func record(_ view: ProfileMotionBackdropBlur.BackdropView, _ event: Event,
                       requestedStyle: Int? = nil, requestedConfiguration: Int? = nil) {
        guard admitted, let item = instance(view) else { return }
        if event == .configureBefore { item.configurations += 1 }
        if event == .stopBefore { item.stops += 1 }
        let value = state(view)
        item.lastState = value; item.lastStateAt = ProcessInfo.processInfo.systemUptime
        if event == .appearanceRequested {
            item.appearanceRequests += 1
            if requestedStyle == item.lastRequestedStyle { return }
            item.lastRequestedStyle = requestedStyle
        }
        if event == .layout {
            item.layouts += 1
            let next = NSDictionary(dictionary: value)
            if item.lastLayout?.isEqual(next) == true { return }
            item.lastLayout = next
        }
        totalEvents += 1
        guard events.count < 64 else { droppedEvents += 1; return }
        var row: [String: Any] = ["event": event.rawValue, "uptime": ProcessInfo.processInfo.systemUptime,
            "instance": item.ordinal, "configuration": item.configurations, "state": value]
        if let requestedStyle { row["requestedStyle"] = requestedStyle }
        if let requestedConfiguration {
            row["requestedConfiguration"] = requestedConfiguration
            row["staleConfiguration"] = requestedConfiguration != item.configurations
        }
        // At most six layer walks on these source lifecycle events. AX reads never walk layers.
        if event == .deferred || event == .configureAfter {
            if layerObservations < 6 {
                let observedLayers = layers(view.layer)
                row["layers"] = observedLayers; item.lastLayers = observedLayers
                item.lastLayersAt = ProcessInfo.processInfo.systemUptime; layerObservations += 1
            }
            else { row["layerObservationOmitted"] = true }
        }
        events.append(row)
    }
    static func deferOnce(_ view: ProfileMotionBackdropBlur.BackdropView) {
        guard admitted, let item = instance(view) else { return }
        guard item.deferredRequests < 16 else { droppedDeferred += 1; return }
        item.deferredRequests += 1
        let configuration = item.configurations
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            record(view, .deferred, requestedConfiguration: configuration)
        }
    }
    static func layers(_ first: CALayer) -> [[String: Any]] {
        var result: [[String: Any]] = [], next: CALayer? = first
        while let layer = next, result.count < 5 {
            let keys = layer.animationKeys() ?? []
            let animations: [[String: Any]] = keys.prefix(2).enumerated().map { ordinal, key in
                guard let animation = layer.animation(forKey: key) else { return ["ordinal": ordinal, "available": false] }
                let kind = animation is CAAnimationGroup ? "group" : animation is CASpringAnimation ? "spring" :
                    animation is CAKeyframeAnimation ? "keyframe" : animation is CABasicAnimation ? "basic" : "other"
                return ["ordinal": ordinal, "available": true, "kind": kind,
                    "duration": number(animation.duration), "speed": number(Double(animation.speed)),
                    "timeOffset": number(animation.timeOffset), "repeatCount": number(Double(animation.repeatCount)),
                    "repeatDuration": number(animation.repeatDuration), "autoreverses": animation.autoreverses,
                    "removedOnCompletion": animation.isRemovedOnCompletion]
            }
            result.append(["depth": result.count, "hidden": layer.isHidden, "opacity": number(Double(layer.opacity)),
                "bounds": [number(Double(layer.bounds.width)), number(Double(layer.bounds.height))],
                "maskPresent": layer.mask != nil,
                "maskBounds": layer.mask.map { [number(Double($0.bounds.width)), number(Double($0.bounds.height))] } ?? [],
                "animationCount": keys.count, "animationLimitReached": keys.count > 2, "animations": animations])
            next = layer.superlayer
        }
        if next != nil { result.append(["ancestorLimitReached": true]) }
        return result
    }
    static func readout(attached: Bool) -> String {
        guard admitted else { return "unadmitted" }
        let final: [[String: Any]] = instances.map { item in
            ["instance": item.ordinal, "configuration": item.configurations,
             "layouts": item.layouts, "stops": item.stops, "deferredRequests": item.deferredRequests,
             "appearanceRequests": item.appearanceRequests, "released": item.view == nil,
             "lastObservedState": item.lastState, "lastObservedAt": item.lastStateAt,
             "lastObservedLayers": item.lastLayers, "lastLayersObservedAt": item.lastLayersAt]
        }
        var payload: [String: Any] = ["schema": 1, "fixture": "actual-profile-blur", "nonce": nonce ?? "",
            "readoutAttached": attached, "firstAdmittedAt": firstAdmittedAt, "readAt": ProcessInfo.processInfo.systemUptime,
            "totalEvents": totalEvents, "droppedEvents": droppedEvents, "droppedInstances": droppedInstances,
            "droppedDeferred": droppedDeferred, "events": events, "final": final,
            "lastObservedStateIsNotReadTimeState": true]
        // Automatic AX traversal may request this value; serialization does not inspect live animator/layers.
        if let encoded = try? JSONSerialization.data(withJSONObject: payload), encoded.count > 32_768 {
            payload["events"] = events.map { row in var copy = row; copy.removeValue(forKey: "layers"); return copy }
            payload["final"] = final.map { row in var copy = row; copy.removeValue(forKey: "lastObservedLayers"); return copy }
            payload["layerPayloadOmittedForSize"] = true
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              data.count <= 32_768, let text = String(data: data, encoding: .utf8) else {
            return "{\"schema\":1,\"fixture\":\"actual-profile-blur\",\"status\":\"Gap\",\"reason\":\"encoding_or_size_limit\"}"
        }
        return text
    }
}

/// Transparent, non-interactive AX carrier in the fixture root, not in the masked Profile subtree.
struct ProfileBlurObservationReadout: UIViewRepresentable {
    static var admitted: Bool { ProfileBlurObservation.admitted }
    func makeUIView(context: Context) -> Readout {
        let view = Readout()
        view.isUserInteractionEnabled = false
        view.text = "Synthetic Profile lifecycle"
        view.font = .systemFont(ofSize: 1)
        view.textColor = .clear
        view.isAccessibilityElement = true
        view.accessibilityTraits = .staticText
        view.accessibilityLabel = "Synthetic Profile lifecycle"
        view.accessibilityIdentifier = "profile.blur.actual.observation"
        return view
    }
    func updateUIView(_ view: Readout, context: Context) {}
    final class Readout: UILabel {
        override var accessibilityValue: String? {
            get { ProfileBlurObservation.readout(attached: window != nil) }
            set {}
        }
    }
}
#endif
