import Foundation

/// An empty word list deliberately omits the opening for explicit preview and
/// test configurations. The current production configuration supplies the copy.
struct OnboardingTickerContent: Equatable {
    let stableText: String
    let words: [String]
    let description: String?
    let finalLockup: String?

    init(
        stableText: String = "Connect with your",
        words: [String],
        description: String? = nil,
        finalLockup: String? = nil
    ) {
        self.stableText = stableText
        self.words = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.description = description.flatMap(Self.nonempty)
        self.finalLockup = finalLockup.flatMap(Self.nonempty)
    }

    /// One complete reading when automatic motion is disabled.
    var staticAccessibilityLabel: String {
        ["\(stableText) \(words.joined(separator: ", ")).", finalLockup]
            .compactMap { $0 }.joined(separator: " ")
    }

    var staticElapsed: Double { OnboardingTickerFrame.totalDuration(for: self) }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum OnboardingWelcomeStep: String, Equatable, Identifiable {
    case opening, places, people
    var id: String { rawValue }
}

struct OnboardingWelcomeConfiguration: Equatable {
    var ticker: OnboardingTickerContent? = nil
    var descriptionIsDelayed = false
    var autoAdvanceSeconds = 7.0
    var startsAt: OnboardingWelcomeStep? = nil
    var pausesAutomatically = false
    var visualTreatment: OnboardingVisualTreatment = .approved

    var steps: [OnboardingWelcomeStep] {
        let hasOpening = ticker.map { !$0.words.isEmpty } ?? false
        return (hasOpening ? [.opening] : []) + [.places, .people]
    }

    func next(after step: OnboardingWelcomeStep) -> OnboardingWelcomeStep? {
        guard let index = steps.firstIndex(of: step), steps.indices.contains(index + 1)
        else { return nil }
        return steps[index + 1]
    }

    func seconds(for step: OnboardingWelcomeStep) -> Double {
        if step == .opening, let ticker {
            return OnboardingSlideMotion.seconds + OnboardingTickerFrame.totalDuration(for: ticker)
        }
        return autoAdvanceSeconds.isFinite ? min(600, max(0.5, autoAdvanceSeconds)) : 7
    }

    static var current: Self {
        resolved(environment: ProcessInfo.processInfo.environment)
    }

    static func resolved(environment: [String: String]) -> Self {
        // Approved opening copy and finite three-scene sequence.
        var configuration = Self(
            ticker: OnboardingTickerContent(
                words: ["community", "people", "places", "loved ones"],
                description: "Keep track of everywhere you’ve been. Keep up with the people you love.",
                finalLockup: "a local experiment"
            ),
            descriptionIsDelayed: true
        )
        configuration.visualTreatment = .resolved(environment: environment)
        #if DEBUG
        if let raw = environment["WANDER_ONBOARDING_AUTO_ADVANCE_SECONDS"],
           let seconds = Double(raw), seconds.isFinite, seconds > 0 {
            configuration.autoAdvanceSeconds = seconds
        }
        if let raw = environment["WANDER_ONBOARDING_TICKER_WORDS"],
           let data = raw.data(using: .utf8),
           let words = try? JSONDecoder().decode([String].self, from: data), !words.isEmpty {
            configuration.ticker = OnboardingTickerContent(
                words: words,
                description: configuration.ticker?.description,
                finalLockup: configuration.ticker?.finalLockup
            )
        }
        if let ticker = configuration.ticker {
            configuration.ticker = OnboardingTickerContent(
                stableText: ticker.stableText,
                words: ticker.words,
                description: environment["WANDER_ONBOARDING_TICKER_DESCRIPTION"] ?? ticker.description,
                finalLockup: environment["WANDER_ONBOARDING_TICKER_FINAL"] ?? ticker.finalLockup
            )
        }
        if let delayed = environment["WANDER_ONBOARDING_DELAY_DESCRIPTION"] {
            configuration.descriptionIsDelayed = delayed == "1"
        }
        configuration.pausesAutomatically = environment["WANDER_ONBOARDING_PAUSED"] == "1"
        configuration.startsAt = environment["WANDER_ONBOARDING_START_STEP"]
            .flatMap(OnboardingWelcomeStep.init(rawValue:))
        #endif
        return configuration
    }
}

/// Shared slide score for words, phrases and complete scenes. Timeline-driven
/// text uses the same cubic curve as SwiftUI's scene animation.
enum OnboardingSlideMotion {
    static let seconds = 1.5
    static let x1 = 0.38
    static let x2 = 0.24

    static func easedProgress(_ progress: Double) -> Double {
        let progress = progress.isFinite ? min(1, max(0, progress)) : 0
        if progress == 0 || progress == 1 { return progress }
        // Solve the Bezier time axis before evaluating its distance axis.
        var low = 0.0, high = 1.0
        for _ in 0..<22 {
            let t = (low + high) / 2, remaining = 1 - t
            let x = 3 * remaining * remaining * t * x1 + 3 * remaining * t * t * x2 + t * t * t
            if x < progress { low = t } else { high = t }
        }
        let t = (low + high) / 2
        return 3 * (1 - t) * t * t + t * t * t
    }

    static func offsets(progress: Double, distance: Double, direction: Double = 1) -> (outgoing: Double, incoming: Double) {
        (-direction * distance * progress, direction * distance * (1 - progress))
    }
}

/// A held word followed by a whole-word slide. The initial entrance is separate
/// so COMMUNITY receives its full reading hold after it lands.
struct OnboardingTickerFrame: Equatable {
    static let holdSeconds = 1.8
    static let slideSeconds = OnboardingSlideMotion.seconds
    static let wordSeconds = holdSeconds + slideSeconds
    static let finalHoldSeconds = 2.4
    static let leadFadeSeconds = 0.18
    static let descriptionArrivalSeconds = 3.6

    static func leadOpacity(elapsed: Double, content: OnboardingTickerContent) -> Double {
        guard content.finalLockup != nil, !content.words.isEmpty else { return 1 }
        let end = Double(content.words.count - 1) * wordSeconds + holdSeconds
        let elapsed = elapsed.isFinite ? max(0, elapsed) : 0
        return min(1, max(0, (end - elapsed) / leadFadeSeconds))
    }

    let wordIndex: Int
    let nextWordIndex: Int?
    let transitionProgress: Double
    let isTransitioning: Bool
    let isFinalTransition: Bool
    let showsFinalLockup: Bool

    static func totalDuration(for content: OnboardingTickerContent) -> Double {
        guard !content.words.isEmpty else { return 0 }
        if content.finalLockup != nil {
            return Double(content.words.count) * wordSeconds + finalHoldSeconds
        }
        // A sequence without a final phrase holds its last word and stops;
        // there is no phantom slide out of that word.
        return Double(content.words.count - 1) * wordSeconds + holdSeconds
    }

    static func at(elapsed: Double, content: OnboardingTickerContent) -> Self {
        guard !content.words.isEmpty else { return held(wordIndex: 0) }
        let elapsed = elapsed.isFinite ? max(0, elapsed) : 0
        let lastIndex = content.words.count - 1
        let wordsDuration = Double(content.words.count) * wordSeconds
        // Bound before converting the clock to Int, including very large input.
        if elapsed >= wordsDuration {
            guard content.finalLockup != nil else { return held(wordIndex: lastIndex) }
            return Self(
                wordIndex: lastIndex, nextWordIndex: nil,
                transitionProgress: 1, isTransitioning: false,
                isFinalTransition: false, showsFinalLockup: true
            )
        }
        let index = min(lastIndex, Int(elapsed / wordSeconds))
        let slideStart = Double(index) * wordSeconds + holdSeconds
        guard elapsed >= slideStart else { return held(wordIndex: index) }
        let isFinal = index == lastIndex
        guard !isFinal || content.finalLockup != nil else { return held(wordIndex: index) }
        return Self(
            wordIndex: index,
            nextWordIndex: isFinal ? nil : index + 1,
            transitionProgress: min(1, max(0, (elapsed - slideStart) / slideSeconds)),
            isTransitioning: true,
            isFinalTransition: isFinal,
            showsFinalLockup: false
        )
    }

    private static func held(wordIndex: Int) -> Self {
        Self(
            wordIndex: wordIndex, nextWordIndex: nil,
            transitionProgress: 0, isTransitioning: false,
            isFinalTransition: false, showsFinalLockup: false
        )
    }
}

/// Approved line breaks shared by the opening and native benefits.
enum OnboardingWelcomeCopy {
    static func finalRows(_ phrase: String) -> [String] {
        let words = phrase.uppercased().split(separator: " ").map(String.init)
        return [words.first ?? "", words.dropFirst().first ?? "", words.dropFirst(2).joined(separator: " ")]
    }
    static func benefitRows(_ step: OnboardingWelcomeStep) -> [String] {
        step == .people ? ["KEEP UP WITH", "THE PEOPLE", "YOU LOVE"] : ["KEEP TRACK OF", "EVERYWHERE", "YOU’VE BEEN"]
    }
}
