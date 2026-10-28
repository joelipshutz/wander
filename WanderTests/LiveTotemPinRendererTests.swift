import SwiftUI
import UIKit
import XCTest
@testable import Wander

@MainActor
final class LiveTotemPinRendererTests: XCTestCase {
    func testEveryProductionCategoryPictogramExistsWithoutEmojiRendering() {
        for category in MapCategoryPictogram.allCases {
            XCTAssertNotNil(UIImage(systemName: category.symbolName), category.rawValue)
            XCTAssertNotNil(UIImage(systemName: category.outlineSymbolName), category.rawValue)
        }
        XCTAssertEqual(MapCategoryPictogram.resolve(emoji: "☕️"), .coffee)
        XCTAssertEqual(MapCategoryPictogram.resolve(emoji: "☕"), .coffee)
        XCTAssertEqual(MapCategoryPictogram.resolve(emoji: "🍜"), .noodles)
        XCTAssertEqual(MapCategoryPictogram.resolve(emoji: "🥾"), .trail)
        XCTAssertEqual(MapCategoryPictogram.resolve(emoji: "unmapped"), .place)
    }

    func testViewedTreatmentPreservesPersonalAndSocialRailPixelsInBothAppearances() throws {
        let state = state(rails: [
            .init(ownership: .currentUser, status: .been),
            .init(ownership: .social, status: .wannaGo)
        ])
        for dark in [false, true] {
            let fresh = try pixels(render(state, dark: dark))
            let viewed = try pixels(render(state, viewed: true, dark: dark))
            for color: UInt32 in [0xF05A3C, 0x69B8D7] {
                XCTAssertGreaterThan(fresh.count(color), 12)
                XCTAssertEqual(fresh.count(color), viewed.count(color),
                               "Viewing must soften the body, never desaturate ownership/status.")
            }
            XCTAssertNotEqual(fresh.bytes, viewed.bytes, "The body still needs a visible viewed treatment.")
        }
    }

    func testFeaturedRailUsesApprovedGreenAndRemainsGreenWhenViewedOrCompact() throws {
        let state = state(rails: [.init(ownership: .featured, status: .been)])
        for compact in [false, true] {
            for viewed in [false, true] {
                let image = try pixels(render(state, viewed: viewed, compact: compact))
                XCTAssertGreaterThan(image.count(0x6FB985), 10)
                XCTAssertEqual(image.count(0x69B8D7), 0, "Featured must not look like social ownership.")
                XCTAssertEqual(image.count(0xF05A3C), 0, "Featured must not imply a personal save.")
            }
        }
    }

    func testSolidDottedAndMixedStatusesRemainVisuallyDifferent() throws {
        let been = state(rails: [.init(ownership: .currentUser, status: .been)])
        let wanna = state(rails: [.init(ownership: .currentUser, status: .wannaGo)])
        let mixed = state(rails: [.init(ownership: .currentUser, status: .been, secondaryStatus: .wannaGo)])
        let solid = try pixels(render(been))
        let dotted = try pixels(render(wanna))
        let split = try pixels(render(mixed))
        XCTAssertGreaterThan(solid.count(0xF05A3C), dotted.count(0xF05A3C))
        XCTAssertGreaterThan(split.count(0xF05A3C), 10)
        XCTAssertNotEqual(solid.bytes, dotted.bytes)
        XCTAssertNotEqual(split.bytes, solid.bytes)
        XCTAssertNotEqual(split.bytes, dotted.bytes)
    }

    func testListMarkerChangesOnlyTopCapAndDoesNotCreateOwnershipColor() throws {
        let without = try pixels(render(state(rails: [], list: false)))
        let with = try pixels(render(state(rails: [], list: true)))
        let changed = try XCTUnwrap(with.changedBounds(comparedTo: without))
        XCTAssertLessThan(changed.maxY, 28 * 3,
                          "List membership must add a cap mark without moving the pictogram or footing.")
        XCTAssertEqual(with.count(0xF05A3C), 0)
        XCTAssertEqual(with.count(0x69B8D7), 0)
        XCTAssertEqual(with.count(0x6FB985), 0)
    }

    func testDenseDotsKeepBothOwnershipColorsAndDoNotFadeAfterViewing() throws {
        let state = state(rails: [
            .init(ownership: .currentUser, status: .been),
            .init(ownership: .social, status: .been)
        ])
        let compact = try pixels(render(state, compact: true))
        let viewed = try pixels(render(state, viewed: true, compact: true))
        XCTAssertGreaterThan(compact.count(0xF05A3C), 10)
        XCTAssertGreaterThan(compact.count(0x69B8D7), 10)
        XCTAssertEqual(compact.bytes, viewed.bytes)
    }

    func testSelectionAlwaysExpandsAndUsesNeutralHaloForSocialPins() throws {
        let state = state(rails: [.init(ownership: .social, status: .been)], list: true)
        for dark in [false, true] {
            let selected = try pixels(render(state, selected: true, dark: dark))
            let selectedFromDensity = try pixels(render(state, selected: true, compact: true, dark: dark))
            let selectedAfterViewing = try pixels(render(state, selected: true, viewed: true, dark: dark))
            XCTAssertEqual(selected.bytes, selectedFromDensity.bytes)
            XCTAssertEqual(selected.bytes, selectedAfterViewing.bytes)
            XCTAssertEqual(selected.count(0xF05A3C), 0, "Selection must not imply a personal save.")
            XCTAssertGreaterThan(selected.count(0x69B8D7), 10)
        }
    }

    func testDenseAndExpandedPinsRetainFortyFourPointInteractionCanvas() throws {
        let state = state(rails: [.init(ownership: .social, status: .wannaGo)])
        for compact in [false, true] {
            for selected in [false, true] {
                let image = try render(state, selected: selected, compact: compact, padding: 0)
                XCTAssertEqual(image.size, CGSize(width: 44, height: 44))
            }
        }
    }

    private func state(rails: [MapPinOutline], list: Bool = false) -> LiveTotemState {
        LiveTotemState(rails: rails, hasListMembership: list,
                       hasSavedStatus: rails.contains { $0.ownership != .featured },
                       isFeatured: rails.contains { $0.ownership == .featured })
    }

    private func render(_ state: LiveTotemState, selected: Bool = false, viewed: Bool = false,
                        compact: Bool = false, dark: Bool = false,
                        padding: CGFloat = 8) throws -> UIImage {
        let renderer = ImageRenderer(content: LiveTotemPinView(
            state: state, categoryEmoji: "☕️", selected: selected, viewed: viewed, compact: compact
        )
            .environment(\.colorScheme, dark ? .dark : .light)
            .padding(padding))
        renderer.scale = 3
        return try XCTUnwrap(renderer.uiImage)
    }

    private func pixels(_ image: UIImage) throws -> Pixels {
        let image = try XCTUnwrap(image.cgImage)
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let succeeded = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                            | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(succeeded)
        return Pixels(width: width, height: height, bytes: bytes)
    }

    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func count(_ rgb: UInt32) -> Int {
            let red: Int = Int((rgb >> 16) & 0xFF)
            let green: Int = Int((rgb >> 8) & 0xFF)
            let blue: Int = Int(rgb & 0xFF)
            var matches = 0
            for index in stride(from: 0, to: bytes.count, by: 4) {
                guard bytes[index + 3] >= 250 else { continue }
                let redDifference: Int = abs(Int(bytes[index]) - red)
                let greenDifference: Int = abs(Int(bytes[index + 1]) - green)
                let blueDifference: Int = abs(Int(bytes[index + 2]) - blue)
                if redDifference <= 3, greenDifference <= 3, blueDifference <= 3 {
                    matches += 1
                }
            }
            return matches
        }

        func changedBounds(comparedTo other: Self) -> CGRect? {
            guard width == other.width, height == other.height else { return nil }
            var changed: CGRect?
            for y in 0..<height {
                for x in 0..<width {
                    let index = (y * width + x) * 4
                    guard (0..<4).contains(where: { bytes[index + $0] != other.bytes[index + $0] }) else { continue }
                    let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                    changed = changed.map { $0.union(pixel) } ?? pixel
                }
            }
            return changed
        }
    }
}
