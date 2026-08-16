import XCTest
@testable import Wander

final class ThemeTokenTests: XCTestCase {
    func testColorTokensMatchHandoffHexValues() {
        let expected: [String: String] = [
            "color.canvas.warm": "#F3DFCA",
            "color.surface.bone": "#FFF7EA",
            "color.surface.raised": "#FFFFFF",
            "color.surface.sand": "#EFE3D0",
            "color.text.ink": "#2C2118",
            "color.text.muted": "#7B6555",
            "color.text.faint": "#A8957F",
            "color.text.onAction": "#FFF7EA",
            "color.border.hairline": "#DBC2AA",
            "color.border.strong": "#C9AC8F",
            "color.action.terracotta": "#D46F4D",
            "color.action.terracottaDark": "#A94F35",
            "color.action.terracottaTint": "#F6E0D2",
            "color.surface.sunTint": "#F4E8C9",
            "color.surface.skyTint": "#DBEAF1",
            "color.pin.you": "#D46F4D",
            "color.pin.social": "#69B8D7",
            "color.category.moss": "#6F8F5F",
            "color.category.sun": "#E3B64B",
            "color.category.sage": "#A0B98A",
            "color.state.success": "#3F8F64",
            "color.state.warning": "#B98528",
            "color.state.error": "#B84A3A",
            "color.state.info": "#4F8EAD",
            "color.avatar.james": "#D4623F",
            "color.avatar.ryan": "#6F8F5F",
            "color.avatar.andrew": "#E3B64B",
            "color.avatar.sofia": "#69B8D7"
        ]

        let actual = Dictionary(uniqueKeysWithValues: WanderTheme.allColorTokens.map { ($0.name, $0.hex) })
        XCTAssertEqual(actual, expected)
    }

    func testEspressoConfirmationMatchesProductionCheckInBlack() {
        XCTAssertNil(WanderPrimaryButtonTone.brand.glassTone)
        XCTAssertEqual(
            WanderPrimaryButtonTone.espressoConfirmation.glassTone,
            .deepBlackAction
        )
    }
}

final class PlaceRatingReactionTests: XCTestCase {
    func testReactionLabelsCoverEveryHalfPointWithoutChangingWholeNumberCopy() {
        let expected: [(Double, String)] = [
            (1, "oof"),
            (1.5, "rough"),
            (2, "meh"),
            (2.5, "ehhh"),
            (3, "mid"),
            (3.5, "okayyy"),
            (4, "yeah"),
            (4.5, "oh baby"),
            (5, "wow")
        ]

        XCTAssertEqual(
            expected.map { PlaceRatingReaction.resolve($0.0).label },
            expected.map(\.1)
        )
    }

    func testReactionResolutionNormalizesAndClampsScores() {
        XCTAssertEqual(PlaceRatingReaction.resolve(0.5), PlaceRatingReaction(score: 1, label: "oof"))
        XCTAssertEqual(PlaceRatingReaction.resolve(4.74), PlaceRatingReaction(score: 4.5, label: "oh baby"))
        XCTAssertEqual(PlaceRatingReaction.resolve(5.5), PlaceRatingReaction(score: 5, label: "wow"))
    }

    func testReactionAccessibilityValueIncludesScoreAndCopy() {
        XCTAssertEqual(
            PlaceRatingReaction.resolve(4.5).accessibilityValue,
            "4.5 out of 5, oh baby"
        )
    }

    func testOnlyOneAndFiveAreDramaticExtremes() {
        XCTAssertTrue(PlaceRatingReaction.resolve(1).isMinimum)
        XCTAssertTrue(PlaceRatingReaction.resolve(5).isMaximum)
        XCTAssertFalse(PlaceRatingReaction.resolve(1.5).isExtreme)
        XCTAssertFalse(PlaceRatingReaction.resolve(4.5).isExtreme)
    }

    func testLiquidLevelAndBoilIntensityRiseWithTheRating() {
        let cool = PlaceRatingLiquidState.resolve(1)
        let middle = PlaceRatingLiquidState.resolve(3)
        let hot = PlaceRatingLiquidState.resolve(5)

        XCTAssertEqual(cool.level, 0.14, accuracy: 0.001)
        XCTAssertEqual(middle.level, 0.50, accuracy: 0.001)
        XCTAssertEqual(hot.level, 0.86, accuracy: 0.001)
        XCTAssertEqual(cool.bubbleCount, 3)
        XCTAssertEqual(middle.bubbleCount, 8)
        XCTAssertEqual(hot.bubbleCount, 12)
    }

    func testLiquidToneMovesFromBlueThroughAmberToDarkRed() {
        let cool = PlaceRatingLiquidState.resolve(1)
        let middle = PlaceRatingLiquidState.resolve(3)
        let hot = PlaceRatingLiquidState.resolve(5)

        XCTAssertGreaterThan(cool.blue, cool.red)
        XCTAssertGreaterThan(middle.red, middle.blue)
        XCTAssertGreaterThan(middle.green, middle.blue)
        XCTAssertGreaterThan(hot.red, hot.green)
        XCTAssertLessThan(hot.green, 0.1)
        XCTAssertLessThan(hot.blue, 0.1)
    }

    func testLiquidVisualStateInterpolatesBetweenHalfPointRatings() {
        let lowerStep = PlaceRatingLiquidState.resolve(3)
        let liveDrag = PlaceRatingLiquidState.resolve(3.25)
        let upperStep = PlaceRatingLiquidState.resolve(3.5)

        XCTAssertEqual(liveDrag.score, 3.25, accuracy: 0.001)
        XCTAssertGreaterThan(liveDrag.progress, lowerStep.progress)
        XCTAssertLessThan(liveDrag.progress, upperStep.progress)
        XCTAssertGreaterThan(liveDrag.level, lowerStep.level)
        XCTAssertLessThan(liveDrag.level, upperStep.level)
    }
}
