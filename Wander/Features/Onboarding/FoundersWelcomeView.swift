import AVKit
import SwiftUI

/// Separate from NUX completion: finishing/skipping this film never completes
/// Ryan's walkthrough, and an interrupted film can resume without repeating setup.
@MainActor
final class FoundersWelcomeStore {
    struct Progress: Codable, Equatable {
        var seconds: Double = 0
        var handled = false
    }

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ userID: String) -> String { "astir.founders-welcome.v1.\(userID)" }
    func progress(for userID: String) -> Progress {
        guard let data = defaults.data(forKey: key(userID)),
              let value = try? JSONDecoder().decode(Progress.self, from: data) else { return Progress() }
        return value
    }
    func save(seconds: Double, for userID: String) {
        guard seconds.isFinite else { return }
        var value = progress(for: userID)
        value.seconds = min(FoundersWelcomePlayer.duration, max(0, seconds))
        write(value, for: userID)
    }
    func finish(for userID: String) {
        var value = progress(for: userID)
        value.handled = true
        write(value, for: userID)
    }
    private func write(_ value: Progress, for userID: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key(userID)) }
    }
}

struct FoundersWelcomeGate<Content: View>: View {
    let userID: String
    let isEligible: Bool
    private let store: FoundersWelcomeStore
    private let content: () -> Content
    @State private var handled: Bool

    init(userID: String, isEligible: Bool, store: FoundersWelcomeStore = FoundersWelcomeStore(),
         @ViewBuilder content: @escaping () -> Content) {
        self.userID = userID
        self.isEligible = isEligible
        self.store = store
        self.content = content
        _handled = State(initialValue: store.progress(for: userID).handled)
    }

    var body: some View {
        // Do not construct WanderRootView while the film is showing: the Map
        // walkthrough's timers and automatic Feed transition must wait for exit.
        if isEligible && !handled {
            FoundersWelcomeView(
                initialPosition: store.progress(for: userID).seconds,
                savePosition: { store.save(seconds: $0, for: userID) },
                finish: {
                    store.finish(for: userID)
                    handled = true
                }
            )
        } else {
            content()
        }
    }
}

struct FoundersWelcomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: FoundersWelcomePlayer
    @State private var isLeaving = false
    let finish: () -> Void

    init(initialPosition: Double = 0, savePosition: @escaping (Double) -> Void = { _ in },
         finish: @escaping () -> Void) {
        _model = StateObject(wrappedValue: FoundersWelcomePlayer(initialPosition: initialPosition, savePosition: savePosition))
        self.finish = finish
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("A quick hello").font(AstirTypography.sheetTitle)
                    Text("From Joe & Ryan · 1:31").font(AstirTypography.caption)
                        .foregroundStyle(AstirTheme.mutedOnInk.color)
                }
                Spacer(minLength: 12)
                Button("Skip intro", action: leave)
                    .font(AstirTypography.label)
                    .foregroundStyle(AstirTheme.paper.color)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onboarding.founders.skip")
            }
            ZStack {
                Color.black
                VideoPlayer(player: model.player)
                    .opacity(model.hasStarted ? 1 : 0)
                    .accessibilityHidden(!model.hasStarted)
                    .accessibilityIdentifier("onboarding.founders.player")
                if !model.hasStarted {
                    if let path = Bundle.main.path(forResource: "founders-welcome-poster", ofType: "png"),
                       let image = UIImage(contentsOfFile: path) {
                        Image(uiImage: image).resizable().scaledToFit().accessibilityHidden(true)
                    }
                    Button(action: model.play) {
                        Label(model.position > 1 ? "Resume welcome" : "Play welcome", systemImage: "play.fill")
                            .font(AstirTypography.label)
                            .padding(.horizontal, 22).padding(.vertical, 16)
                            .background(AstirTheme.signal.color, in: Capsule())
                            .foregroundStyle(AstirTheme.ink.color)
                    }
                    .accessibilityIdentifier("onboarding.founders.play")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let failure = model.failure {
                Text(failure).font(AstirTypography.bodySmall)
                Button("Try again", action: model.play)
                    .accessibilityIdentifier("onboarding.founders.retry")
            } else if model.hasStarted {
                HStack {
                    Button(action: model.togglePlayback) {
                        Label(model.isPlaying ? "Pause" : "Resume", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .accessibilityIdentifier("onboarding.founders.pause")
                    Spacer()
                    Button(action: { model.player.isMuted.toggle(); model.isMuted = model.player.isMuted }) {
                        Label(model.isMuted ? "Sound on" : "Mute", systemImage: model.isMuted ? "speaker.slash" : "speaker.wave.2")
                    }
                    .accessibilityIdentifier("onboarding.founders.mute")
                }
                .font(AstirTypography.label)
                .frame(minHeight: 44)
            } else {
                Text("A little about why we made Astir.")
                    .font(AstirTypography.bodySmall).foregroundStyle(AstirTheme.mutedOnInk.color)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .foregroundStyle(AstirTheme.paper.color)
        .background(AstirTheme.ink.color.ignoresSafeArea())
        .opacity(isLeaving ? 0 : 1)
        .allowsHitTesting(!isLeaving)
        .onChange(of: model.didFinish) { _, ended in if ended { leave() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.pause() } }
        .onDisappear { model.tearDown() }
        .task(id: isLeaving) {
            guard isLeaving else { return }
            if !reduceMotion {
                do { try await Task.sleep(for: .milliseconds(220)) }
                catch { return }
            }
            finish()
        }
    }

    private func leave() {
        guard !isLeaving else { return }
        model.tearDown()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { isLeaving = true }
    }
}

@MainActor
final class FoundersWelcomePlayer: ObservableObject {
    static let duration = 91.0
    let player = AVPlayer()
    @Published var hasStarted = false
    @Published var isPlaying = false
    @Published var isMuted = false
    @Published var didFinish = false
    @Published var failure: String?
    private(set) var position: Double
    private let savePosition: (Double) -> Void
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var lastSavedSecond = -1
    private var finished = false
    private var ownsAudioSession = false

    init(initialPosition: Double, savePosition: @escaping (Double) -> Void) {
        position = min(Self.duration - 0.1, max(0, initialPosition.isFinite ? initialPosition : 0))
        self.savePosition = savePosition
        prepare()
    }

    private func prepare() {
        guard let url = Bundle.main.url(forResource: "founders-welcome", withExtension: "mp4") else {
            failure = "The welcome video couldn’t load. You can continue into Astir."
            return
        }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .pause
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.player.currentItem?.status == .failed {
                    self.pause()
                    self.failure = "The welcome video couldn’t play. Try again or skip into Astir."
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.didFinish = true }
        }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                guard let self, seconds.isFinite else { return }
                self.position = seconds
                self.isPlaying = self.player.rate > 0
                let bucket = Int(seconds / 5)
                if bucket != self.lastSavedSecond {
                    self.lastSavedSecond = bucket
                    self.savePosition(seconds)
                }
            }
        }
    }

    func play() {
        guard !finished else { return }
        if player.currentItem == nil || player.currentItem?.status == .failed {
            removeObservers()
            prepare()
        }
        guard player.currentItem != nil else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            ownsAudioSession = true
            failure = nil
            hasStarted = true
            player.play()
            isPlaying = true
        } catch {
            failure = "Audio couldn’t start. Try again or skip into Astir."
        }
    }
    func togglePlayback() { player.rate > 0 ? pause() : play() }
    func pause() {
        player.pause()
        isPlaying = false
        savePosition(position)
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
    }
    func tearDown() {
        guard !finished else { return }
        finished = true
        pause()
        removeObservers()
        player.replaceCurrentItem(with: nil)
    }
    private func removeObservers() {
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver); self.interruptionObserver = nil }
        statusObserver?.invalidate(); statusObserver = nil
    }
}
