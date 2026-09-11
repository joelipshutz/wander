import SwiftUI

// The release build keeps the original profile layout. These hooks only enable
// the review prototype when its explicit DEBUG preview environment is present.
enum ProfileMotionSource: Hashable { case avatar, name, navigation }

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
    case glide, spring, arc

    var title: String {
        switch self {
        case .glide: "01 · Glide"
        case .spring: "02 · Soft spring"
        case .arc: "03 · Staged arc"
        }
    }

    static func resolved(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        guard let index = arguments.firstIndex(of: "-ProfileHeaderMotion"),
              arguments.indices.contains(index + 1) else { return nil }
        return Self(rawValue: arguments[index + 1])
    }

    var animation: Animation {
        switch self {
        case .glide: .easeInOut(duration: 0.62)
        case .spring: .spring(duration: 0.78, bounce: 0.24)
        case .arc: .easeInOut(duration: 0.8)
        }
    }
}

struct ProfileHeaderMotionState {
    private(set) var expanded = false
    private(set) var previousOffset: CGFloat = 0

    mutating func update(offset: CGFloat, originalAvatar: CGRect) -> Bool {
        let wasExpanded = expanded
        // The midpoint / lower edge are measured in the visible viewport.
        // The overlay subtracts the pinned control row before passing this rect.
        if offset > previousOffset, offset >= originalAvatar.midY {
            expanded = true
        } else if offset < previousOffset, offset <= originalAvatar.maxY {
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
                .opacity(0)
                .accessibilityHidden(true)
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
                            width: proxy.size.width
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
    let width: CGFloat
    @State private var initialAvatar: CGRect?
    @State private var initialNavigation: CGRect?
    @State private var motion = ProfileHeaderMotionState()
    @State private var photoProgress: CGFloat = 0
    @State private var nameProgress: CGFloat = 0
    @State private var surfaceProgress: CGFloat = 0

    private var displayName: some View {
        Text(name)
            .font(AstirTypography.sheetTitle)
            .foregroundStyle(brandMode.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: nameRect.width, height: nameRect.height)
            .allowsHitTesting(false)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                brandMode.background.frame(height: 294)
                LinearGradient(colors: [brandMode.background, brandMode.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 22)
            }
            .opacity(surfaceProgress)
            .allowsHitTesting(false)

            avatar
                .modifier(ProfileMotionTransform(
                    progress: photoProgress, source: avatarRect,
                    destination: CGPoint(x: width / 2, y: 150), scale: 2,
                    arc: variant == .arc ? 34 : 0
                ))
                .allowsHitTesting(false)
                .accessibilityLabel("\(name)'s profile photo")

            if variant == .arc {
                // In this option the name leaves with the inline identity and
                // rises into its final position after the portrait leads.
                displayName
                    .position(x: nameRect.midX, y: nameRect.midY)
                    .opacity(1 - surfaceProgress)
                displayName
                    .scaleEffect(1 + 0.4 * nameProgress)
                    .position(x: width / 2, y: 265 + 20 * (1 - nameProgress))
                    .opacity(nameProgress)
            } else {
                displayName
                    .modifier(ProfileMotionTransform(
                        progress: nameProgress, source: nameRect,
                        destination: CGPoint(x: width / 2, y: 265), scale: 1.4,
                        arc: 0, horizontalArc: 90, easesVertically: true, containerWidth: width
                    ))
            }

            // Moving identity/content passes underneath the fixed controls.
            // Keep this opaque cover above the moving layers, including the
            // portion outside the safe area, so neither can cross the clock.
            brandMode.background
                .frame(height: (initialNavigation ?? navigationRect).maxY + 8)
                .allowsHitTesting(false)
            brandMode.background.frame(height: 100).offset(y: -100)
                .allowsHitTesting(false)
            navigation
                .frame(width: navigationRect.width, height: navigationRect.height)
                .position(x: width / 2, y: (initialNavigation ?? navigationRect).midY)
        }
        .onAppear {
            initialAvatar = avatarRect
            initialNavigation = navigationRect
        }
        .onChange(of: avatarRect.minY) { _, _ in
            guard let initialAvatar else { return }
            let offset = initialAvatar.minY - avatarRect.minY
            let viewportAvatar = initialAvatar.offsetBy(dx: 0, dy: -(initialNavigation?.maxY ?? 0))
            guard motion.update(offset: offset, originalAvatar: viewportAvatar) else { return }
            let target: CGFloat = motion.expanded ? 1 : 0
            let animation = reduceMotion ? nil : variant.animation
            withAnimation(animation) {
                photoProgress = target
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18).delay(motion.expanded ? 0 : 0.4)) {
                surfaceProgress = target
            }
            withAnimation(reduceMotion ? nil : (variant == .arc ? .easeInOut(duration: 0.56).delay(0.20) : animation)) {
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
    var horizontalArc: CGFloat = 0
    var easesVertically = false
    var containerWidth: CGFloat? = nil
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        let verticalProgress = easesVertically ? sin(progress * .pi / 2) : progress
        let rawX = source.midX + (destination.x - source.midX) * progress + sin(progress * .pi) * horizontalArc
        let halfWidth = source.width * (1 + (scale - 1) * progress) / 2
        let x = containerWidth.map { min($0 - halfWidth - 12, max(halfWidth + 12, rawX)) } ?? rawX
        content
            .scaleEffect(1 + (scale - 1) * progress)
            .position(
                x: x,
                y: source.midY + (destination.y - source.midY) * verticalProgress - sin(progress * .pi) * arc
            )
    }
}
#endif
