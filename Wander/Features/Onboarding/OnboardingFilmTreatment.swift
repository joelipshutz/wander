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

/// Only native SwiftUI ink is filtered. UIKit auth controls and MapKit remain
/// real views; the decorative texture above them never participates in hit tests.
private struct OnboardingFilmInk: ViewModifier {
    @Environment(\.onboardingVisualTreatment) private var treatment
    @Environment(\.onboardingFilmMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var epoch = Date.now
    @State private var heldTime = 0.0
    private var plays: Bool { motion && !reduceMotion && scenePhase == .active }

    @ViewBuilder func body(content: Content) -> some View {
        if treatment.isFilm {
            TimelineView(.animation(minimumInterval: 1 / 24.0, paused: !plays)) { context in
                let elapsed = heldTime + (plays ? max(0, context.date.timeIntervalSince(epoch)) : 0)
                content
                    .mask { OnboardingFilmInkMask(tick: Int(elapsed * 24)) }
                    .shadow(color: OnboardingVisualTreatment.signal.opacity(0.18), radius: 0.8, x: 0.7)
                    .opacity(0.96)
            }
            .onChange(of: plays) { _, isPlaying in
                if isPlaying { epoch = .now }
                else { heldTime += max(0, Date.now.timeIntervalSince(epoch)) }
            }
        } else {
            content
        }
    }
}

/// Extends the Ocean Park label's native ink removal to full headline bounds.
/// Grain is local to the lettering; short dropout strokes replace large tears.
private struct OnboardingFilmInkMask: View {
    let tick: Int
    var body: some View {
        Canvas(rendersAsynchronously: true) { ink, size in
            ink.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            ink.blendMode = .destinationOut
            ink.opacity = 0.11
            var scanlines = Path()
            for row in stride(from: CGFloat(tick % 3) / 3, to: size.height, by: 1.4) {
                scanlines.addRect(CGRect(x: 0, y: row, width: size.width, height: 0.26))
            }
            ink.fill(scanlines, with: .color(.black))
            ink.opacity = 0.22
            var grain = Path()
            for point in 0..<2400 {
                let x = CGFloat((point * 137 + tick * 19) % 997) / 997 * size.width
                let y = CGFloat((point * 73 + tick * 7) % 991) / 991 * size.height
                grain.addRect(CGRect(x: x, y: y, width: 0.65, height: 0.5))
            }
            ink.fill(grain, with: .color(.black))
            ink.opacity = 0.55
            var wear = Path()
            for point in 0..<65 {
                let x = CGFloat((point * 113 + 41) % 997) / 997 * size.width
                let y = CGFloat((point * 71 + 13) % 991) / 991 * size.height
                wear.addRect(CGRect(x: x, y: y, width: 0.65, height: 1.1))
            }
            ink.fill(wear, with: .color(.black))
            // Quiet, intermittent short horizontal marks; no full-width gashes.
            if tick % 192 < 5 {
                ink.opacity = 0.18
                let y = CGFloat((tick / 192 * 53 + 31) % 100) / 100 * size.height
                ink.fill(Path(CGRect(x: size.width * 0.27, y: y,
                    width: size.width * 0.14, height: 0.45)), with: .color(.black))
            }
        }
    }
}

extension View {
    func onboardingFilmInk() -> some View { modifier(OnboardingFilmInk()) }
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
