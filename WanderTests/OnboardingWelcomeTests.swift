import XCTest
@testable import Wander

final class OnboardingWelcomeTests: XCTestCase {
    func testStaticOpeningIncludesFinalPhraseAndCompleteAccessibleCopy() throws {
        let content = try XCTUnwrap(OnboardingWelcomeConfiguration.resolved(environment: [:]).ticker)
        XCTAssertTrue(OnboardingTickerFrame.at(elapsed: content.staticElapsed, content: content).showsFinalLockup)
        for phrase in ["Connect with your", "community", "people", "places", "loved ones", "a local experiment"] {
            XCTAssertTrue(content.staticAccessibilityLabel.contains(phrase))
        }
    }

    func testLeadFadesBeforeTheFinalPhraseSlideStarts() {
        let content = OnboardingTickerContent(words: ["people", "places"], finalLockup: "a local experiment")
        let start = OnboardingTickerFrame.wordSeconds + OnboardingTickerFrame.holdSeconds
        XCTAssertEqual(OnboardingTickerFrame.leadOpacity(elapsed: start - 0.18, content: content), 1, accuracy: 0.00001)
        XCTAssertEqual(OnboardingTickerFrame.leadOpacity(elapsed: start - 0.09, content: content), 0.5, accuracy: 0.00001)
        XCTAssertFalse(OnboardingTickerFrame.at(elapsed: start - 0.09, content: content).isTransitioning)
        XCTAssertEqual(OnboardingTickerFrame.leadOpacity(elapsed: start, content: content), 0)
        XCTAssertTrue(OnboardingTickerFrame.at(elapsed: start, content: content).isFinalTransition)
        XCTAssertEqual(OnboardingTickerFrame.leadOpacity(elapsed: 99, content: .init(words: ["people"])), 1)
    }

    @MainActor
    func testWordAndSceneSlidesMoveTogetherAndRetainBothLabelsUntilLanding() {
        XCTAssertEqual(OnboardingCarouselTiming.slideSeconds, OnboardingSlideMotion.seconds)
        XCTAssertEqual(OnboardingTickerFrame.slideSeconds, OnboardingSlideMotion.seconds)
        for direction in [-1.0, 1.0] {
            for time in stride(from: 0.0, through: 1.0, by: 0.01) {
                let p = OnboardingSlideMotion.easedProgress(time)
                let offsets = OnboardingSlideMotion.offsets(progress: p, distance: 390, direction: direction)
                XCTAssertEqual(offsets.incoming - offsets.outgoing, direction * 390, accuracy: 0.00001)
                XCTAssertTrue((0...1).contains(p))
            }
        }
        XCTAssertEqual(OnboardingSlideMotion.easedProgress(0), 0)
        XCTAssertEqual(OnboardingSlideMotion.easedProgress(1), 1)
        XCTAssertEqual(OnboardingSlideMotion.easedProgress(.nan), 0)
        let values = (0...100).map { OnboardingSlideMotion.easedProgress(Double($0) / 100) }
        XCTAssertEqual(values, values.sorted(), "A word must never reverse or overshoot during a slide.")
    }

    func testInitialEntranceDoesNotConsumeTheFirstWordReadingHold() throws {
        let config = OnboardingWelcomeConfiguration.resolved(environment: [:])
        let content = try XCTUnwrap(config.ticker)
        XCTAssertEqual(config.seconds(for: .opening), OnboardingSlideMotion.seconds + OnboardingTickerFrame.totalDuration(for: content))
        XCTAssertEqual(config.seconds(for: .opening), 17.1, accuracy: 0.00001)
        XCTAssertFalse(OnboardingTickerFrame.at(elapsed: 0, content: content).isTransitioning)
        XCTAssertFalse(OnboardingTickerFrame.at(elapsed: OnboardingTickerFrame.holdSeconds - 0.01, content: content).isTransitioning)
    }

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

    func testTickerHoldsReadableWordThenSlidesBeforeAdvancingItsIndex() {
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
            elapsed: OnboardingTickerFrame.holdSeconds + OnboardingTickerFrame.slideSeconds / 2,
            content: content
        )
        XCTAssertEqual(halfway.wordIndex, 0, "The source word must remain available throughout its slide.")
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

        let middle = OnboardingTickerFrame.at(elapsed: finalStart + OnboardingTickerFrame.slideSeconds / 2, content: content)
        XCTAssertEqual(middle.wordIndex, 1)
        XCTAssertNil(middle.nextWordIndex, "The final phrase replaces the whole headline, not an ordinary ticker word.")
        XCTAssertTrue(middle.isTransitioning)
        XCTAssertTrue(middle.isFinalTransition)
        XCTAssertFalse(middle.showsFinalLockup, "Keep the outgoing label alive until the incoming phrase lands.")
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

    @MainActor
    func testEmbeddedSignupCanSwitchToLoginAndCloseWithoutLeakingVerification() async {
        let provider = PreviewAuthSessionProvider(state: .signedOut, canPresentNativeAuth: true)
        let auth = AuthSessionStore(provider: provider)
        auth.beginSignIn(mode: .signUp)
        let didSend = await auth.sendEmailCode(to: "example@example.com")
        XCTAssertTrue(didSend)
        XCTAssertEqual(auth.emailVerificationAddress, "example@example.com")
        XCTAssertFalse(AppEntryForegroundRefreshPolicy.canRefreshEntry(isPresentingNativeAuth: auth.isPresentingNativeAuth))

        auth.beginSignIn(mode: .signIn)
        XCTAssertTrue(auth.isPresentingNativeAuth)
        XCTAssertEqual(auth.activeNativeAuthMode, .signIn)
        XCTAssertNil(auth.emailVerificationAddress)
        XCTAssertTrue(provider.didResetPendingEmailVerification)

        auth.nativeAuthDidDismiss()
        XCTAssertFalse(auth.isPresentingNativeAuth)
        XCTAssertTrue(AppEntryForegroundRefreshPolicy.canRefreshEntry(isPresentingNativeAuth: auth.isPresentingNativeAuth))
        XCTAssertNil(auth.emailVerificationAddress)
        XCTAssertEqual(auth.state, .signedOut)
    }}
