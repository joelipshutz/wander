#if DEBUG
@testable import Wander
import XCTest
import UIKit

final class AstirBrandShellTests: XCTestCase {
    func testMapBackdropBlurPreservesSolidMapColorsWithoutTint() throws {
        for color in [[UInt8](arrayLiteral: 32, 51, 73), [235, 225, 203], [5, 110, 70], [255, 255, 255], [0, 0, 0]] {
            let input = try imageFromPixels { _, _ in color + [255] }
            let output = try XCTUnwrap(AstirMapGaussianBlur.render(input, inset: 20))
            let pixel = try centerPixel(output)
            for component in 0..<4 {
                XCTAssertEqual(Int(pixel[component]), Int((color + [255])[component]), accuracy: 2)
            }
        }
    }

    func testMapBackdropBlurSoftensDetailWithoutAddingTransparency() throws {
        let input = try imageFromPixels { x, _ in
            let value: UInt8 = x.isMultiple(of: 2) ? 0 : 255
            return [value, value, value, 255]
        }
        let output = try XCTUnwrap(AstirMapGaussianBlur.render(input, inset: 20))
        let pixel = try centerPixel(output)
        XCTAssertGreaterThan(pixel[0], 50)
        XCTAssertLessThan(pixel[0], 240)
        XCTAssertEqual(pixel[0], pixel[1])
        XCTAssertEqual(pixel[1], pixel[2])
        XCTAssertEqual(pixel[3], 255)
    }

    private func imageFromPixels(_ pixel: (Int, Int) -> [UInt8]) throws -> CGImage {
        var data = [UInt8]()
        for y in 0..<64 {
            for x in 0..<64 { data.append(contentsOf: pixel(x, y)) }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(data) as CFData))
        return try XCTUnwrap(CGImage(
            width: 64, height: 64, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 256,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private func centerPixel(_ image: CGImage) throws -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
        }
        return pixel
    }

    func testLaunchArgumentResolvesEveryPrototypePage() {
        for page in AstirBrandShellPage.allCases {
            XCTAssertEqual(
                AstirBrandShellPage.resolved(
                    from: ["Wander", "-AstirBrandShell", page.rawValue],
                    environment: [:]
                ),
                page
            )
        }
    }

    func testPrototypeContainsOnlyCurrentAppSurfaces() {
        XCTAssertEqual(AstirBrandShellPage.allCases, [.map, .feed, .lists, .add, .profile])
    }

    func testBareLaunchArgumentStartsAtMap() {
        XCTAssertEqual(
            AstirBrandShellPage.resolved(
                from: ["Wander", "-AstirBrandShell"],
                environment: [:]
            ),
            .map
        )
    }

    func testEnvironmentSupportsDeterministicSimulatorCapture() {
        XCTAssertEqual(
            AstirBrandShellPage.resolved(
                from: ["Wander"],
                environment: ["WANDER_ASTIR_BRAND_SHELL": "lists"]
            ),
            .lists
        )
    }

    func testPrototypeDoesNotActivateWithoutExplicitLaunchValue() {
        XCTAssertNil(
            AstirBrandShellPage.resolved(from: ["Wander"], environment: [:])
        )
    }

    func testUnknownPrototypePageFallsBackToMap() {
        XCTAssertEqual(
            AstirBrandShellPage.resolved(
                from: ["Wander", "-AstirBrandShell", "unknown"],
                environment: [:]
            ),
            .map
        )
    }

    func testAstirModesOnlyExposeAdaptiveEditorialSchemes() {
        XCTAssertEqual(AstirBrandMode.allCases, [.editorial, .editorialLight])
        XCTAssertTrue(AstirBrandMode.editorial.prefersDarkInterface)
        XCTAssertFalse(AstirBrandMode.editorialLight.prefersDarkInterface)
    }

    func testAstirModesShareTheEditorialPalette() {
        XCTAssertEqual(AstirTheme.ink.hex, "#141714")
        XCTAssertEqual(AstirTheme.paper.hex, "#F2E9DB")
        XCTAssertEqual(AstirTheme.signal.hex, "#F05A3C")
        XCTAssertEqual(AstirTheme.signalOnPaper.hex, "#B23620")
        XCTAssertEqual(AstirTheme.mutedOnPaper.hex, "#655F57")
        XCTAssertEqual(AstirTheme.lineOnPaper.hex, "#8A8176")
        XCTAssertEqual(AstirTheme.lineOnInk.hex, "#74786F")
    }

    func testPrototypeKeepsAstirSpellingAndCurrentNavigationContract() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/BrandExploration/AstirBrandShell.swift"
            )
        )

        XCTAssertTrue(source.contains("Text(\"ASTIR\")"))
        XCTAssertFalse(source.contains("Text(\"ASTER\")"))
        XCTAssertTrue(source.contains("case .map: \"Map\""))
        XCTAssertTrue(source.contains("case .feed: \"Feed\""))
        XCTAssertTrue(source.contains("case .lists: \"Lists\""))
        XCTAssertTrue(source.contains("case .profile: \"Profile\""))
        XCTAssertTrue(source.contains("title: \"I’m here now\""))
        XCTAssertTrue(source.contains("title: \"Paste a link\""))
        XCTAssertTrue(source.contains("title: \"Search manually\""))
        XCTAssertTrue(source.contains("title: \"Add from a photo\""))
        XCTAssertFalse(source.contains("Third Thursday"))
        XCTAssertFalse(source.contains("Join the table"))
        XCTAssertFalse(source.contains("You’re expected"))
        XCTAssertFalse(source.contains("The night, kept."))
    }
}
#endif
