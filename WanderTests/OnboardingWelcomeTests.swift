import XCTest
@testable import Wander

final class OnboardingWelcomeTests: XCTestCase {
    func testExplicitEmptyConfigurationOmitsTickerAndEndsAfterNativeBenefits() {
        let configuration = OnboardingWelcomeConfiguration()
        XCTAssertEqual(configuration.steps, [.places, .people])
        XCTAssertEqual(configuration.next(after: .places), .people)
        XCTAssertNil(configuration.next(after: .people), "The final scene enters auth instead of looping.")
        XCTAssertNil(configuration.next(after: .opening))
    }

    func testCurrentDefaultsStartWithConfirmedOpeningThenNativeBenefits() throws {
        let configuration = OnboardingWelcomeConfiguration.resolved(environment: [:])
        let ticker = try XCTUnwrap(configuration.ticker)
        XCTAssertEqual(ticker.stableText, "Connect with your")
        XCTAssertEqual(ticker.words, ["community", "people", "places", "loved ones"])
        XCTAssertEqual(ticker.description, "Keep track of everywhere you’ve been. Keep up with the people you love.")
        XCTAssertEqual(ticker.finalLockup, "a local experiment")
        XCTAssertTrue(configuration.descriptionIsDelayed)
        XCTAssertEqual(configuration.steps, [.opening, .places, .people])
        XCTAssertEqual(configuration.next(after: .opening), .places)
        XCTAssertEqual(configuration.next(after: .places), .people)
        XCTAssertNil(configuration.next(after: .people))
        let finalPhraseBegins = Double(ticker.words.count) * OnboardingTickerFrame.wordSeconds
        XCTAssertTrue(OnboardingTickerFrame.at(elapsed: finalPhraseBegins, content: ticker).showsFinalLockup)
        XCTAssertGreaterThan(configuration.seconds(for: .opening), finalPhraseBegins)
    }

    #if DEBUG
    func testSupportingLineCanBeReviewedWithoutReplacingConfirmedWords() {
        let configuration = OnboardingWelcomeConfiguration.resolved(environment: [
            "WANDER_ONBOARDING_TICKER_DESCRIPTION": "An alternative supporting line.",
            "WANDER_ONBOARDING_DELAY_DESCRIPTION": "0"
        ])
        XCTAssertEqual(configuration.ticker?.description, "An alternative supporting line.")
        XCTAssertEqual(configuration.ticker?.words, ["community", "people", "places", "loved ones"])
        XCTAssertEqual(configuration.ticker?.finalLockup, "a local experiment")
        XCTAssertFalse(configuration.descriptionIsDelayed)
    }

    func testMalformedDebugWordOverridePreservesConfirmedOpening() {
        let configuration = OnboardingWelcomeConfiguration.resolved(environment: [
            "WANDER_ONBOARDING_TICKER_WORDS": "not a JSON list"
        ])
        XCTAssertEqual(configuration.ticker?.words, ["community", "people", "places", "loved ones"])
        XCTAssertEqual(configuration.steps.first, .opening)
    }
    #endif

    func testBlankTickerCopyCannotExposeAnEmptyOpening() {
        var configuration = OnboardingWelcomeConfiguration()
        configuration.ticker = OnboardingTickerContent(words: [" ", "\n", ""])
        XCTAssertEqual(configuration.steps, [.places, .people])
    }

    func testSuppliedWordsPrependOpeningWithoutChangingBenefitOrder() {
        var configuration = OnboardingWelcomeConfiguration()
        configuration.ticker = OnboardingTickerContent(words: [" first ", "", "second"])
        XCTAssertEqual(configuration.ticker?.words, ["first", "second"])
        XCTAssertEqual(configuration.steps, [.opening, .places, .people])
        XCTAssertEqual(configuration.next(after: .opening), .places)
    }

    func testReadingIntervalRejectsNonfiniteAndBoundsCaptureOverrides() {
        var configuration = OnboardingWelcomeConfiguration()
        XCTAssertEqual(configuration.seconds(for: .places), 7)
        configuration.autoAdvanceSeconds = .infinity
        XCTAssertEqual(configuration.seconds(for: .people), 7)
        configuration.autoAdvanceSeconds = -.infinity
        XCTAssertEqual(configuration.seconds(for: .people), 7)
        configuration.autoAdvanceSeconds = -1
        XCTAssertEqual(configuration.seconds(for: .people), 0.5)
        configuration.autoAdvanceSeconds = 900
        XCTAssertEqual(configuration.seconds(for: .people), 600)
    }

    func testTickerHoldsReadableWordThenFlipsBeforeAdvancingItsIndex() {
        let content = OnboardingTickerContent(words: ["first", "second"])
        let held = OnboardingTickerFrame.at(elapsed: 1, content: content)
        XCTAssertEqual(held.wordIndex, 0)
        XCTAssertNil(held.nextWordIndex)
        XCTAssertFalse(held.isTransitioning)

        let start = OnboardingTickerFrame.at(elapsed: OnboardingTickerFrame.holdSeconds, content: content)
        XCTAssertEqual(start.wordIndex, 0)
        XCTAssertEqual(start.nextWordIndex, 1)
        XCTAssertTrue(start.isTransitioning)
        XCTAssertEqual(start.transitionProgress, 0, accuracy: 0.000001)
        let halfway = OnboardingTickerFrame.at(
            elapsed: OnboardingTickerFrame.holdSeconds + OnboardingTickerFrame.flipSeconds / 2,
            content: content
        )
        XCTAssertEqual(halfway.wordIndex, 0, "The source word must remain available throughout its flips.")
        XCTAssertEqual(halfway.nextWordIndex, 1)
        XCTAssertEqual(halfway.transitionProgress, 0.5, accuracy: 0.000001)
        XCTAssertFalse(halfway.isFinalTransition)
        XCTAssertFalse(halfway.showsFinalLockup)

        let nextHold = OnboardingTickerFrame.at(elapsed: OnboardingTickerFrame.wordSeconds, content: content)
        XCTAssertEqual(nextHold.wordIndex, 1)
        XCTAssertNil(nextHold.nextWordIndex)
        XCTAssertFalse(nextHold.isTransitioning)
    }

    func testFinalHeadlineTransitionsOnlyAfterLastWordHoldAndThenGetsReadingTime() {
        let content = OnboardingTickerContent(words: ["first", "last"], finalLockup: "a local experiment")
        let finalStart = OnboardingTickerFrame.wordSeconds + OnboardingTickerFrame.holdSeconds
        let finalEnd = Double(content.words.count) * OnboardingTickerFrame.wordSeconds
        XCTAssertEqual(OnboardingTickerFrame.totalDuration(for: content), finalEnd + 2.4, accuracy: 0.000001)
        let before = OnboardingTickerFrame.at(elapsed: finalStart - 0.001, content: content)
        XCTAssertEqual(before.wordIndex, 1)
        XCTAssertFalse(before.isTransitioning)
        XCTAssertFalse(before.showsFinalLockup)

        let middle = OnboardingTickerFrame.at(elapsed: finalStart + 0.5, content: content)
        XCTAssertEqual(middle.wordIndex, 1)
        XCTAssertNil(middle.nextWordIndex, "The final phrase replaces the whole headline, not an ordinary ticker word.")
        XCTAssertTrue(middle.isTransitioning)
        XCTAssertTrue(middle.isFinalTransition)
        XCTAssertFalse(middle.showsFinalLockup, "Keep the transition view alive until every flap reaches its target.")
        XCTAssertEqual(middle.transitionProgress, 0.5, accuracy: 0.000001)

        for elapsed in [finalEnd, finalEnd + 1, finalEnd + 2.4] {
            let settled = OnboardingTickerFrame.at(elapsed: elapsed, content: content)
            XCTAssertTrue(settled.showsFinalLockup)
            XCTAssertFalse(settled.isTransitioning)
            XCTAssertFalse(settled.isFinalTransition)
            XCTAssertEqual(settled.transitionProgress, 1)
        }
    }

    func testNoFinalPhraseKeepsLastWordReadableWithoutFlippingToNothing() {
        let content = OnboardingTickerContent(words: ["first", "last"])
        XCTAssertEqual(
            OnboardingTickerFrame.totalDuration(for: content),
            OnboardingTickerFrame.wordSeconds + OnboardingTickerFrame.holdSeconds,
            accuracy: 0.000001
        )
        for elapsed in [OnboardingTickerFrame.wordSeconds, 4.5, 50] {
            let frame = OnboardingTickerFrame.at(elapsed: elapsed, content: content)
            XCTAssertEqual(frame.wordIndex, 1)
            XCTAssertNil(frame.nextWordIndex)
            XCTAssertFalse(frame.isTransitioning)
            XCTAssertFalse(frame.isFinalTransition)
            XCTAssertFalse(frame.showsFinalLockup)
        }
    }

    func testTickerClockHandlesInvalidVeryLargeAndEmptyInput() {
        let content = OnboardingTickerContent(words: ["first", "second"], finalLockup: "Final")
        let initial = OnboardingTickerFrame.at(elapsed: 0, content: content)
        for elapsed in [-1.0, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(OnboardingTickerFrame.at(elapsed: elapsed, content: content), initial)
        }
        let late = OnboardingTickerFrame.at(elapsed: .greatestFiniteMagnitude, content: content)
        XCTAssertEqual(late.wordIndex, 1)
        XCTAssertTrue(late.showsFinalLockup)
        XCTAssertFalse(late.isTransitioning)
        let empty = OnboardingTickerContent(words: [], finalLockup: "Final")
        XCTAssertEqual(OnboardingTickerFrame.totalDuration(for: empty), 0)
        let frame = OnboardingTickerFrame.at(elapsed: .greatestFiniteMagnitude, content: empty)
        XCTAssertEqual(frame.wordIndex, 0)
        XCTAssertNil(frame.nextWordIndex)
        XCTAssertFalse(frame.isTransitioning)
        XCTAssertFalse(frame.showsFinalLockup)
    }

    func testSplitFlapUsesFiveContinuousPhysicalFlipsAndSettlesOnExactTarget() {
        let starts = (0..<5).map { index in
            OnboardingSplitFlapFrame.at(progress: Double(index) / 5, from: "q", to: "z", column: 0)
        }
        XCTAssertEqual(starts[0].from, "q")
        XCTAssertEqual(starts[4].to, "z")
        XCTAssertTrue(starts.allSatisfy { $0.from != $0.to })
        XCTAssertTrue(starts.allSatisfy { abs($0.progress) < 0.000001 })
        for index in 1..<starts.count {
            XCTAssertEqual(starts[index - 1].to, starts[index].from, "Each flap begins where the previous physical flip ended.")
            XCTAssertTrue("abcdefghijklmnopqrstuvwxyz".contains(starts[index].from))
            let almostFinished = OnboardingSplitFlapFrame.at(
                progress: Double(index) / 5 - 0.00001, from: "q", to: "z", column: 0
            )
            XCTAssertEqual(almostFinished.to, starts[index].from)
            XCTAssertGreaterThan(almostFinished.progress, 0.999)
        }
        let settled = OnboardingSplitFlapFrame.at(progress: 1, from: "q", to: "z", column: 0)
        XCTAssertEqual(settled.from, "z")
        XCTAssertEqual(settled.to, "z")
        XCTAssertEqual(settled.progress, 1)
    }

    func testSplitFlapStaggersColumnsButEveryColumnSettlesAtTheSameDeadline() {
        let early = OnboardingSplitFlapFrame.at(progress: 0.05, from: "a", to: "b", column: 0)
        let later = OnboardingSplitFlapFrame.at(progress: 0.05, from: "a", to: "b", column: 8)
        XCTAssertGreaterThan(early.progress, 0)
        XCTAssertEqual(later.from, "a")
        XCTAssertEqual(later.progress, 0)
        for column in [0, 8, 20, Int.max] {
            let frame = OnboardingSplitFlapFrame.at(progress: 1, from: "a", to: "b", column: column)
            XCTAssertEqual(frame.from, "b")
            XCTAssertEqual(frame.to, "b")
            XCTAssertEqual(frame.progress, 1)
        }
        XCTAssertEqual(
            OnboardingSplitFlapFrame.at(progress: 0.3, from: "a", to: "b", column: Int.min),
            OnboardingSplitFlapFrame.at(progress: 0.3, from: "a", to: "b", column: 0)
        )
    }

    func testSplitFlapClockBoundsInputAndLeavesUnchangedGlyphsFixed() {
        for progress in [-1.0, Double.nan, Double.infinity, -Double.infinity] {
            let frame = OnboardingSplitFlapFrame.at(progress: progress, from: "é", to: "a", column: 2)
            XCTAssertEqual(frame.from, "é")
            XCTAssertEqual(frame.progress, 0)
        }
        let late = OnboardingSplitFlapFrame.at(progress: .greatestFiniteMagnitude, from: "a", to: "é", column: 2)
        XCTAssertEqual(late.from, "é")
        XCTAssertEqual(late.to, "é")
        XCTAssertEqual(late.progress, 1)
        for progress in [0.0, 0.3, 1] {
            let fixed = OnboardingSplitFlapFrame.at(progress: progress, from: " ", to: " ", column: 2)
            XCTAssertEqual(fixed.from, " ")
            XCTAssertEqual(fixed.to, " ")
            XCTAssertEqual(fixed.progress, 1)
        }
    }

    func testDifferentWordLengthsFlipSurplusLettersToBlanksAndCanClearWholeWord() {
        func settledLine(from: String, to: String) -> String {
            let source = Array(from)
            let target = Array(to)
            return String((0..<max(source.count, target.count)).map { column in
                let fromGlyph: Character = source.indices.contains(column) ? source[column] : " "
                let toGlyph: Character = target.indices.contains(column) ? target[column] : " "
                let start = OnboardingSplitFlapFrame.at(progress: 0, from: fromGlyph, to: toGlyph, column: column)
                XCTAssertEqual(start.from, fromGlyph)
                let end = OnboardingSplitFlapFrame.at(progress: 1, from: fromGlyph, to: toGlyph, column: column)
                XCTAssertEqual(end.from, end.to)
                return end.to
            })
        }
        XCTAssertEqual(settledLine(from: "community", to: "people"), "people   ")
        XCTAssertEqual(settledLine(from: "places", to: "loved ones"), "loved ones")
        XCTAssertEqual(settledLine(from: "loved ones", to: ""), String(repeating: " ", count: 10))
        XCTAssertEqual(settledLine(from: "", to: ""), "")
    }

    @MainActor
    func testEmbeddedSignupCanSwitchToLoginAndCloseWithoutLeakingVerification() async {
        let provider = PreviewAuthSessionProvider(state: .signedOut, canPresentNativeAuth: true)
        let auth = AuthSessionStore(provider: provider)
        auth.beginSignIn(mode: .signUp)
        let didSend = await auth.sendEmailCode(to: "example@example.com")
        XCTAssertTrue(didSend)
        XCTAssertEqual(auth.emailVerificationAddress, "example@example.com")

        auth.beginSignIn(mode: .signIn)
        XCTAssertTrue(auth.isPresentingNativeAuth)
        XCTAssertEqual(auth.activeNativeAuthMode, .signIn)
        XCTAssertNil(auth.emailVerificationAddress)
        XCTAssertTrue(provider.didResetPendingEmailVerification)

        auth.nativeAuthDidDismiss()
        XCTAssertFalse(auth.isPresentingNativeAuth)
        XCTAssertNil(auth.emailVerificationAddress)
        XCTAssertEqual(auth.state, .signedOut)
    }
}
