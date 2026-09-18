import SwiftUI

/// The selected 06 study: a quiet hold and one short analog tracking episode.
/// The scheduler sleeps between episodes; only this label owns frame updates.
enum AstirOceanParkTracking {
    static let initialDelay: TimeInterval = 3
    static let interval: ClosedRange<TimeInterval> = 25...30
    static let duration: TimeInterval = 0.96
    static let frameInterval: TimeInterval = 1.0 / 24

    struct Frame: Equatable {
        let tick: Int
        let isTearing: Bool
    }

    static func shouldAnimate(enabled: Bool, visible: Bool, active: Bool, reduceMotion: Bool) -> Bool {
        enabled && visible && active && !reduceMotion
    }

    static func frame(elapsed: TimeInterval) -> Frame? {
        guard elapsed.isFinite, elapsed >= 0, elapsed < duration else { return nil }
        return Frame(tick: Int((1.36 + elapsed) * 24), isTearing: (0.35..<0.58).contains(elapsed))
    }

    @MainActor
    static func run(
        nextInterval: () -> TimeInterval = { Double.random(in: interval) },
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        update: (Frame?) -> Void
    ) async {
        defer { update(nil) }
        do {
            try await sleep(initialDelay)
            while !Task.isCancelled {
                let start = now()
                let next = start + nextInterval()
                while let frame = frame(elapsed: now() - start) {
                    try Task.checkCancellation()
                    update(frame)
                    try await sleep(max(0, min(frameInterval, duration - (now() - start))))
                }
                update(nil)
                // Onset-to-onset timing; rendering work does not extend the interval.
                try await sleep(max(0, next - now()))
            }
        } catch {
            // View disappearance, backgrounding or Reduce Motion cancels the sleep.
        }
    }
}

struct AstirOceanParkLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.astirBrandMode) private var brandMode
    let isCompact: Bool
    let animationsEnabled: Bool
    @State private var visible = false
    @State private var frame: AstirOceanParkTracking.Frame?

    private var shouldAnimate: Bool {
        AstirOceanParkTracking.shouldAnimate(
            enabled: animationsEnabled, visible: visible,
            active: scenePhase == .active, reduceMotion: reduceMotion
        )
    }

    private var label: Text {
        Text("OCEAN PARK")
            .font(AstirTheme.metadata(isCompact ? 6.5 : 7.5))
            .tracking(isCompact ? 1.8 : 2.3)
    }

    var body: some View {
        label
            .opacity(shouldAnimate && frame != nil ? 0 : 1)
            .overlay {
                if shouldAnimate, let frame {
                    AstirOceanParkSignal(label: label, color: brandMode.primaryText, frame: frame)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .task(id: shouldAnimate) {
                guard shouldAnimate else { frame = nil; return }
                await AstirOceanParkTracking.run { frame = $0 }
            }
    }
}

/// Draw into the label's own bounds, never the masthead material or the Map.
/// Texture is a small deterministic set of native strokes, with no video asset.
struct AstirOceanParkSignal: View {
    let label: Text
    let color: Color
    let frame: AstirOceanParkTracking.Frame

    var body: some View {
        Canvas { context, size in
            let text = context.resolve(label.foregroundStyle(color))
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let tear = CGRect(x: 0, y: size.height * 0.48, width: size.width, height: size.height * 0.15)
            context.drawLayer { ink in
                if frame.isTearing {
                    var intact = ink
                    intact.clip(to: Path(tear), options: .inverse)
                    intact.draw(text, at: center)
                    var shifted = ink
                    shifted.clip(to: Path(tear))
                    shifted.draw(text, at: CGPoint(x: center.x + 1.6, y: center.y))
                } else {
                    ink.draw(text, at: center)
                }
                ink.blendMode = .destinationOut
                ink.opacity = frame.isTearing ? 0.40 : 0.10
                var scanlines = Path()
                for row in stride(from: CGFloat(frame.tick % 3) / 3, to: size.height, by: 1) {
                    scanlines.addRect(CGRect(x: 0, y: row, width: size.width, height: 0.27))
                }
                ink.fill(scanlines, with: .color(.black))
                ink.opacity = frame.isTearing ? 0.40 : 0.045
                var noise = Path()
                for point in 0..<70 {
                    let x = CGFloat((point * 37 + frame.tick * 19) % 220) / 220 * size.width
                    let y = CGFloat((point * 13 + frame.tick * 7) % 20) / 20 * size.height
                    noise.addRect(CGRect(x: x, y: y, width: 0.37, height: 0.27))
                }
                ink.fill(noise, with: .color(.black))
            }
        }
    }
}
