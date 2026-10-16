#if DEBUG
import Foundation

/// Disposable synthetic-test observation. Does not drive the carousel or auth.
@MainActor
enum OnboardingTimingDiagnostic {
    enum Event: String, Codable, Sendable {
        case carouselAppeared, carouselDisappeared, sceneChanged, motionChanged
        case playingChanged, pauseChanged, selectionChanged
        case timerTaskEntered, timerStarted, timerWoke, timerCancelled, timerTaskExited
        case slideTaskEntered, slideDelayWoke, slideCancelled, slideTaskExited
        case slideAnimationStarted, slideAnimationCompleted
        case startAuthRequested, authRequestDispatched
        case flowAppeared, nativeAuthPresentationChanged, nativeAuthViewAppeared
    }

    struct State: Codable, Sendable {
        var selection: Int? = nil
        var previousSelection: Int? = nil
        var generation: Int? = nil
        var slideGeneration: Int? = nil
        var autoAdvanceGeneration: Int? = nil
        var sceneActive: Bool? = nil
        var reduceMotion: Bool? = nil
        var voiceOver: Bool? = nil
        var paused: Bool? = nil
        var finished: Bool? = nil
        var playing: Bool? = nil
        var motionPlaying: Bool? = nil
        var waitSeconds: Double? = nil
        var taskCancelled: Bool? = nil
        var signUp: Bool? = nil
        var nativeAuthPresented: Bool? = nil
    }

    private struct Entry: Codable, Sendable {
        let millisecondsSinceFirstEvent: Double
        let event: Event
        let state: State
    }

    private struct Snapshot: Codable, Sendable {
        let schema: Int
        let treatment: String
        let diagnosticLaunchID: String
        let firstEventSystemUptime: TimeInterval
        let firstEventWallClockUnixTime: TimeInterval
        let eventLimit: Int
        let truncated: Bool
        let entries: [Entry]
    }

    private static let eventLimit = 128
    private static let diagnosticLaunchID = UUID().uuidString
    private static var firstEvent: (systemUptime: TimeInterval, wallClockUnixTime: TimeInterval)?
    private static var entries: [Entry] = []
    private static var truncated = false
    private static let writer = DispatchQueue(label: "com.grayline.wander.onboarding-timing-diagnostic", qos: .utility)

    private static let destination: (treatment: String, url: URL)? = {
        #if targetEnvironment(simulator)
        let arguments = Set(ProcessInfo.processInfo.arguments)
        guard Set(["-WanderOnboardingTimingDiagnostic", "-WanderAuthenticatedUITest",
                   "-WanderOnboardingUITestSignedOut"]).isSubset(of: arguments),
              let treatment = ProcessInfo.processInfo.environment["WANDER_ONBOARDING_TREATMENT"],
              ["film", "film-type"].contains(treatment),
              let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        return (treatment, cache.appendingPathComponent("rec636-onboarding-diagnostic-\(treatment).json"))
        #else
        return nil
        #endif
    }()

    static func record(_ event: Event, state: State = State()) {
        guard let destination, !truncated else { return }
        if entries.count == eventLimit {
            truncated = true
        } else {
            let now = ProcessInfo.processInfo.systemUptime
            if firstEvent == nil { firstEvent = (now, Date().timeIntervalSince1970) }
            entries.append(Entry(millisecondsSinceFirstEvent: (now - (firstEvent?.systemUptime ?? now)) * 1_000,
                                 event: event, state: state))
        }
        guard let firstEvent else { return }
        let snapshot = Snapshot(schema: 1, treatment: destination.treatment,
                                diagnosticLaunchID: diagnosticLaunchID,
                                firstEventSystemUptime: firstEvent.systemUptime,
                                firstEventWallClockUnixTime: firstEvent.wallClockUnixTime,
                                eventLimit: eventLimit, truncated: truncated, entries: entries)
        let url = destination.url
        // Best effort and ordered off-main; process exit can leave the last queued write unfinished.
        writer.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch { }
        }
    }
}
#endif
