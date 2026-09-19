import AVFoundation
import SwiftUI
import UIKit

/// Selected film C ships by default; debug review may compare archived treatments.
enum OnboardingVisualTreatment: String, Equatable, CaseIterable {
    case approved
    case film
    case filmType = "film-type"

    var isFilm: Bool { self != .approved }
    var matchesFilmType: Bool { self == .filmType }
    static let background = AstirTheme.ink.color
    static let signal = AstirTheme.signal.color

    static func resolved(environment: [String: String]) -> Self {
        #if DEBUG
        Self(rawValue: environment["WANDER_ONBOARDING_TREATMENT"] ?? "") ?? .filmType
        #else
        .filmType
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
private struct OnboardingFilmClockKey: EnvironmentKey {
    static let defaultValue: OnboardingFilmClock? = nil
}
private struct OnboardingFilmViewportKey: EnvironmentKey {
    static let defaultValue = CGRect.zero
}
extension EnvironmentValues {
    var onboardingFilmClock: OnboardingFilmClock? {
        get { self[OnboardingFilmClockKey.self] }
        set { self[OnboardingFilmClockKey.self] = newValue }
    }
    var onboardingFilmViewport: CGRect {
        get { self[OnboardingFilmViewportKey.self] }
        set { self[OnboardingFilmViewportKey.self] = newValue }
    }
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

/// Shared elapsed time survives a new word, a retained slide and account entry.
/// Only decorative TimelineViews tick; the whole form does not redraw at 24 Hz.
struct OnboardingFilmClock: Equatable {
    private(set) var epoch: Date
    private(set) var heldTime = 0.0
    private(set) var isPlaying = false

    init(epoch: Date = .now) { self.epoch = epoch }
    func elapsed(at date: Date) -> Double {
        heldTime + (isPlaying ? max(0, date.timeIntervalSince(epoch)) : 0)
    }
    mutating func setPlaying(_ playing: Bool, at date: Date) {
        guard playing != isPlaying else { return }
        heldTime = elapsed(at: date)
        epoch = date
        isPlaying = playing
    }
}

struct OnboardingFilmTimelineScope: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = OnboardingFilmClock()
    @State private var viewport = CGRect.zero
    let isPlaying: Bool
    private var plays: Bool { isPlaying && !reduceMotion && scenePhase == .active }

    func body(content: Content) -> some View {
        content
            .environment(\.onboardingFilmClock, clock)
            .environment(\.onboardingFilmViewport, viewport)
            .onGeometryChange(for: CGRect.self) { geometry in geometry.frame(in: .global) } action: {
                viewport = $0
            }
            .onChange(of: plays, initial: true) { _, playing in clock.setPlaying(playing, at: .now) }
    }
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
        // The source type clock is +.23s; its tape shader clock is +.17s.
        let t = (time + 0.06).truncatingRemainder(dividingBy: 12)
        let failures: [(Double, Double, Double)] = [
            (0.72, 0.81, 0.35), (0.81, 0.86, 0.94), (0.86, 0.99, 0.16),
            (1.04, 1.13, 0.58), (3.20, 3.28, 0.12), (3.31, 3.45, 0.43),
            (5.74, 5.88, 0.35), (5.88, 5.94, 1.08), (5.94, 6.08, 0.18),
            (8.64, 8.76, 0.38), (8.79, 8.91, 0.06), (9.00, 9.13, 0.51),
            (10.47, 10.60, 0.28)
        ]
        let power = failures.first { ($0.0..<$0.1).contains(t) }?.2 ?? 0.94
        return power * (1 - 0.07 * (0.5 + 0.5 * sin(time * 17.4)))
    }
    var bandCenter: Double { 0.16 + 0.69 * Self.noise(floor(time * 2), 2.8) }
    // Original export is 720 px wide from a 393 pt composition. Do not use
    // device scale: that would make the wear change between iPhone models.
    static let rasterScale = 720.0 / 393.0
    func verticalSlip(height: Double) -> Double { tracking ? -height * 0.011 * sin(time * 31) : 0 }
    func damageBand(row: Double) -> Double {
        1 - Self.smoothstep(0.08 * 0.36, 0.08, abs(row - bandCenter))
    }

    func displacement(row: Double, width: Double, height: Double = 852) -> Double {
        guard moving else { return 0 }
        let fine = (Self.noise(floor(row * height * Self.rasterScale * 0.52), Double(tick)) - 0.5) * 0.36 / Self.rasterScale
        let wobble = sin(row * 11 + time * 2.1) * 0.00043 + sin(row * 41 - time * 4.4) * 0.0001
        let tear = tracking ? damageBand(row: row) * 0.098 * sin(time * 41) : 0
        let head = 1 - Self.smoothstep(0.025, 0.125, row)
        let headNoise = (Self.noise(floor(row * height * Self.rasterScale), Double(tick)) - 0.5) * 0.012
        // Sampling source at p + offset means the drawn picture moves -offset.
        return -(fine + width * (wobble + tear + head * headNoise))
    }
    func chromaDelay(row: Double) -> Double {
        (6.6 + (tracking ? damageBand(row: row) * 9 : 0)) / Self.rasterScale
    }
    static func smoothstep(_ low: Double, _ high: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - low) / (high - low)))
        return t * t * (3 - 2 * t)
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
    @Environment(\.onboardingFilmClock) private var sharedClock
    @State private var fallbackClock = OnboardingFilmClock()
    let content: (OnboardingFilmFrame) -> Content
    private var plays: Bool { motion && !reduceMotion && scenePhase == .active }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24.0, paused: !plays)) { context in
            let elapsed = (sharedClock ?? fallbackClock).elapsed(at: context.date)
            content(reduceMotion ? .still : OnboardingFilmFrame(time: elapsed + 0.17, moving: elapsed > 0))
        }
        .onChange(of: plays, initial: true) { _, isPlaying in
            fallbackClock.setPlaying(isPlaying, at: .now)
        }
    }
}

/// The original view retains its layout, accessibility and hit area. Canvas
/// resolves its SwiftUI drawing once, then shifts rows of that native symbol.
private struct OnboardingFilmInk: ViewModifier {
    @Environment(\.onboardingVisualTreatment) private var treatment
    var isEnabled = true

    @ViewBuilder func body(content: Content) -> some View {
        if treatment.isFilm && isEnabled {
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
    @Environment(\.onboardingFilmViewport) private var viewport
    let frame: OnboardingFilmFrame
    let ink: Ink

    var body: some View {
        GeometryReader { geometry in
            let bounds = geometry.frame(in: .global)
            let field = viewport.isEmpty ? bounds : viewport
            Canvas(rendersAsynchronously: true) { context, size in
                guard let symbol = context.resolveSymbol(id: 0) else { return }
                let scale = OnboardingFilmFrame.rasterScale
                let rowHeight = 1 / scale
                let center = CGPoint(x: size.width / 2,
                                     y: size.height / 2 + frame.verticalSlip(height: field.height))
                context.drawLayer { signal in
                    // All labels sample the same screen-space line error. This
                    // also keeps outgoing/incoming slide layers in registration.
                    for y in stride(from: CGFloat.zero, to: size.height, by: rowHeight) {
                        let screenY = bounds.minY + y - field.minY
                        let fraction = 1 - screenY / max(1, field.height)
                        let shift = frame.displacement(row: fraction, width: field.width, height: field.height)
                        let band = frame.tracking ? frame.damageBand(row: fraction) : 0
                        var row = signal
                        row.clip(to: Path(CGRect(x: -24, y: y, width: size.width + 48,
                                                 height: min(rowHeight, size.height - y))))
                        row.opacity = frame.density * (1 - band * 0.58)
                        let position = CGPoint(x: center.x + shift, y: center.y)
                        // The selected film delays chroma across four samples.
                        // Keep the native glyph sharp and its color tail soft;
                        // this is registration bleed, not a blurred whole label.
                        let delay = frame.chromaDelay(row: fraction)
                        var bleed = row
                        bleed.addFilter(.colorMultiply(AstirTheme.signal.color))
                        bleed.addFilter(.blur(radius: 0.55))
                        for (offset, weight) in [(1.0, 0.44), (2.3, 0.25), (-0.55, 0.20), (3.8, 0.11)] {
                            var sample = bleed
                            sample.opacity *= weight * 0.42
                            sample.draw(symbol, at: CGPoint(x: position.x - delay * offset, y: position.y))
                        }
                        row.draw(symbol, at: position)
                    }
                    // Fine raster wear replaces the old heavy 1pt black grooves.
                    // Global phase prevents identical holes repeating per word.
                    signal.blendMode = .destinationOut
                    for y in stride(from: CGFloat.zero, to: size.height, by: rowHeight) {
                        let rasterY = (bounds.minY + y - field.minY) * scale
                        var scan = signal
                        scan.opacity = 0.10 * (0.5 + 0.5 * sin(rasterY * .pi))
                        scan.fill(Path(CGRect(x: 0, y: y, width: size.width, height: rowHeight)), with: .color(.black))
                    }
                    var grain = Path()
                    var holes = Path()
                    for point in 0..<650 {
                        let x = OnboardingFilmFrame.noise(Double(point), Double(bounds.minX) + Double(frame.tick) + 19) * size.width
                        let y = OnboardingFilmFrame.noise(Double(point), Double(bounds.minY) + Double(frame.tick) + 71) * size.height
                        let dot = CGRect(x: x, y: y, width: 0.45, height: 0.55)
                        grain.addRect(dot)
                        if point % 43 == 0 { holes.addRect(dot.insetBy(dx: -0.2, dy: -0.1)) }
                    }
                    signal.opacity = 0.055
                    signal.fill(grain, with: .color(.black))
                    signal.opacity = 0.50
                    signal.fill(holes, with: .color(.black))
                }
            } symbols: { ink.tag(0) }
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
                    let center = (1 - frame.bandCenter) * size.height
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
    func onboardingFilmInk(isEnabled: Bool = true) -> some View {
        modifier(OnboardingFilmInk(isEnabled: isEnabled))
    }
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
