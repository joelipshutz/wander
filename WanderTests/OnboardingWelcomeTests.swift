import XCTest
import UIKit
@testable import Wander

final class OnboardingWelcomeTests: XCTestCase {
    func testLeadFadesBeforeTheFinalFlapsStart() {
        let content = OnboardingTickerContent(words: ["people", "places"], finalLockup: "a local experiment")
        let start = OnboardingTickerFrame.wordSeconds + OnboardingTickerFrame.holdSeconds
        XCTAssertEqual(OnboardingTickerFrame.leadOpacity(elapsed: start - 0.18, content: content), 1, accuracy: 0.00001)
        XCTAssertEqual(OnboardingTickerFrame.leadOpacity(elapsed: start - 0.09, content: content), 0.5, accuracy: 0.00001)
        XCTAssertFalse(OnboardingTickerFrame.at(elapsed: start - 0.09, content: content).isTransitioning)
        XCTAssertEqual(OnboardingTickerFrame.leadOpacity(elapsed: start, content: content), 0)
        XCTAssertTrue(OnboardingTickerFrame.at(elapsed: start, content: content).isFinalTransition)
        XCTAssertEqual(OnboardingTickerFrame.leadOpacity(elapsed: 99, content: .init(words: ["people"])), 1)
    }

    func testEveryFlutterHasExactlyFourHapticTapsIncludingTheFinalPhrase() {
        let content = OnboardingWelcomeConfiguration.current.ticker!
        var cursor = OnboardingFlapHapticCursor()
        var taps = [Int]()
        for time in stride(from: 0.0, through: OnboardingTickerFrame.totalDuration(for: content), by: 1.0 / 60) {
            if let tap = cursor.advance(to: time, playing: true, content: content) { taps.append(tap) }
        }
        XCTAssertEqual(taps, Array(repeating: [0, 1, 2, 3], count: 4).flatMap { $0 })
    }

    func testHapticsDoNotCatchUpAfterPauseOrDroppedFrames() {
        let content = OnboardingTickerContent(words: ["people", "places"])
        let firstTap = OnboardingTickerFrame.holdSeconds + OnboardingTickerFrame.flipSeconds * 0.1
        var cursor = OnboardingFlapHapticCursor()
        XCTAssertNil(cursor.advance(to: firstTap - 0.01, playing: true, content: content))
        XCTAssertNil(cursor.advance(to: firstTap, playing: false, content: content))
        XCTAssertNil(cursor.advance(to: firstTap + 0.01, playing: true, content: content))
        XCTAssertNil(cursor.advance(to: firstTap + 0.8, playing: true, content: content))
        XCTAssertNil(cursor.advance(to: .infinity, playing: true, content: content))
        XCTAssertNil(cursor.advance(to: firstTap - 0.01, playing: true, content: content))
        XCTAssertEqual(cursor.advance(to: firstTap, playing: true, content: content), 0)
        XCTAssertNil(cursor.advance(to: firstTap, playing: true, content: content), "Repeated frames cannot duplicate a tap.")
    }

    @MainActor
    func testBlankRowsVisiblyTurnAndSettleBackToTheirOriginalFaces() throws {
        let rows = ["", "PEOPLE", ""]
        for finish in OnboardingFlapFinish.allCases {
            let view = OnboardingFlapSurfaceView(frame: CGRect(x: 0, y: 0, width: 354, height: 170))
            view.update(from: rows, to: rows, progress: 1, isDark: true, finish: finish, minimumColumns: 10, flips: 8)
            let held = try renderedBoard(view)
            view.update(from: rows, to: rows, progress: 0.41, isDark: true, finish: finish, minimumColumns: 10, flips: 8)
            XCTAssertNotEqual(try renderedBoard(view), held, "Identical words and blank rows still turn: \(finish)")
            view.update(from: rows, to: rows, progress: 1, isDark: true, finish: finish, minimumColumns: 10, flips: 8)
            XCTAssertEqual(try renderedBoard(view), held, "Every row settles back without stale halves: \(finish)")
        }
    }

    func testEveryOpeningCellIncludingBlanksRunsEightFlips() {
        let source = OnboardingBoardCopy.openingRows(word: "people").flatMap { OnboardingBoardCopy.centered($0, columns: 10) }
        let target = OnboardingBoardCopy.openingRows(word: "places").flatMap { OnboardingBoardCopy.centered($0, columns: 10) }
        XCTAssertEqual(source.count, 30)
        for index in source.indices {
            let column = index % 10
            let delay = Double(column) * OnboardingSplitFlapFrame.columnDelay
            var previous: OnboardingSplitFlapFrame?
            for flip in 0..<8 {
                let local = (Double(flip) + 0.5) / 8
                let frame = OnboardingSplitFlapFrame.at(progress: delay + (1 - delay) * local,
                    from: source[index], to: target[index], column: column)
                XCTAssertNotEqual(frame.from, frame.to, "Cell \(index), flip \(flip) must travel even if its final letter is unchanged.")
                XCTAssertEqual(frame.progress, 0.5, accuracy: 0.000001)
                if let previous { XCTAssertEqual(previous.to, frame.from) }
                previous = frame
            }
            XCTAssertEqual(previous?.to, target[index])
            let settled = OnboardingSplitFlapFrame.at(progress: 1, from: source[index], to: target[index], column: column)
            XCTAssertEqual(settled.from, target[index])
            XCTAssertEqual(settled.to, target[index])
        }
    }

    @MainActor
    func testRetainedFlapsSettleToTheSamePixelsAsAnInitiallyStaticBoard() throws {
        let from = OnboardingBoardCopy.openingRows(word: "community")
        let to = OnboardingBoardCopy.finalRows("a local experiment")
        for finish in OnboardingFlapFinish.allCases {
            let animated = OnboardingFlapSurfaceView(frame: CGRect(x: 0, y: 0, width: 354, height: 127))
            animated.update(from: from, to: to, progress: 0, isDark: true, finish: finish)
            animated.layoutIfNeeded()
            for progress in stride(from: 0.0, through: 1.0, by: 0.025) {
                animated.update(from: from, to: to, progress: progress, isDark: true, finish: finish)
            }
            animated.update(from: from, to: to, progress: 1, isDark: true, finish: finish)
            let held = OnboardingFlapSurfaceView(frame: animated.frame)
            held.update(from: to, to: to, progress: 1, isDark: true, finish: finish)
            XCTAssertEqual(try renderedBoard(animated), try renderedBoard(held), "No stale glyph half may survive the last flip: \(finish)")
        }
    }

    @MainActor
    func testRetainedFlapsRebuildTheirFacesWhenAppearanceOrFinishChanges() throws {
        let rows = OnboardingBoardCopy.openingRows(word: "people")
        let reused = OnboardingFlapSurfaceView(frame: CGRect(x: 0, y: 0, width: 354, height: 127))
        reused.update(from: rows, to: rows, progress: 1, isDark: false)
        let light = try renderedBoard(reused)
        reused.update(from: rows, to: rows, progress: 1, isDark: true, finish: .sculpted)
        let dark = try renderedBoard(reused)
        let fresh = OnboardingFlapSurfaceView(frame: reused.frame)
        fresh.update(from: rows, to: rows, progress: 1, isDark: true, finish: .sculpted)
        XCTAssertNotEqual(light, dark)
        XCTAssertEqual(dark, try renderedBoard(fresh), "A reused board must match a newly created dark/sculpted board.")
    }

    @MainActor
    func testRetainedFlapsResizeWithoutStaleGlyphScaleOrClippedRows() throws {
        let rows = OnboardingBoardCopy.benefitRows(.places)
        let resized = OnboardingFlapSurfaceView(frame: CGRect(x: 0, y: 0, width: 288, height: 104))
        resized.update(from: rows, to: rows, progress: 1, isDark: false, finish: .graphic)
        _ = try renderedBoard(resized)
        resized.frame = CGRect(x: 0, y: 0, width: 440, height: 158)
        let fresh = OnboardingFlapSurfaceView(frame: resized.frame)
        fresh.update(from: rows, to: rows, progress: 1, isDark: false, finish: .graphic)
        XCTAssertEqual(try renderedBoard(resized), try renderedBoard(fresh))
    }

    @MainActor
    private func renderedBoard(_ view: UIView) throws -> Data {
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: view.bounds.size).image { view.layer.render(in: $0.cgContext) }
        return try XCTUnwrap(image.pngData())
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

        let middle = OnboardingTickerFrame.at(elapsed: finalStart + OnboardingTickerFrame.flipSeconds / 2, content: content)
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

    func testSplitFlapUsesEightContinuousPhysicalFlipsAndSettlesOnExactTarget() {
        let starts = (0..<8).map { index in
            OnboardingSplitFlapFrame.at(progress: Double(index) / 8, from: "q", to: "z", column: 0)
        }
        XCTAssertEqual(starts[0].from, "q")
        XCTAssertEqual(starts[7].to, "z")
        XCTAssertTrue(starts.allSatisfy { $0.from != $0.to })
        XCTAssertTrue(starts.allSatisfy { abs($0.progress) < 0.000001 })
        for index in 1..<starts.count {
            XCTAssertEqual(starts[index - 1].to, starts[index].from, "Each flap begins where the previous physical flip ended.")
            XCTAssertTrue("ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains(starts[index].from))
            let almostFinished = OnboardingSplitFlapFrame.at(
                progress: Double(index) / 8 - 0.00001, from: "q", to: "z", column: 0
            )
            XCTAssertEqual(almostFinished.to, starts[index].from)
            XCTAssertGreaterThan(almostFinished.progress, 0.999)
        }
        let settled = OnboardingSplitFlapFrame.at(progress: 1, from: "q", to: "z", column: 0)
        XCTAssertEqual(settled.from, "z")
        XCTAssertEqual(settled.to, "z")
        XCTAssertEqual(settled.progress, 1)
    }

    func testOpeningBoardContainsOnlyTheWordAndReservesTheFinalRows() {
        let opening = OnboardingBoardCopy.openingRows(word: "loved ones")
        XCTAssertEqual(opening, ["", "LOVED ONES", ""])
        let final = OnboardingBoardCopy.finalRows("a local experiment")
        XCTAssertEqual(final, ["A", "LOCAL", "EXPERIMENT"])
        let places = OnboardingBoardCopy.benefitRows( .places)
        let people = OnboardingBoardCopy.benefitRows( .people)
        XCTAssertEqual(places, ["KEEP TRACK OF", "EVERYWHERE", "YOU’VE BEEN"])
        XCTAssertEqual(people, ["KEEP UP WITH", "THE PEOPLE", "YOU LOVE"])
        for rows in [opening, final, places, people] {
            XCTAssertEqual(rows.count, 3)
            for row in rows {
                let cells = OnboardingBoardCopy.centered(row)
                XCTAssertEqual(cells.count, 17)
                XCTAssertEqual(String(cells).trimmingCharacters(in: .whitespaces), row)
                let leading = cells.prefix(while: { $0 == " " }).count
                let trailing = cells.reversed().prefix(while: { $0 == " " }).count
                XCTAssertLessThanOrEqual(abs(leading - trailing), 1)
            }
        }
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

    func testSplitFlapClockBoundsInputAndReturnsUnchangedGlyphsAfterFlutter() {
        for progress in [-1.0, Double.nan, Double.infinity, -Double.infinity] {
            let frame = OnboardingSplitFlapFrame.at(progress: progress, from: "é", to: "a", column: 2)
            XCTAssertEqual(frame.from, "é")
            XCTAssertEqual(frame.progress, 0)
        }
        let late = OnboardingSplitFlapFrame.at(progress: .greatestFiniteMagnitude, from: "a", to: "é", column: 2)
        XCTAssertEqual(late.from, "é")
        XCTAssertEqual(late.to, "é")
        XCTAssertEqual(late.progress, 1)
        let blankStart = OnboardingSplitFlapFrame.at(progress: 0, from: " ", to: " ", column: 2)
        XCTAssertEqual(blankStart.from, " ")
        XCTAssertEqual(blankStart.progress, 0)
        let blankMoving = OnboardingSplitFlapFrame.at(progress: 0.3, from: " ", to: " ", column: 2)
        XCTAssertNotEqual(blankMoving.from, blankMoving.to)
        let blankEnd = OnboardingSplitFlapFrame.at(progress: 1, from: " ", to: " ", column: 2)
        XCTAssertEqual(blankEnd.from, " ")
        XCTAssertEqual(blankEnd.to, " ")
        XCTAssertEqual(blankEnd.progress, 1)
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
