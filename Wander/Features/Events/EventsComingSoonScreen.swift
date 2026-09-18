import AVFoundation
import SwiftUI
import UIKit

/// A local decorative recording with a native, server-confirmed launch-interest CTA.
struct EventsComingSoonScreen: View {
    let isSelected: Bool
    var userID: String? = nil
    var repository: (any EventsInterestRepository)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @StateObject private var interest = EventsInterestModel()

    private var playbackPolicy: EventsPlaybackPolicy {
        EventsPlaybackPolicy(isSelected: isSelected, isVisible: isVisible,
                             isSceneActive: scenePhase == .active, reduceMotion: reduceMotion)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            EventsVideoSurface(policy: playbackPolicy)
                .ignoresSafeArea()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Coming soon. An Ocean Park experiment.")
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("events.comingSoon")

            Group {
                if interest.isRegistered {
                    EventsWaitlistStatus()
                } else {
                    EventsNotifyControl(
                        saving: interest.isSaving,
                        enabled: userID != nil,
                        animates: playbackPolicy.shouldPlay,
                        action: { Task { await interest.register(repository: repository) } }
                    )
                }
            }
                .frame(height: 60)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: userID) { await interest.load(userID: userID, repository: repository) }
        .task(id: isSelected) {
            if isSelected { await interest.load(userID: userID, repository: repository) }
        }
        .alert("Keep me posted", isPresented: Binding(
            get: { interest.errorMessage != nil },
            set: { if !$0 { interest.errorMessage = nil } }
        )) {
            Button("Try again") { Task { await interest.register(repository: repository) } }
            Button("Cancel", role: .cancel) { interest.errorMessage = nil }
        } message: {
            Text(interest.errorMessage ?? "")
        }
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

/// A real button with cached, distressed artwork. Core Animation supplies the
/// occasional tape flicker; no additional video decoder or per-frame SwiftUI work.
private struct EventsNotifyControl: UIViewRepresentable {
    let saving: Bool
    let enabled: Bool
    let animates: Bool
    let action: () -> Void

    final class Coordinator {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> EventsNotifyButton {
        let button = EventsNotifyButton()
        button.addAction(UIAction { [weak coordinator = context.coordinator] _ in
            coordinator?.action()
        }, for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: EventsNotifyButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = enabled && !saving
        button.alpha = saving ? 0.65 : 1
        button.accessibilityValue = saving ? "Saving" : nil
        button.accessibilityHint = "Get notified when Events launches."
        button.updateAnimation(animates && !saving)
    }

    static func dismantleUIView(_ button: EventsNotifyButton, coordinator: Coordinator) {
        button.updateAnimation(false)
    }
}

@MainActor final class EventsNotifyButton: UIButton {
    private var artworkSize: CGSize = .zero
    private let tapFeedback = UIImpactFeedbackGenerator(style: .light)
    private var animates = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "events.keepMePosted"
        accessibilityLabel = "Keep me posted"
        imageView?.contentMode = .scaleToFill
        adjustsImageWhenHighlighted = false
        backgroundColor = .clear
        addAction(UIAction { [weak self] _ in
            self?.tapFeedback.impactOccurred()
        }, for: .touchDown)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.size != artworkSize else { return }
        artworkSize = bounds.size
        setImage(EventsNotifyArtwork.image(size: bounds.size, selected: false), for: .normal)
        imageView?.frame = bounds
    }

    func updateAnimation(_ enabled: Bool) {
        guard animates != enabled else { return }
        animates = enabled
        guard enabled else {
            imageView?.layer.removeAnimation(forKey: "tape")
            return
        }
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1, 1, 0.38, 0.88, 1, 1, 0.52, 1, 1]
        opacity.keyTimes = [0, 0.21, 0.215, 0.23, 0.24, 0.59, 0.60, 0.61, 1]
        opacity.calculationMode = .discrete
        let shift = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shift.values = [0, 0, -1.4, 0.6, 0, 0, 1.8, 0, 0]
        shift.keyTimes = opacity.keyTimes
        shift.calculationMode = .discrete
        let group = CAAnimationGroup()
        group.animations = [opacity, shift]
        group.duration = 8
        group.repeatCount = .infinity
        imageView?.layer.add(group, forKey: "tape")
    }
}

/// Confirmation is static text, not a disabled button or a selected control state.
private struct EventsWaitlistStatus: UIViewRepresentable {
    func makeUIView(context: Context) -> EventsWaitlistStatusView { EventsWaitlistStatusView() }
    func updateUIView(_ view: EventsWaitlistStatusView, context: Context) {}
}

@MainActor final class EventsWaitlistStatusView: UIView {
    private let artwork = UIImageView()
    private var artworkSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityIdentifier = "events.waitlistStatus"
        accessibilityLabel = "Added to Wait List"
        addSubview(artwork)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        artwork.frame = bounds
        guard bounds.width > 0, bounds.height > 0, bounds.size != artworkSize else { return }
        artworkSize = bounds.size
        artwork.image = EventsNotifyArtwork.image(size: bounds.size, selected: true)
    }
}

@MainActor enum EventsNotifyArtwork {
    static func image(size: CGSize, selected: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            // Sampled bright ink from the recorded film footer (RGB 191/193/187).
            // The erosion below brings its midtones down with the film grain.
            let color = selected
                ? UIColor(red: 191.0 / 255, green: 193.0 / 255, blue: 187.0 / 255, alpha: 1)
                : UIColor(red: 0.843, green: 0.459, blue: 0.329, alpha: 1)
            if !selected {
                let edge = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
                let border = UIBezierPath(roundedRect: edge, cornerRadius: 12)
                color.setStroke()
                border.lineWidth = 2.2
                border.stroke()
            }
            let font = UIFont(name: "HelveticaNeue-CondensedBlack", size: 27)
                ?? UIFont.systemFont(ofSize: 25, weight: .black)
            let text = (selected ? "ADDED TO WAIT LIST" : "KEEP ME POSTED") as NSString
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color,
                                                            .kern: 0.6]
            let availableWidth = max(1, size.width - 32)
            let naturalWidth = text.size(withAttributes: attributes).width
            if naturalWidth > availableWidth {
                attributes[.font] = font.withSize(font.pointSize * availableWidth / naturalWidth)
                attributes[.kern] = 0.6 * availableWidth / naturalWidth
            }
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2,
                                 y: (size.height - textSize.height) / 2), withAttributes: attributes)
            // Erode only the ink. Clear pixels stay clear through every state.
            context.setBlendMode(.destinationOut)
            var seed: UInt64 = 542_03
            func noise() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1
                return CGFloat((seed >> 32) & 0xffff) / 65535
            }
            for _ in 0..<Int(size.width * size.height / 13) {
                let x = noise() * size.width, y = noise() * size.height
                context.setFillColor(UIColor.black.withAlphaComponent(0.12 + noise() * 0.38).cgColor)
                context.fill(CGRect(x: x, y: y, width: 0.4 + noise() * 1.3, height: 0.35 + noise() * 0.7))
            }
            for y in stride(from: CGFloat(2), to: size.height, by: 1.7) {
                context.setFillColor(UIColor.black.withAlphaComponent(0.12 + noise() * 0.10).cgColor)
                context.fill(CGRect(x: 0, y: y, width: size.width, height: 0.35))
            }
            for _ in 0..<14 {
                context.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
                context.fill(CGRect(x: noise() * size.width, y: noise() * size.height,
                                    width: 2 + noise() * 7, height: 0.5))
            }
        }.withRenderingMode(.alwaysOriginal)
    }
}
