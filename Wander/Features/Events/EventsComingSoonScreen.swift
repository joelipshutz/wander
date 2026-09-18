import AVFoundation
import SwiftUI
import UIKit

/// A local, decorative recording. It never loads event data or owns tab navigation.
struct EventsComingSoonScreen: View {
    let isSelected: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        EventsVideoSurface(
            policy: EventsPlaybackPolicy(
                isSelected: isSelected,
                isVisible: isVisible,
                isSceneActive: scenePhase == .active,
                reduceMotion: reduceMotion
            )
        )
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coming soon. An Ocean Park experiment.")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("events.comingSoon")
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

struct EventsPlaybackPolicy: Equatable {
    var isSelected: Bool
    var isVisible: Bool
    var isSceneActive: Bool
    var reduceMotion: Bool

    var shouldPlay: Bool {
        isSelected && isVisible && isSceneActive && !reduceMotion
    }
}

/// Caps extreme aspect ratios without cropping the lettering on small phones or
/// the iPad compatibility window. Ordinary portrait phones fill edge to edge.
enum EventsArtworkLayout {
    static let aspectRatio: CGFloat = 720.0 / 1560.0

    static func frame(in bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let width = min(bounds.width, bounds.height * 0.66)
        return CGRect(x: bounds.midX - width / 2, y: bounds.minY,
                      width: width, height: bounds.height)
    }
}

private struct EventsVideoSurface: UIViewRepresentable {
    let policy: EventsPlaybackPolicy

    func makeUIView(context: Context) -> EventsVideoView {
        EventsVideoView()
    }

    func updateUIView(_ view: EventsVideoView, context: Context) {
        view.update(policy: policy)
    }

    static func dismantleUIView(_ view: EventsVideoView, coordinator: ()) {
        view.tearDown()
    }
}

/// One hardware-decoded H.264 stream, no per-frame SwiftUI updates, Canvas,
/// display link, live shader, network request, audio session or player controls.
@MainActor final class EventsVideoView: UIView {
    private let poster = UIImageView()
    private let videoLayer = AVPlayerLayer()
    private(set) var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var preparation: Task<Void, Never>?
    private var readiness: NSKeyValueObservation?
    private var policy = EventsPlaybackPolicy(
        isSelected: false, isVisible: false, isSceneActive: false, reduceMotion: false
    )
    private(set) var preparationCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        clipsToBounds = true
        poster.image = Self.posterImage
        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        poster.backgroundColor = .black
        addSubview(poster)
        videoLayer.videoGravity = .resizeAspectFill
        videoLayer.isHidden = true
        layer.addSublayer(videoLayer)
    }

    required init?(coder: NSCoder) { return nil }

    private static let posterImage: UIImage? = {
        guard let path = Bundle.main.path(forResource: "events-coming-soon", ofType: "jpg") else { return nil }
        return UIImage(contentsOfFile: path)
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        let frame = EventsArtworkLayout.frame(in: bounds)
        poster.frame = frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = frame
        CATransaction.commit()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            preparation?.cancel()
            preparation = nil
            player?.pause()
        }
    }

    func update(policy: EventsPlaybackPolicy) {
        self.policy = policy
        guard policy.shouldPlay else {
            preparation?.cancel()
            preparation = nil
            player?.pause()
            if policy.reduceMotion { videoLayer.isHidden = true }
            return
        }
        if let player {
            videoLayer.isHidden = !videoLayer.isReadyForDisplay
            player.play()
            return
        }
        guard preparation == nil else { return }
        // The poster and native tab selection render before player setup starts.
        preparation = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, self.policy.shouldPlay else { return }
            self.preparePlayer()
            self.preparation = nil
        }
    }

    private func preparePlayer() {
        guard player == nil,
              let url = Bundle.main.url(forResource: "events-coming-soon", withExtension: "mp4")
        else { return }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 1
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.volume = 0
        queue.preventsDisplaySleepDuringVideoPlayback = false
        queue.automaticallyWaitsToMinimizeStalling = false
        player = queue
        preparationCount += 1
        looper = AVPlayerLooper(player: queue, templateItem: item)
        videoLayer.player = queue
        readiness = videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.videoLayer.isHidden = !self.videoLayer.isReadyForDisplay || self.policy.reduceMotion
            }
        }
        if policy.shouldPlay { queue.play() }
    }

    func tearDown() {
        preparation?.cancel()
        preparation = nil
        readiness?.invalidate()
        readiness = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        videoLayer.player = nil
        player?.removeAllItems()
        player = nil
        videoLayer.isHidden = true
    }
}

#Preview {
    EventsComingSoonScreen(isSelected: true)
}
