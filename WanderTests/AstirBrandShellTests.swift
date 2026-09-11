#if DEBUG
@testable import Wander
import XCTest
import SwiftUI

final class AstirBrandShellTests: XCTestCase {
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

    @MainActor
    func testReducedTransparencyFilterLabelsRemainVisible() throws {
        // Exercise the shared surface with the same foreground and sizing as
        // the Map source chips. Compare rendered pixels, not accessibility text:
        // VoiceOver can still find a label that is invisible on its background.
        for mode in AstirBrandMode.allCases {
            for selected in [false, true] {
                for contrast in [ColorSchemeContrast.standard, .increased] {
                    func render(label: String) throws -> CGImage {
                        let renderer = ImageRenderer(content:
                            Text(label)
                                .font(AstirTypography.label)
                                .frame(width: 112, height: 44)
                                .foregroundStyle(selected ? mode.accentText : mode.primaryText)
                                .astirGlassSurface(cornerRadius: 18, selected: selected)
                                .environment(\.astirBrandMode, mode)
                                .environment(\.colorScheme, mode.prefersDarkInterface ? .dark : .light)
                                // SwiftUI exposes test overrides for these read-only settings.
                                .environment(\._colorSchemeContrast, contrast)
                                .environment(\._accessibilityReduceTransparency, true)
                        )
                        renderer.scale = 2
                        return try XCTUnwrap(renderer.cgImage)
                    }

                    let labeled = try render(label: "Featured")
                    let blank = try render(label: "")
                    let actual = try filterPixels(labeled)
                    let background = try filterPixels(blank)
                    let center = (blank.height / 2 * blank.width + blank.width / 2) * 4
                    let backgroundRGB = (0..<3).map { Double(background[center + $0]) / 255 }
                    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                    UIColor(selected ? mode.accentText : mode.primaryText)
                        .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                    let foregroundLuminance = luminance([Double(red), Double(green), Double(blue)])
                    let backgroundLuminance = luminance(backgroundRGB)
                    let contrastRatio = (max(foregroundLuminance, backgroundLuminance) + 0.05)
                        / (min(foregroundLuminance, backgroundLuminance) + 0.05)
                    XCTAssertGreaterThanOrEqual(contrastRatio, 4.5,
                        "Low contrast: \(mode), selected=\(selected), contrast=\(contrast)")
                    var visibleTextPixels = 0
                    for y in 16..<72 {
                        for x in 16..<208 {
                            let offset = (y * labeled.width + x) * 4
                            let difference = (0..<3).map {
                                abs(Int(actual[offset + $0]) - Int(background[offset + $0]))
                            }.max() ?? 0
                            if difference > 50 { visibleTextPixels += 1 }
                        }
                    }
                    XCTAssertGreaterThan(visibleTextPixels, 200,
                        "Invisible label: \(mode), selected=\(selected), contrast=\(contrast)")
                    let attachment = XCTAttachment(image: UIImage(cgImage: labeled))
                    attachment.name = "REC-451 \(mode) selected-\(selected) \(contrast)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    private func luminance(_ rgb: [Double]) -> Double {
        let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }

    private func filterPixels(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(rendered)
        return pixels
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
