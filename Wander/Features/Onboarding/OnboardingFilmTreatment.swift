import AVFoundation
import SwiftUI
import UIKit

/// Optional review treatments. Release and ordinary debug launches stay approved.
enum OnboardingVisualTreatment: String, Equatable, CaseIterable {
    case approved
    case film
    case filmType = "film-type"

    var isFilm: Bool { self != .approved }
    var matchesFilmType: Bool { self == .filmType }
    static let background = Color(red: 12 / 255, green: 16 / 255, blue: 16 / 255)
    static let signal = Color(red: 215 / 255, green: 117 / 255, blue: 84 / 255)

    static func resolved(environment: [String: String]) -> Self {
        #if DEBUG
        Self(rawValue: environment["WANDER_ONBOARDING_TREATMENT"] ?? "") ?? .approved
        #else
        .approved
        #endif
    }

    func headline(size: CGFloat, approved: Font) -> Font {
        matchesFilmType ? .custom("HelveticaNeue-CondensedBlack", size: size * 1.12) : approved
    }

    func leadFont(size: CGFloat, approved: Font) -> Font {
        matchesFilmType ? .custom("HelveticaNeue-BoldItalic", size: size * 1.12) : approved
    }
}

private struct OnboardingVisualTreatmentKey: EnvironmentKey {
    static let defaultValue = OnboardingVisualTreatment.approved
}
private struct OnboardingFilmMotionKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var onboardingVisualTreatment: OnboardingVisualTreatment {
        get { self[OnboardingVisualTreatmentKey.self] }
        set { self[OnboardingVisualTreatmentKey.self] = newValue }
    }
    var onboardingFilmMotion: Bool {
        get { self[OnboardingFilmMotionKey.self] }
        set { self[OnboardingFilmMotionKey.self] = newValue }
    }
}

struct OnboardingMotionPreferenceKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Timing and signal faults translated from the selected Events 03C renderer.
/// Stable Signal hue; brief density failures and three tracking hits every 8s.
struct OnboardingFilmFrame: Equatable {
    let time: Double
    let moving: Bool
    static let still = Self(time: 0, moving: false)
    var tick: Int { Int(time * 24) }
    var tracking: Bool {
        guard moving else { return false }
        let t = time.truncatingRemainder(dividingBy: 8)
        return (1.68..<1.88).contains(t) || (4.72..<4.88).contains(t) || (6.93..<7.18).contains(t)
    }
    var density: Double {
        guard moving else { return 0.94 }
        let t = time.truncatingRemainder(dividingBy: 12)
        let failures: [(Double, Double, Double)] = [
            (0.72, 0.81, 0.35), (0.81, 0.86, 0.94), (0.86, 0.99, 0.16),
            (1.04, 1.13, 0.58), (3.20, 3.28, 0.12), (3.31, 3.45, 0.43),
            (5.74, 5.88, 0.35), (5.88, 5.94, 1.0), (5.94, 6.08, 0.18),
            (8.64, 8.76, 0.38), (8.79, 8.91, 0.06), (9.00, 9.13, 0.51),
            (10.47, 10.60, 0.28)
        ]
        let power = failures.first { ($0.0..<$0.1).contains(t) }?.2 ?? 0.94
        return power * (1 - 0.07 * (0.5 + 0.5 * sin(time * 17.4)))
    }
    var bandCenter: Double { 0.16 + 0.69 * Self.noise(floor(time * 2), 2.8) }
    var verticalSlip: Double { tracking ? 3.8 * sin(time * 31) : 0 }

    func displacement(row: Double, width: Double) -> Double {
        guard moving else { return 0 }
        let fine = (Self.noise(floor(row * 240), Double(tick)) - 0.5) * 0.36
        let wobble = sin(row * 11 + time * 2.1) * 0.00043 + sin(row * 41 - time * 4.4) * 0.0001
        let band = max(0, 1 - abs(row - bandCenter) / 0.10)
        let tear = tracking ? band * 0.098 * sin(time * 41) : 0
        return fine + width * (wobble + tear)
    }
    static func noise(_ x: Double, _ y: Double) -> Double {
        let value = sin(x * 127.1 + y * 311.7) * 43758.5453123
        return value - floor(value)
    }
}

/// Only the decorated subviews redraw. Pausing holds the current frame; Reduce
/// Motion always uses undistorted static ink, even if toggled during a fault.
private struct OnboardingFilmPlayback<Content: View>: View {
    @Environment(\.onboardingFilmMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var epoch = Date.now
    @State private var heldTime = 0.0
    let content: (OnboardingFilmFrame) -> Content
    private var plays: Bool { motion && !reduceMotion && scenePhase == .active }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24.0, paused: !plays)) { context in
            let elapsed = heldTime + (plays ? max(0, context.date.timeIntervalSince(epoch)) : 0)
            content(reduceMotion ? .still : OnboardingFilmFrame(time: elapsed + 0.17, moving: elapsed > 0))
        }
        .onChange(of: plays) { _, isPlaying in
            if isPlaying { epoch = .now }
            else { heldTime += max(0, Date.now.timeIntervalSince(epoch)) }
        }
    }
}

/// The original view retains its layout, accessibility and hit area. Canvas
/// resolves its SwiftUI drawing once, then shifts rows of that native symbol.
private struct OnboardingFilmInk: ViewModifier {
    @Environment(\.onboardingVisualTreatment) private var treatment

    @ViewBuilder func body(content: Content) -> some View {
        if treatment.isFilm {
            content.opacity(0.001)
                .overlay {
                    OnboardingFilmPlayback { frame in
                        OnboardingFilmSignal(frame: frame, ink: content)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        } else {
            content
        }
    }
}

private struct OnboardingFilmSignal<Ink: View>: View {
    let frame: OnboardingFilmFrame
    let ink: Ink

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            guard let symbol = context.resolveSymbol(id: 0) else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + frame.verticalSlip)
            context.opacity = frame.density
            context.drawLayer { signal in
                // The reference leaves a warm, delayed smear beyond the glyph.
                var bleed = signal
                bleed.addFilter(.colorMultiply(Color(red: 0.72, green: 0.19, blue: 0.10)))
                bleed.addFilter(.blur(radius: frame.tracking ? 2.4 : 1.3))
                bleed.opacity = 0.38
                bleed.draw(symbol, at: CGPoint(x: center.x - 2.2, y: center.y + 0.15))
                bleed.opacity = 0.16
                bleed.draw(symbol, at: CGPoint(x: center.x - 4.1, y: center.y))

                // Different rows acquire different line-time errors. The broad
                // fault bends only a band of lettering, rather than translating
                // the entire label like an ordinary digital shake animation.
                let rowHeight: CGFloat = 2
                for y in stride(from: CGFloat.zero, to: size.height, by: rowHeight) {
                    var row = signal
                    row.clip(to: Path(CGRect(x: -8, y: y, width: size.width + 16, height: min(rowHeight, size.height - y))))
                    let fraction = Double(y / max(1, size.height))
                    let shift = frame.displacement(row: fraction, width: size.width)
                    if frame.tracking, abs(fraction - frame.bandCenter) < 0.10 { row.opacity = 0.48 }
                    row.draw(symbol, at: CGPoint(x: center.x + shift, y: center.y))
                }

                signal.blendMode = .destinationOut
                signal.opacity = frame.tracking ? 0.43 : 0.24
                var scanlines = Path()
                for y in stride(from: CGFloat(frame.tick % 3) / 3, to: size.height, by: 1) {
                    scanlines.addRect(CGRect(x: 0, y: y, width: size.width, height: 0.32))
                }
                signal.fill(scanlines, with: .color(.black))

                // Sparse holes and irregular flecks, rather than a regular grid.
                signal.opacity = 0.64
                var wear = Path()
                for point in 0..<190 {
                    let x = OnboardingFilmFrame.noise(Double(point), 41) * size.width
                    let y = OnboardingFilmFrame.noise(Double(point), 13) * size.height
                    let width = 0.28 + OnboardingFilmFrame.noise(Double(point), 7) * 1.1
                    wear.addRect(CGRect(x: x, y: y, width: width, height: 0.4 + width * 0.75))
                }
                signal.fill(wear, with: .color(.black))
                signal.opacity = 0.22
                var grain = Path()
                for point in 0..<1200 {
                    let x = OnboardingFilmFrame.noise(Double(point), Double(frame.tick) + 19) * size.width
                    let y = OnboardingFilmFrame.noise(Double(point), Double(frame.tick) + 71) * size.height
                    grain.addRect(CGRect(x: x, y: y, width: 0.4, height: 0.6))
                }
                signal.fill(grain, with: .color(.black))
                if frame.moving, frame.tick % 11 < 2 {
                    signal.opacity = 0.56
                    let x = OnboardingFilmFrame.noise(Double(frame.tick), 3) * size.width * 0.7
                    let y = OnboardingFilmFrame.noise(Double(frame.tick), 8) * size.height
                    signal.fill(Path(CGRect(x: x, y: y, width: size.width * 0.22, height: 0.65)), with: .color(.black))
                }
            }
        } symbols: {
            ink.tag(0)
        }
    }
}

/// The native Map/activity views remain native. Rare registration slips affect
/// their visual surface; navigation and the bottom controls stay anchored.
private struct OnboardingFilmSurface: ViewModifier {
    @Environment(\.onboardingVisualTreatment) private var treatment
    @ViewBuilder func body(content: Content) -> some View {
        if treatment.isFilm {
            OnboardingFilmPlayback { frame in
                content
                    .offset(x: frame.tracking ? sin(frame.time * 41) * 2.8 : 0,
                            y: frame.tracking ? sin(frame.time * 31) * 1.2 : 0)
            }
        } else { content }
    }
}

/// Fine dust plus occasional wandering tracking/head-switching bands over the
/// whole picture. The strokes are brief and sparse, as in Events 03C.
struct OnboardingFilmArtifacts: View {
    var body: some View {
        OnboardingFilmPlayback { frame in
            Canvas(rendersAsynchronously: true) { context, size in
                var dust = Path()
                for point in 0..<165 {
                    let x = OnboardingFilmFrame.noise(Double(point), Double(frame.tick) + 23) * size.width
                    let y = OnboardingFilmFrame.noise(Double(point), Double(frame.tick) + 47) * size.height
                    dust.addRect(CGRect(x: x, y: y, width: point % 9 == 0 ? 1.2 : 0.45, height: 0.55))
                }
                context.opacity = 0.24
                context.fill(dust, with: .color(Color(red: 0.82, green: 0.84, blue: 0.77)))
                if frame.moving, frame.tick % 17 < 3 {
                    context.opacity = 0.20
                    let y = OnboardingFilmFrame.noise(Double(frame.tick / 3), 22) * size.height
                    let x = OnboardingFilmFrame.noise(Double(frame.tick / 3), 52) * size.width * 0.65
                    context.fill(Path(CGRect(x: x, y: y, width: size.width * 0.32, height: 0.5)), with: .color(.white))
                }
                if frame.tracking {
                    let center = frame.bandCenter * size.height
                    let band = CGRect(x: 0, y: center - 12, width: size.width, height: 24)
                    context.opacity = 0.23
                    context.fill(Path(band), with: .color(.black))
                    context.opacity = 0.18
                    for line in 0..<12 {
                        let x = OnboardingFilmFrame.noise(Double(line), Double(frame.tick)) * size.width
                        let y = size.height * 0.93 + Double(line) * 1.2
                        context.fill(Path(CGRect(x: x, y: y, width: size.width * 0.16, height: 0.6)), with: .color(.white))
                    }
                }
            }
        }
    }
}

extension View {
    func onboardingFilmInk() -> some View { modifier(OnboardingFilmInk()) }
    func onboardingFilmSurface() -> some View { modifier(OnboardingFilmSurface()) }
}

/// The exact unlettered Higgsfield texture used by Coming Soon, reused locally.
/// Screen blending at reduced opacity keeps its horizontal scratches quiet.
struct OnboardingFilmTexture: UIViewRepresentable {
    let isPlaying: Bool
    let reduceMotion: Bool

    func makeUIView(context: Context) -> OnboardingFilmTextureView { OnboardingFilmTextureView() }
    func updateUIView(_ view: OnboardingFilmTextureView, context: Context) {
        view.update(isPlaying: isPlaying && !reduceMotion, staticOnly: reduceMotion)
    }
    static func dismantleUIView(_ view: OnboardingFilmTextureView, coordinator: ()) { view.tearDown() }
}

@MainActor final class OnboardingFilmTextureView: UIView {
    private let poster = UIImageView()
    private let videoLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var readiness: NSKeyValueObservation?
    private var staticOnly = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = .black
        if let path = Bundle.main.path(forResource: "onboarding-film-texture", ofType: "png") {
            poster.image = UIImage(contentsOfFile: path)
        }
        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        addSubview(poster)
        videoLayer.videoGravity = .resizeAspectFill
        videoLayer.isHidden = true
        layer.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        poster.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { player?.pause() }
    }
    func update(isPlaying: Bool, staticOnly: Bool) {
        self.staticOnly = staticOnly
        if staticOnly { player?.pause(); videoLayer.isHidden = true; return }
        guard isPlaying else { player?.pause(); return }
        if player == nil, let url = Bundle.main.url(forResource: "onboarding-film-texture", withExtension: "mp4") {
            let queue = AVQueuePlayer()
            queue.isMuted = true
            queue.volume = 0
            queue.preventsDisplaySleepDuringVideoPlayback = false
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 1
            player = queue
            looper = AVPlayerLooper(player: queue, templateItem: item)
            videoLayer.player = queue
            readiness = videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.videoLayer.isHidden = self.staticOnly || !self.videoLayer.isReadyForDisplay
                }
            }
        }
        videoLayer.isHidden = !videoLayer.isReadyForDisplay
        player?.play()
    }
    func tearDown() {
        readiness?.invalidate()
        readiness = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        videoLayer.player = nil
        player?.removeAllItems()
        player = nil
    }
}
