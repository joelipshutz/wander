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
            return OnboardingTickerFrame.totalDuration(for: ticker)
        }
        return autoAdvanceSeconds.isFinite ? min(600, max(0.5, autoAdvanceSeconds)) : 7
    }

    static var current: Self {
        resolved(environment: ProcessInfo.processInfo.environment)
    }

    static func resolved(environment: [String: String]) -> Self {
        // Confirmed by Joe on September 17. Supporting copy and its timing
        // remain review choices; the lead-in, words and final phrase are fixed.
        var configuration = Self(
            ticker: OnboardingTickerContent(
                words: ["community", "people", "places", "loved ones"],
                description: "Keep track of everywhere you’ve been. Keep up with the people you love.",
                finalLockup: "a local experiment"
            ),
            descriptionIsDelayed: true
        )
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

/// Each word is held before its letters rotate through physical split flaps.
/// The later slide to a different scene belongs to the surrounding composition.
struct OnboardingTickerFrame: Equatable {
    static let holdSeconds = 1.6
    static let flipSeconds = 1.0
    static let wordSeconds = holdSeconds + flipSeconds
    static let finalHoldSeconds = 2.4

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
        // there is no phantom flip out of that word.
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
        let local = elapsed - Double(index) * wordSeconds
        guard local >= holdSeconds else { return held(wordIndex: index) }
        let isFinal = index == lastIndex
        guard !isFinal || content.finalLockup != nil else { return held(wordIndex: index) }
        return Self(
            wordIndex: index,
            nextWordIndex: isFinal ? nil : index + 1,
            transitionProgress: min(1, max(0, (local - holdSeconds) / flipSeconds)),
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

/// One physical flap within a five-flip letter change. Intermediate letters are
/// deterministic so native rendering, scrubbing and tests follow the same path.
struct OnboardingSplitFlapFrame: Equatable {
    static let flipCount = 5
    static let columnDelay = 0.012
    static let maximumStaggeredColumn = 12

    let from: Character
    let to: Character
    let progress: Double

    static func at(progress: Double, from: Character, to: Character, column: Int) -> Self {
        guard from != to else { return Self(from: from, to: to, progress: 1) }
        let progress = progress.isFinite ? min(1, max(0, progress)) : 0
        if progress >= 1 { return Self(from: to, to: to, progress: 1) }

        let column = max(0, column)
        let delay = Double(min(maximumStaggeredColumn, column)) * columnDelay
        let local = min(1, max(0, (progress - delay) / (1 - delay)))
        let glyphs = cycle(from: from, to: to, column: column)
        let position = local * Double(flipCount)
        let flip = min(flipCount - 1, Int(position))
        return Self(
            from: glyphs[flip], to: glyphs[flip + 1],
            progress: min(1, max(0, position - Double(flip)))
        )
    }

    private static func cycle(from: Character, to: Character, column: Int) -> [Character] {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        let scalarSeed = (String(from) + String(to)).unicodeScalars.reduce(0) {
            ($0 + Int($1.value) % alphabet.count) % alphabet.count
        }
        var cursor = (scalarSeed + column % alphabet.count) % alphabet.count
        var glyphs = [from]
        for _ in 0..<(flipCount - 1) {
            // Every physical flip changes its glyph, including the final one.
            while alphabet[cursor] == glyphs.last || alphabet[cursor] == to {
                cursor = (cursor + 1) % alphabet.count
            }
            glyphs.append(alphabet[cursor])
            cursor = (cursor + 7) % alphabet.count
        }
        glyphs.append(to)
        return glyphs
    }
}
