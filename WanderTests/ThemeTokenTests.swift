import XCTest
import UIKit
@testable import Wander

final class ThemeTokenTests: XCTestCase {
    @MainActor
    func testEventsMarkMatchesListsInkHeightAndVerticalCenter() throws {
        let events = EventsTabSymbol.tabImage
        let lists = PlaceListSymbol.paperTabImage
        XCTAssertEqual(events.renderingMode, .alwaysTemplate)
        XCTAssertTrue(events === EventsTabSymbol.tabImage, "Tab switches reuse the rendered image.")
        XCTAssertEqual(events.size.height, lists.size.height)
        let eventsInk = try inkBounds(events)
        let listsInk = try inkBounds(lists)
        let pixel = 1 / events.scale
        XCTAssertEqual(eventsInk.height, listsInk.height, accuracy: pixel)
        XCTAssertEqual(eventsInk.midY, listsInk.midY, accuracy: pixel)
        XCTAssertEqual(eventsInk.midX, events.size.width / 2, accuracy: pixel)
        XCTAssertGreaterThan(eventsInk.width / eventsInk.height, 1.4, "Preserve the complete wide lighting rig.")
        XCTAssertGreaterThan(eventsInk.minY, 0)
        XCTAssertLessThan(eventsInk.maxY, events.size.height)
    }

    private func inkBounds(_ image: UIImage) throws -> CGRect {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var bounds = CGRect.null
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 127 {
                bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        XCTAssertFalse(bounds.isNull)
        return bounds.applying(CGAffineTransform(scaleX: 1 / image.scale, y: 1 / image.scale))
    }

    func testColorTokensMatchAstirEditorialLightValues() {
        let expected: [String: String] = [
            "color.canvas.warm": "#F2E9DB",
            "color.surface.bone": "#FBF6ED",
            "color.surface.raised": "#FFF9F0",
            "color.surface.sand": "#E8DED0",
            "color.text.ink": "#141714",
            "color.text.muted": "#655F57",
            "color.text.faint": "#8D877E",
            "color.text.onAction": "#141714",
            "color.border.hairline": "#8A8176",
            "color.border.strong": "#A99F91",
            "color.action.terracotta": "#F05A3C",
            "color.action.terracottaDark": "#C9422A",
            "color.action.terracottaTint": "#FBE0D9",
            "color.surface.sunTint": "#F4E8C9",
            "color.surface.skyTint": "#DBEAF1",
            "color.pin.you": "#F05A3C",
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

    func testCoreThemeTokensCarryAstirEditorialDarkValues() {
        XCTAssertEqual(WanderTheme.canvasWarm.darkHex, "#141714")
        XCTAssertEqual(WanderTheme.surfaceBone.darkHex, "#1B1F1B")
        XCTAssertEqual(WanderTheme.surfaceRaised.darkHex, "#222622")
        XCTAssertEqual(WanderTheme.surfaceSand.darkHex, "#101210")
        XCTAssertEqual(WanderTheme.textInk.darkHex, "#F2E9DB")
        XCTAssertEqual(WanderTheme.textMuted.darkHex, "#98958D")
        XCTAssertEqual(WanderTheme.borderHairline.darkHex, "#74786F")
        XCTAssertEqual(WanderTheme.terracotta.darkHex, "#F05A3C")
        XCTAssertEqual(WanderTheme.sunTint.darkHex, "#312B1A")
        XCTAssertEqual(WanderTheme.skyTint.darkHex, "#172A32")
    }

    @MainActor
    func testEspressoConfirmationMatchesProductionCheckInBlack() {
        XCTAssertNil(WanderPrimaryButtonTone.brand.glassTone)
        XCTAssertEqual(
            WanderPrimaryButtonTone.espressoConfirmation.glassTone,
            .deepBlackAction
        )
        XCTAssertNil(WanderPrimaryButtonTone.solidBlackConfirmation.glassTone)
    }

    func testDarkMapPaletteUsesAstirEditorialNightTokens() {
        XCTAssertEqual(WanderMapAppearance.nightSurface.hex, "#141714")
        XCTAssertEqual(WanderMapAppearance.nightRaised.hex, "#1B1F1B")
        XCTAssertEqual(WanderMapAppearance.nightText.hex, "#F2E9DB")
        XCTAssertEqual(WanderMapAppearance.nightMuted.hex, "#98958D")
        XCTAssertEqual(WanderMapAppearance.light.colorScheme, .light)
        XCTAssertEqual(WanderMapAppearance.dark.colorScheme, .dark)
        XCTAssertEqual(WanderMapAppearance.dark.neutralGlassTone, .darkOverlay)
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

    func testDarkRatingPaletteKeepsContrastAndLiquidBehaviorAcrossTheScale() {
        func luminance(_ red: Double, _ green: Double, _ blue: Double) -> Double {
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
        let surface = luminance(27.0 / 255, 31.0 / 255, 27.0 / 255)
        for score in PlaceRating.allowedScores {
            let dark = PlaceRatingLiquidState.resolve(score, isDarkMode: true)
            let light = PlaceRatingLiquidState.resolve(score)
            let contrast = (luminance(dark.red, dark.green, dark.blue) + 0.05) / (surface + 0.05)
            XCTAssertGreaterThanOrEqual(contrast, 4.5, "Solid color at rating \(score)")
            XCTAssertEqual(dark.score, light.score)
            XCTAssertEqual(dark.progress, light.progress)
            XCTAssertEqual(dark.level, light.level)
            XCTAssertEqual(dark.bubbleCount, light.bubbleCount)
        }
        let cool = PlaceRatingLiquidState.resolve(1, isDarkMode: true)
        let middle = PlaceRatingLiquidState.resolve(3, isDarkMode: true)
        let hot = PlaceRatingLiquidState.resolve(5, isDarkMode: true)
        XCTAssertGreaterThan(cool.blue, cool.green)
        XCTAssertGreaterThan(cool.green, cool.red)
        XCTAssertGreaterThan(middle.red, middle.green)
        XCTAssertGreaterThan(middle.green, middle.blue)
        XCTAssertGreaterThan(hot.red, hot.green)
        XCTAssertGreaterThan(hot.red, hot.blue)
    }
}
