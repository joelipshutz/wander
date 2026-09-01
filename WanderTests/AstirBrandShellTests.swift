#if DEBUG
@testable import Wander
import XCTest

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
