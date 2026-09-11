import SwiftUI

// The release build keeps the original profile layout. These hooks only enable
// the review prototype when its explicit DEBUG preview environment is present.
enum ProfileMotionSource: Hashable { case avatar, name, navigation, bio }

extension View {
    @ViewBuilder
    func profileMotionSource(_ source: ProfileMotionSource) -> some View {
        #if DEBUG
        modifier(ProfileMotionSourceModifier(source: source))
        #else
        self
        #endif
    }

    @ViewBuilder
    func profileHeaderMotionOverlay<A: View, N: View>(avatar: A, name: String, navigation: N) -> some View {
        #if DEBUG
        modifier(ProfileMotionOverlayModifier(avatar: avatar, name: name, navigation: navigation))
        #else
        self
        #endif
    }
}

#if DEBUG
import UIKit

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

    static func resolved(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        guard let index = arguments.firstIndex(of: "-ProfileHeaderMotion"),
              arguments.indices.contains(index + 1) else { return nil }
        return Self(rawValue: arguments[index + 1])
    }

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

private struct ProfileHeaderMotionKey: EnvironmentKey {
    static let defaultValue: ProfileHeaderMotionVariant? = nil
}
extension EnvironmentValues {
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
    @Environment(\.profileHeaderMotion) private var variant
    let source: ProfileMotionSource

    func body(content: Content) -> some View {
        if variant != nil {
            content
                .opacity(source == .bio ? 1 : 0)
                .accessibilityHidden(source != .bio)
                .anchorPreference(key: ProfileMotionAnchors.self, value: .bounds) { [source: $0] }
        } else {
            content
        }
    }
}

private struct ProfileMotionOverlayModifier<A: View, N: View>: ViewModifier {
    @Environment(\.profileHeaderMotion) private var variant
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
    @State private var initialName: CGRect?
    @State private var initialNavigation: CGRect?
    @State private var initialBio: CGRect?
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
        case .compact: CGPoint(x: (initialAvatar ?? avatarRect).midX, y: 111)
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

    /// Shares the neutral ultra-thin material, desaturation, and soft edge used
    /// by the other tabs' localized header blur. Only this review option expands
    /// it into one continuous field. The upper field is always present.
    private var continuousHeaderBlur: some View {
        Group {
            if reduceTransparency {
                brandMode.background
            } else {
                ProfileMotionBackdropBlur(isDark: brandMode.prefersDarkInterface)
                    .saturation(0)
            }
        }
        .frame(width: width,
               height: topInset + toolbarBottom + (surfaceBottom - toolbarBottom) * surfaceProgress)
        .mask(alignment: .bottom) {
            VStack(spacing: 0) {
                Color.white
                LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
            }
        }
        .offset(y: -topInset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var identity: some View {
        ZStack(alignment: .topLeading) {
            avatar
                .modifier(ProfileMotionTransform(
                    progress: photoProgress, source: motion.expanded ? (entryAvatar ?? avatarRect) : avatarRect,
                    destination: destination, scale: variant == .compact ? 1 : 1.2,
                    arc: variant == .compact ? 0 : -16
                ))
                .allowsHitTesting(false)
                .accessibilityLabel("\(name)'s profile photo")

            if variant == .compact {
                displayName(color: brandMode.primaryText)
                    .position(x: nameRect.midX, y: nameRect.midY)
                    .opacity(1 - nameProgress)
                displayName(color: brandMode.primaryText)
                    .modifier(ProfileMotionTransform(
                        progress: nameProgress, source: motion.expanded ? (entryName ?? nameRect) : nameRect,
                        destination: CGPoint(x: (initialName ?? nameRect).midX, y: 111),
                        scale: 1, arc: 0
                    ))
                    .opacity(nameProgress)
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
                identity
                brandMode.background.frame(height: toolbarBottom).allowsHitTesting(false)
                brandMode.background.frame(height: topInset).offset(y: -topInset).allowsHitTesting(false)
            }
            navigation
                .frame(width: navigationRect.width, height: navigationRect.height)
                .position(x: width / 2, y: (initialNavigation ?? navigationRect).midY)
        }
        .onAppear {
            initialAvatar = avatarRect
            initialName = nameRect
            initialNavigation = navigationRect
            initialBio = bioRect
        }
        .onChange(of: avatarRect.minY) { _, _ in
            guard let initialAvatar else { return }
            let offset = initialAvatar.minY - avatarRect.minY
            let viewportTop = initialNavigation?.maxY ?? 0
            let viewportAvatar = initialAvatar.offsetBy(dx: 0, dy: -viewportTop)
            let restoreBoundary = variant == .compact ? initialBio.map { $0.maxY - viewportTop } : nil
            let entryBoundary = variant == .compact ? initialName.map { max(0, $0.minY - viewportTop) } : nil
            guard motion.update(offset: offset, originalAvatar: viewportAvatar,
                                entryBoundary: entryBoundary, restoreBoundary: restoreBoundary) else { return }
            // Freeze the entry geometry while the content continues to scroll.
            // A downward curve keeps the portrait clear of the pinned toolbar.
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
}

/// Keep the blur layer opaque as a compositor while reducing the material's
/// intensity. Lowering the view alpha would reveal a second, sharp copy of
/// scrolling text under the name and clock.
private struct ProfileMotionBackdropBlur: UIViewRepresentable {
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

        private func configure() {
            stop()
            effect = nil
            let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
                self?.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            }
            self.animator = animator
            animator.fractionComplete = 0.65
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
#endif
