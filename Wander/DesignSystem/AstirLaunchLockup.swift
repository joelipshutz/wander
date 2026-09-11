import SwiftUI

enum AstirLaunchArtwork {
    static let wordmark = "AstirLaunchWordmark"
    static let stirMask = "AstirLaunchSTIRMask"
    static let aspectRatio = 1600.0 / 764.0
    static let background = Color(red: 8 / 255.0, green: 10 / 255.0, blue: 9 / 255.0)
    static let text = Color(red: 230 / 255.0, green: 221 / 255.0, blue: 205 / 255.0)

    static func width(availableWidth: CGFloat) -> CGFloat {
        min(460, max(0, availableWidth - 32))
    }
}

/// A view-local clock; this does not participate in app readiness or map loading.
enum AstirLaunchGlimmer {
    static let duration: TimeInterval = 5.4
    static let letterMinX = 712.6011648247104 / 2200
    static let letterWidth = 1187.4397566815144 / 2200

    struct Frame: Equatable {
        let center: Double
        let opacity: Double
    }

    static func shouldAnimate(
        reduceMotion: Bool,
        sceneIsActive: Bool,
        isVisible: Bool,
        isEnabled: Bool
    ) -> Bool {
        !reduceMotion && sceneIsActive && isVisible && isEnabled
    }

    static func frame(elapsed: TimeInterval) -> Frame {
        let safeElapsed = elapsed.isFinite ? max(0, elapsed) : 0
        let phase = safeElapsed.truncatingRemainder(dividingBy: duration) / duration
        let progress = min(1, max(0, (phase - 0.12) / 0.76))
        let eased = progress * progress * (3 - 2 * progress)
        let fadeIn = min(1, max(0, (phase - 0.12) / 0.13))
        let fadeOut = min(1, max(0, (0.88 - phase) / 0.13))
        return Frame(
            center: letterMinX + letterWidth * (-0.2 + 1.4 * eased),
            opacity: min(fadeIn, fadeOut) * 0.22
        )
    }
}

/// The approved still PNG remains the base layer. Only the aligned STIR mask
/// receives a restrained screen-blended highlight; the photographic A and plinth
/// never enter the animated layer.
struct AstirLaunchLockup: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var animationsEnabled = true

    @State private var isVisible = false
    @State private var startedAt = Date.now

    private var shouldAnimate: Bool {
        AstirLaunchGlimmer.shouldAnimate(
            reduceMotion: reduceMotion,
            sceneIsActive: scenePhase == .active,
            isVisible: isVisible,
            isEnabled: animationsEnabled
        )
    }

    var body: some View {
        Image(AstirLaunchArtwork.wordmark)
            .resizable()
            .interpolation(.high)
            .aspectRatio(AstirLaunchArtwork.aspectRatio, contentMode: .fit)
            .overlay {
                if shouldAnimate {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        highlight(AstirLaunchGlimmer.frame(
                            elapsed: context.date.timeIntervalSince(startedAt)
                        ))
                    }
                    .blendMode(.screen)
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .onChange(of: shouldAnimate) { _, active in
                if active { startedAt = .now }
            }
    }

    private func highlight(_ frame: AstirLaunchGlimmer.Frame) -> some View {
        let halfWidth = AstirLaunchGlimmer.letterWidth * 0.135
        let light = Color(red: 1, green: 250 / 255.0, blue: 239 / 255.0)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: light.opacity(0.11), location: 0.27),
                .init(color: light, location: 0.48),
                .init(color: light.opacity(0.74), location: 0.56),
                .init(color: light.opacity(0.13), location: 0.78),
                .init(color: .clear, location: 1)
            ],
            startPoint: UnitPoint(x: frame.center - halfWidth, y: 440 / 1050.0),
            endPoint: UnitPoint(x: frame.center + halfWidth, y: 600 / 1050.0)
        )
        .opacity(frame.opacity)
        .mask {
            Image(AstirLaunchArtwork.stirMask)
                .resizable()
                .interpolation(.high)
                .aspectRatio(AstirLaunchArtwork.aspectRatio, contentMode: .fit)
        }
    }
}
