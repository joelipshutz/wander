#if DEBUG && targetEnvironment(simulator)
import MapKit
import UIKit
import XCTest
@testable import Wander

@MainActor
final class MapDesignLabTests: XCTestCase {
    private let fixtureArguments = [
        "-WanderMapCapture", "-WanderAuthenticatedUITest", "-WanderUseStorefrontFixtures"
    ]

    func testDesignOptionsRequireAnExplicitAuthenticatedCaptureFixture() {
        for arguments in [
            [],
            ["-WanderMapCapture"],
            ["-WanderAuthenticatedUITest"],
            ["-WanderUseStorefrontFixtures"],
            ["-WanderMapCapture", "-WanderAuthenticatedUITest"],
            ["-WanderMapCapture", "-WanderUseDemoFixtures"],
            ["-WanderAuthenticatedUITest", "-WanderUseStorefrontFixtures"]
        ] {
            XCTAssertNil(MapKitLabStyle.resolve(arguments: arguments + ["-WanderMapDesign", "quiet"]))
            XCTAssertNil(MapPinLabStyle.resolve(arguments: arguments + ["-WanderPinDesign", "porcelain"]))
        }
    }

    func testMissingAndUnrecognizedOptionsLeaveTheProductionDesignActive() {
        for suffix in [[], ["-WanderMapDesign"], ["-WanderMapDesign", "unknown"]] {
            XCTAssertNil(MapKitLabStyle.resolve(arguments: fixtureArguments + suffix))
        }
        for suffix in [[], ["-WanderPinDesign"], ["-WanderPinDesign", "unknown"]] {
            XCTAssertNil(MapPinLabStyle.resolve(arguments: fixtureArguments + suffix))
        }
    }

    func testEveryOptionResolvesWithEitherSupportedFixtureSource() {
        for fixture in ["-WanderUseDemoFixtures", "-WanderUseStorefrontFixtures"] {
            let arguments = ["-WanderMapCapture", "-WanderAuthenticatedUITest", fixture]
            for style in MapKitLabStyle.allCases {
                XCTAssertEqual(MapKitLabStyle.resolve(
                    arguments: arguments + ["-WanderMapDesign", style.rawValue]
                ), style)
            }
            for style in MapPinLabStyle.allCases {
                XCTAssertEqual(MapPinLabStyle.resolve(
                    arguments: arguments + ["-WanderPinDesign", style.rawValue]
                ), style)
            }
        }
    }

    func testSecondPassCategorySymbolsExistInTheNativeSymbolCatalog() {
        for category in MapPinSecondPassCategory.allCases {
            XCTAssertNotNil(UIImage(systemName: category.symbolName),
                            "Missing filled category symbol for \(category)")
            XCTAssertNotNil(UIImage(systemName: category.outlineSymbolName),
                            "Missing outline category symbol for \(category)")
        }
    }

    func testSecondPassCategoryMappingNormalizesPresentationAndFallsBackSafely() {
        XCTAssertEqual(MapPinSecondPassCategory.resolve(emoji: "☕️"), .coffee)
        XCTAssertEqual(MapPinSecondPassCategory.resolve(emoji: "☕"), .coffee)
        XCTAssertEqual(MapPinSecondPassCategory.resolve(emoji: "🍽️"), .dining)
        XCTAssertEqual(MapPinSecondPassCategory.resolve(emoji: "🍽"), .dining)
        XCTAssertEqual(MapPinSecondPassCategory.resolve(emoji: "🍸"), .bar)
        XCTAssertEqual(MapPinSecondPassCategory.resolve(emoji: "🥾"), .trail)
        XCTAssertEqual(MapPinSecondPassCategory.resolve(emoji: "🌳"), .nature)
        for unknown in ["", "unrecognized category", "🧪"] {
            let category = MapPinSecondPassCategory.resolve(emoji: unknown)
            XCTAssertEqual(category, .place)
            XCTAssertEqual(category.symbolName, "location.fill")
            XCTAssertEqual(category.outlineSymbolName, "location")
        }
    }

    func testLetterpressInitialsCannotReintroduceEmojiFromPlaceTitles() {
        for (title, expected) in [
            ("Cedar Coffee", "C"),
            ("☕️ Café", "C"),
            ("ℹ️ Museum", "M"),
            ("🍕 Pizza Place", "P"),
            ("  — 7th Street", "7"),
            ("1️⃣ Pizza", "1"),
            ("éclair", "É"),
            ("🧪", "P"),
            ("…", "P"),
            ("", "P")
        ] {
            XCTAssertEqual(MapPinSecondPassGlyph.letterpressInitial(for: title), expected)
        }
    }

    func testLetterpressCacheDistinguishesInactivePlaceTitlesOnlyForItsOwnFamily() {
        let first = descriptor(state: .ownBeen, title: "Cedar Coffee")
        let second = descriptor(state: .ownBeen, title: "Maple Coffee")
        // Production inactive pins intentionally share images across place
        // titles. Letterpress initials introduce a new visual input.
        XCTAssertEqual(first.renderSignature, second.renderSignature)
        XCTAssertNotEqual(
            MapPinDesignLab.cacheSuffix(for: first, style: .letterpress),
            MapPinDesignLab.cacheSuffix(for: second, style: .letterpress)
        )
        for style in MapPinLabStyle.allCases where style != .letterpress {
            XCTAssertEqual(
                MapPinDesignLab.cacheSuffix(for: first, style: style),
                MapPinDesignLab.cacheSuffix(for: second, style: style),
                "Only title-dependent imagery needs separate inactive cache entries"
            )
        }
        XCTAssertEqual(MapPinDesignLab.cacheSuffix(for: first, style: nil), "")
    }

    func testLetterpressPlaceInitialsRenderBeforeSelection() throws {
        let first = try XCTUnwrap(MapPinDesignLab.render(
            for: descriptor(state: .ownBeen, title: "Cedar Coffee"),
            isDark: false, style: .letterpress
        ))
        let second = try XCTUnwrap(MapPinDesignLab.render(
            for: descriptor(state: .ownBeen, title: "Maple Coffee"),
            isDark: false, style: .letterpress
        ))
        XCTAssertNotEqual(try XCTUnwrap(first.pngData()), try XCTUnwrap(second.pngData()),
                          "Place initials must survive the inactive pin renderer")
    }

    func testBasemapOptionsPreserveNativePointsOfInterestAndDisableTraffic() throws {
        // An unknown category also remains included: the lab must not narrow
        // native POIs to the categories known when these tests were written.
        let categories: [MKPointOfInterestCategory] = [
            .airport, .bakery, .beach, .cafe, .hospital, .museum, .nationalPark,
            .nightlife, .park, .publicTransport, .restaurant, .store,
            MKPointOfInterestCategory(rawValue: "MapDesignLabFutureCategory")
        ]
        for style in MapKitLabStyle.allCases {
            let configuration = style.configuration()
            let filter: MKPointOfInterestFilter?
            if style == .hybrid {
                let hybrid = try XCTUnwrap(configuration as? MKHybridMapConfiguration)
                XCTAssertEqual(hybrid.elevationStyle, .flat)
                XCTAssertFalse(hybrid.showsTraffic)
                filter = hybrid.pointOfInterestFilter
            } else {
                let standard = try XCTUnwrap(configuration as? MKStandardMapConfiguration)
                switch style {
                case .quiet, .night:
                    XCTAssertEqual(standard.elevationStyle, .flat)
                    XCTAssertEqual(standard.emphasisStyle, .muted)
                case .atlas:
                    XCTAssertEqual(standard.elevationStyle, .flat)
                    XCTAssertEqual(standard.emphasisStyle, .default)
                case .dimension:
                    XCTAssertEqual(standard.elevationStyle, .realistic)
                    XCTAssertEqual(standard.emphasisStyle, .default)
                case .hybrid:
                    XCTFail("Hybrid must retain its native configuration type")
                }
                XCTAssertFalse(standard.showsTraffic)
                filter = standard.pointOfInterestFilter
            }
            let nativeFilter = try XCTUnwrap(filter)
            for category in categories {
                XCTAssertTrue(nativeFilter.includes(category), "\(style): \(category.rawValue)")
            }
        }
    }

    func testEveryPinDesignRendersTheSavedFeaturedAndSearchStateMatrix() throws {
        for style in MapPinLabStyle.allCases {
            for state in PinState.allCases {
                for selected in [false, true] {
                    for dark in [false, true] {
                        let descriptor = descriptor(state: state, selected: selected)
                        let image = try XCTUnwrap(MapPinDesignLab.render(
                            for: descriptor, isDark: dark, style: style
                        ), "\(style), \(state), selected=\(selected), dark=\(dark)")
                        XCTAssertGreaterThan(image.size.width, 0)
                        XCTAssertGreaterThan(image.size.height, 0)
                        let pixels = try rgbaPixels(image)
                        XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).contains {
                            pixels[$0] >= 250
                        }, "\(style), \(state) must render visible opaque content")
                    }
                }
            }
        }
    }

    func testPinDesignsKeepOwnershipAndWannaStatesVisuallyDistinct() throws {
        for style in MapPinLabStyle.allCases {
            for dark in [false, true] {
                func rendered(_ state: PinState) throws -> Data {
                    let image = try XCTUnwrap(MapPinDesignLab.render(
                        for: descriptor(state: state), isDark: dark, style: style
                    ))
                    return try XCTUnwrap(image.pngData())
                }
                let ownBeen = try rendered(.ownBeen)
                let ownWanna = try rendered(.ownWanna)
                let socialBeen = try rendered(.socialBeen)
                let socialMixed = try rendered(.socialMixed)
                let ownAndSocial = try rendered(.ownAndSocial)
                XCTAssertNotEqual(ownBeen, ownWanna, "\(style): Wanna needs a non-color status cue")
                XCTAssertNotEqual(ownBeen, socialBeen, "\(style): own and social ownership must remain distinct")
                XCTAssertNotEqual(socialBeen, socialMixed, "\(style): mixed social statuses must survive rendering")
                XCTAssertNotEqual(ownWanna, ownAndSocial, "\(style): adding social ownership must remain visible")
                XCTAssertNotEqual(socialMixed, ownAndSocial, "\(style): adding personal ownership must remain visible")
                XCTAssertNotEqual(socialBeen, try rendered(.search), "\(style): external search results must remain distinct")
            }
        }
    }

    func testFeaturedTotemRailIsGreenWithoutRecoloringPersonalOrSocialSaves() throws {
        for dark in [false, true] {
            for state in PinState.allCases {
                let image = try XCTUnwrap(MapPinDesignLab.render(
                    for: descriptor(state: state), isDark: dark, style: .totem
                ))
                let pixels = try rgbaPixels(image)
                let hasGreenRail = stride(from: 0, to: pixels.count, by: 4).contains { index in
                    let red = Int(pixels[index])
                    let green = Int(pixels[index + 1])
                    let blue = Int(pixels[index + 2])
                    return pixels[index + 3] > 250 && green > red + 35 && green > blue + 35
                }
                XCTAssertEqual(hasGreenRail, state == .featured,
                               "Only the Featured-only fallback should have a green rail: \(state)")
            }
        }
    }

    func testSelectedTitlesDoNotMoveThePinAwayFromItsCoordinate() throws {
        for style in MapPinLabStyle.allCases {
            for state in PinState.allCases {
                for selected in [false, true] {
                    let descriptor = descriptor(state: state, selected: selected)
                    let layout = MapPinCanvasMetrics.resolve(for: descriptor)
                    let image = try XCTUnwrap(MapPinDesignLab.render(
                        for: descriptor, isDark: false, style: style
                    ))
                    let offset = MapPinDesignLab.offset(for: descriptor)
                    let coordinateInImage = CGPoint(
                        x: image.size.width / 2 - offset.x,
                        y: image.size.height / 2 - offset.y
                    )
                    XCTAssertEqual(image.size, layout.size, "\(style), \(state)")
                    XCTAssertEqual(coordinateInImage.x, layout.pinCenter.x, accuracy: 0.5)
                    XCTAssertEqual(coordinateInImage.y, layout.pinCenter.y, accuracy: 0.5)
                    if selected {
                        XCTAssertLessThan(coordinateInImage.y, image.size.height / 2)
                    } else {
                        XCTAssertEqual(offset, .zero)
                        let diameter: CGFloat = state == .ownAndSocial || state == .search ? 62 : 58
                        XCTAssertEqual(image.size, CGSize(width: diameter, height: diameter),
                                       "Lab pins must preserve the native collision canvas")
                    }
                }
            }
        }
    }

    func testLabImagesMatchNativeAnnotationCollisionGeometryBeforeAndAfterSelection() throws {
        let view = NativeMapPinAnnotationView(annotation: nil, reuseIdentifier: nil)
        for state in PinState.allCases {
            for selected in [false, true] {
                let descriptor = descriptor(state: state, selected: selected)
                view.configure(descriptor: descriptor, isDark: false, reduceMotion: true)
                let nativeImage = try XCTUnwrap(view.image)
                for style in MapPinLabStyle.allCases {
                    let labImage = try XCTUnwrap(MapPinDesignLab.render(
                        for: descriptor, isDark: false, style: style
                    ))
                    XCTAssertEqual(labImage.size, nativeImage.size,
                                   "\(style), \(state), selected=\(selected) must preserve native collision bounds")
                    XCTAssertEqual(MapPinDesignLab.offset(for: descriptor), view.centerOffset,
                                   "\(style), \(state) must preserve the native coordinate anchor")
                }
            }
        }
    }

    func testAdaptiveDotsKeepTheirExistingNativeRenderer() {
        var dot = descriptor(state: .ownWanna)
        dot.detail = .dot
        var selectedDot = descriptor(state: .ownWanna, selected: true)
        selectedDot.detail = .dot
        for style in MapPinLabStyle.allCases {
            XCTAssertNil(MapPinDesignLab.render(for: dot, isDark: false, style: style))
            XCTAssertNotNil(MapPinDesignLab.render(for: selectedDot, isDark: false, style: style),
                            "Selection must still promote an adaptive dot to a category pin")
        }
    }

    private enum PinState: CaseIterable {
        case ownBeen, ownWanna, socialBeen, socialMixed, ownAndSocial, featured, search

        var outlines: [MapPinOutline] {
            switch self {
            case .ownBeen:
                [.init(ownership: .currentUser, status: .been)]
            case .ownWanna:
                [.init(ownership: .currentUser, status: .wannaGo)]
            case .socialBeen:
                [.init(ownership: .social, status: .been)]
            case .socialMixed:
                [.init(ownership: .social, status: .been, secondaryStatus: .wannaGo)]
            case .ownAndSocial:
                [.init(ownership: .currentUser, status: .wannaGo),
                 .init(ownership: .social, status: .been, secondaryStatus: .wannaGo)]
            case .featured:
                [.init(ownership: .featured, status: .been)]
            case .search:
                []
            }
        }
    }

    private func descriptor(
        state: PinState,
        selected: Bool = false,
        title: String = "Neighborhood Coffee"
    ) -> NativeMapAnnotationDescriptor {
        NativeMapAnnotationDescriptor(
            id: "lab-fixture", kind: state == .search ? .search("fixture") : .saved("fixture"),
            title: title, emoji: "☕️",
            coordinate: CLLocationCoordinate2D(latitude: 34.075, longitude: -118.285),
            outlines: state.outlines, isSearchResult: state == .search, isSelected: selected,
            opacity: 1, animatesEntrance: false, entranceDelay: 0,
            accessibilityLabel: MapPinAccessibility.label(
                outlines: state.outlines, category: "Coffee", placeName: title
            ),
            bounceRevision: 0
        )
    }

    private func rgbaPixels(_ image: UIImage) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return pixels
    }
}
#endif
