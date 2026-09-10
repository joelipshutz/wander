import XCTest
import UIKit
@testable import Wander

final class AstirLaunchLockupTests: XCTestCase {
    func testGlimmerRequiresAnActiveVisibleEnabledViewWithoutReducedMotion() {
        XCTAssertTrue(AstirLaunchGlimmer.shouldAnimate(
            reduceMotion: false, sceneIsActive: true, isVisible: true, isEnabled: true
        ))
        for disabledCondition in 0..<4 {
            XCTAssertFalse(AstirLaunchGlimmer.shouldAnimate(
                reduceMotion: disabledCondition == 0,
                sceneIsActive: disabledCondition != 1,
                isVisible: disabledCondition != 2,
                isEnabled: disabledCondition != 3
            ))
        }
    }

    func testGlimmerHasQuietEndpointsAndDoesNotMoveItsMask() {
        XCTAssertEqual(AstirLaunchGlimmer.frame(elapsed: 0).opacity, 0)
        XCTAssertEqual(AstirLaunchGlimmer.frame(elapsed: 0.6).opacity, 0)
        XCTAssertEqual(AstirLaunchGlimmer.frame(elapsed: 5).opacity, 0)
        XCTAssertEqual(
            AstirLaunchGlimmer.frame(elapsed: 2.7).center,
            AstirLaunchGlimmer.letterMinX + AstirLaunchGlimmer.letterWidth / 2,
            accuracy: 0.000_001
        )
        XCTAssertEqual(AstirLaunchGlimmer.frame(elapsed: 2.7).opacity, 0.22, accuracy: 0.000_001)
        XCTAssertEqual(AstirLaunchGlimmer.frame(elapsed: 5.4), AstirLaunchGlimmer.frame(elapsed: 0))
    }

    func testClockValuesRemainFiniteAndHighlightIsRestrained() {
        let values: [TimeInterval] = [-1, .nan, .infinity, -.infinity]
            + Array(stride(from: 0.0, through: 20.0, by: 0.05))
        for elapsed in values {
            let frame = AstirLaunchGlimmer.frame(elapsed: elapsed)
            XCTAssertTrue(frame.center.isFinite)
            XCTAssertTrue((0...1).contains(frame.center))
            XCTAssertTrue((0...0.22).contains(frame.opacity))
        }
    }

    func testWordmarkFitsCompactWidthsWithoutChangingItsAspectRatio() {
        for width: CGFloat in [0, 200, 320, 375, 393, 440, 1024] {
            let actual = AstirLaunchArtwork.width(availableWidth: width)
            XCTAssertGreaterThanOrEqual(actual, 0)
            XCTAssertLessThanOrEqual(actual, max(0, width - 32))
            XCTAssertLessThanOrEqual(actual, 460)
        }
        XCTAssertEqual(AstirLaunchArtwork.aspectRatio, 1600.0 / 764.0)
    }

    func testSTIRMaskMatchesApprovedLetterAlphaAndExcludesStatueAndBase() throws {
        let mark = try raster("AstirLaunchWordmark")
        let mask = try raster("AstirLaunchSTIRMask")
        XCTAssertEqual(mark.width, 1600)
        XCTAssertEqual(mark.height, 764)
        XCTAssertEqual(mask.width, mark.width)
        XCTAssertEqual(mask.height, mark.height)
        var covered = 0
        var mismatches = 0
        var outsideLetters = 0
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                let alpha = mask.bytes[(y * mask.width + x) * 4 + 3]
                // Bounds include only the unchanged STIR glyphs, never A/plinth.
                let isLetterRegion = (518...1382).contains(x) && (225...532).contains(y)
                if isLetterRegion {
                    if alpha != mark.bytes[(y * mask.width + x) * 4 + 3] { mismatches += 1 }
                } else if alpha > 0 {
                    outsideLetters += 1
                }
                if alpha > 0 { covered += 1 }
            }
        }
        XCTAssertEqual(mismatches, 0, "The native highlight mask must align with every approved letter edge/counter.")
        XCTAssertEqual(outsideLetters, 0, "The photograph and foundation must never be highlighted.")
        XCTAssertGreaterThan(covered, 50_000)
        XCTAssertLessThan(covered, 150_000)
    }

    private func raster(_ name: String) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Wander/Resources/Assets.xcassets/\(name).imageset/\(name).png")
        let image = try XCTUnwrap(UIImage(data: Data(contentsOf: url))?.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return (image.width, image.height, bytes)
    }
}
