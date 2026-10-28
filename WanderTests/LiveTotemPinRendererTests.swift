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

    func testCategoryPictogramsStayInsideTheCreamBodyWithClearFootingSeparation() throws {
        let categories = ["☕️", "🍽️", "🍜", "🍸", "🥐", "🌳", "🥾", "🏖️", "🏛️", "🏨", "🛍️", "🧘"]
        let state = state(rails: [.init(ownership: .currentUser, status: .been)])
        for selected in [false, true] {
            for dark in [false, true] {
                let reference = try pixels(render(state, selected: selected, dark: dark, emoji: "?"))
                let tileWidth: CGFloat = selected ? 32 : 29
                let tileHeight: CGFloat = selected ? 44 : 40
                // The image is a 44pt interaction canvas with 8pt test padding.
                // Category changes must stay at least 4pt inside the body and
                // above the separate 10pt status footing, for every silhouette.
                let safeBody = CGRect(x: 30 - tileWidth / 2 + 4, y: 30 - tileHeight / 2 + 4,
                                      width: tileWidth - 8, height: tileHeight - 10 - 8)
                for emoji in categories {
                    let image = try pixels(render(state, selected: selected, dark: dark, emoji: emoji))
                    let changed = try XCTUnwrap(image.changedBounds(comparedTo: reference), emoji)
                    XCTAssertGreaterThanOrEqual(changed.minX, safeBody.minX * 3, emoji)
                    XCTAssertLessThanOrEqual(changed.maxX, safeBody.maxX * 3, emoji)
                    XCTAssertGreaterThanOrEqual(changed.minY, safeBody.minY * 3, emoji)
                    XCTAssertLessThanOrEqual(changed.maxY, safeBody.maxY * 3,
                                             "\(emoji) must remain above the black footing.")
                }
            }
        }
    }

    func testSolidDottedAndMixedRailsShareSymmetricVisibleInsets() throws {
        let variants: [MapPinOutline] = [
            .init(ownership: .currentUser, status: .been),
            .init(ownership: .currentUser, status: .wannaGo),
            .init(ownership: .currentUser, status: .been, secondaryStatus: .wannaGo),
            .init(ownership: .currentUser, status: .wannaGo, secondaryStatus: .been)
        ]
        for selected in [false, true] {
            for dark in [false, true] {
                let solid = try pixels(render(state(rails: [variants[0]]), selected: selected, dark: dark))
                let reference = try XCTUnwrap(solid.colorBounds(0xF05A3C))
                let footingWidth: CGFloat = (selected ? 32 : 29) * 3
                let footingLeft = (CGFloat(solid.width) - footingWidth) / 2
                let footingRight = footingLeft + footingWidth
                for variant in variants {
                    let image = try pixels(render(state(rails: [variant]), selected: selected, dark: dark))
                    let rail = try XCTUnwrap(image.colorBounds(0xF05A3C))
                    XCTAssertEqual(rail.minX - footingLeft, footingRight - rail.maxX, accuracy: 1,
                                   "Visible rail endpoints must have equal left/right footing inset.")
                    XCTAssertEqual(rail.minX, reference.minX, accuracy: 1)
                    XCTAssertEqual(rail.maxX, reference.maxX, accuracy: 1,
                                   "Dots and mixed statuses must reach the same visible ends as Been.")
                }
                let twoRows = try pixels(render(state(rails: [
                    .init(ownership: .currentUser, status: .been, secondaryStatus: .wannaGo),
                    .init(ownership: .social, status: .wannaGo)
                ]), selected: selected, dark: dark))
                let own = try XCTUnwrap(twoRows.colorBounds(0xF05A3C))
                let social = try XCTUnwrap(twoRows.colorBounds(0x69B8D7))
                XCTAssertEqual(own.minX, social.minX, accuracy: 1)
                XCTAssertEqual(own.maxX, social.maxX, accuracy: 1)
            }
        }
    }

    func testListBadgeChangesOnlyTopRightCornerAcrossDensitySelectionAndAppearance() throws {
        for compact in [false, true] {
            for selected in [false, true] {
                for dark in [false, true] {
                    for viewed in [false, true] {
                        let without = try pixels(render(state(rails: [], list: false), selected: selected,
                                                        viewed: viewed, compact: compact, dark: dark))
                        let with = try pixels(render(state(rails: [], list: true), selected: selected,
                                                     viewed: viewed, compact: compact, dark: dark))
                        let changed = try XCTUnwrap(with.changedBounds(comparedTo: without))
                        let isDense = compact && !selected
                        let diameter: CGFloat = isDense ? 7.5 : 11
                        XCTAssertGreaterThan(changed.minX, (isDense ? 31 : 37) * 3,
                                             "The list badge belongs at the right corner, outside the pictogram.")
                        XCTAssertLessThan(changed.maxY, (isDense ? 29 : 25) * 3)
                        XCTAssertLessThanOrEqual(changed.width, diameter * 3 + 2)
                        XCTAssertLessThanOrEqual(changed.height, diameter * 3 + 2)
                        if !isDense {
                            let tileTop: CGFloat = selected ? 8 : 10
                            let tileRight: CGFloat = 30 + (selected ? 32 : 29) / 2
                            XCTAssertLessThan(changed.minY, tileTop * 3,
                                              "The circular badge must overlap the top edge.")
                            XCTAssertGreaterThan(changed.maxY, tileTop * 3)
                            XCTAssertLessThan(changed.minX, tileRight * 3)
                            XCTAssertGreaterThan(changed.maxX, tileRight * 3,
                                                 "The circular badge must overlap the right edge.")
                        }
                        XCTAssertEqual(with.count(0xF05A3C), 0)
                        XCTAssertEqual(with.count(0x69B8D7), 0)
                        XCTAssertEqual(with.count(0x6FB985), 0)
                    }
                }
            }
        }
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
        for list in [false, true] {
            let state = state(rails: [.init(ownership: .social, status: .wannaGo)], list: list)
            for compact in [false, true] {
                for selected in [false, true] {
                    let image = try render(state, selected: selected, compact: compact, padding: 0)
                    XCTAssertEqual(image.size, CGSize(width: 44, height: 44))
                }
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
                        emoji: String = "☕️", padding: CGFloat = 8) throws -> UIImage {
        let renderer = ImageRenderer(content: LiveTotemPinView(
            state: state, categoryEmoji: emoji, selected: selected, viewed: viewed, compact: compact
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

        func colorBounds(_ rgb: UInt32) -> CGRect? {
            let red = Int((rgb >> 16) & 0xFF)
            let green = Int((rgb >> 8) & 0xFF)
            let blue = Int(rgb & 0xFF)
            var bounds: CGRect?
            for y in 0..<height {
                for x in 0..<width {
                    let index = (y * width + x) * 4
                    guard bytes[index + 3] >= 250 else { continue }
                    let matchesRed = abs(Int(bytes[index]) - red) <= 3
                    let matchesGreen = abs(Int(bytes[index + 1]) - green) <= 3
                    let matchesBlue = abs(Int(bytes[index + 2]) - blue) <= 3
                    guard matchesRed, matchesGreen, matchesBlue else { continue }
                    let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                    bounds = bounds.map { $0.union(pixel) } ?? pixel
                }
            }
            return bounds
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
