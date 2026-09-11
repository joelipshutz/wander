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

    mutating func update(offset: CGFloat, originalAvatar: CGRect, restoreBoundary: CGFloat? = nil) -> Bool {
        let wasExpanded = expanded
        // The midpoint / lower edge are measured in the visible viewport.
        // The overlay subtracts the pinned control row before passing this rect.
        if offset > previousOffset, offset >= originalAvatar.midY {
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
            content.overlayPreferenceValue(ProfileMotionAnchors.self) { anchors in
                GeometryReader { proxy in
                    if let a = anchors[.avatar], let n = anchors[.name], let bar = anchors[.navigation] {
                        ProfileMotionOverlay(
                            variant: variant, avatar: avatar, name: name, navigation: navigation,
                            avatarRect: proxy[a], nameRect: proxy[n], navigationRect: proxy[bar],
                            bioRect: anchors[.bio].map { proxy[$0] }, width: proxy.size.width
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
    let variant: ProfileHeaderMotionVariant
    let avatar: A
    let name: String
    let navigation: N
    let avatarRect: CGRect
    let nameRect: CGRect
    let navigationRect: CGRect
    let bioRect: CGRect?
    let width: CGFloat
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

    var body: some View {
        ZStack(alignment: .topLeading) {
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
                displayName(color: contrastingText)
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

            // The moving identity and scroll content pass underneath the fixed
            // controls. The contrasting identity panel begins below this row.
            brandMode.background.frame(height: toolbarBottom).allowsHitTesting(false)
            brandMode.background.frame(height: 100).offset(y: -100).allowsHitTesting(false)
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
            guard motion.update(offset: offset, originalAvatar: viewportAvatar, restoreBoundary: restoreBoundary) else { return }
            // Freeze the entry geometry while the content continues to scroll.
            // A downward curve keeps the portrait clear of the pinned toolbar.
            if motion.expanded {
                entryAvatar = avatarRect
                entryName = nameRect
            }
            let target: CGFloat = motion.expanded ? 1 : 0
            withAnimation(reduceMotion ? nil : variant.animation) { photoProgress = target }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24).delay(motion.expanded ? 0 : 0.3)) {
                surfaceProgress = target
            }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.56).delay(variant == .compact ? 0 : 0.2)) {
                nameProgress = target
            }
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
