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

    func testBareLaunchArgumentStartsAtIntro() {
        XCTAssertEqual(
            AstirBrandShellPage.resolved(
                from: ["Wander", "-AstirBrandShell"],
                environment: [:]
            ),
            .intro
        )
    }

    func testEnvironmentSupportsDeterministicSimulatorCapture() {
        XCTAssertEqual(
            AstirBrandShellPage.resolved(
                from: ["Wander"],
                environment: ["WANDER_ASTIR_BRAND_SHELL": "memory"]
            ),
            .memory
        )
    }

    func testPrototypeDoesNotActivateWithoutExplicitLaunchValue() {
        XCTAssertNil(
            AstirBrandShellPage.resolved(from: ["Wander"], environment: [:])
        )
    }

    func testUnknownPrototypePageFallsBackToIntro() {
        XCTAssertEqual(
            AstirBrandShellPage.resolved(
                from: ["Wander", "-AstirBrandShell", "unknown"],
                environment: [:]
            ),
            .intro
        )
    }

    func testPrototypeKeepsAstirSpellingAndConcreteEventLogistics() throws {
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
        XCTAssertTrue(source.contains("Thu, Sep 17"))
        XCTAssertTrue(source.contains("7–10 PM"))
        XCTAssertTrue(source.contains("Back Patio"))
        XCTAssertTrue(source.contains("Join the table"))
        XCTAssertTrue(source.contains("$32"))
    }
}
#endif
