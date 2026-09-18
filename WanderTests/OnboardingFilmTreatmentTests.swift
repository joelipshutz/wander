import UIKit
import XCTest
@testable import Wander

final class OnboardingFilmTreatmentTests: XCTestCase {
    func testOrdinaryAndUnknownLaunchesKeepApprovedTreatment() {
        XCTAssertEqual(OnboardingWelcomeConfiguration.resolved(environment: [:]).visualTreatment, .approved)
        XCTAssertEqual(OnboardingVisualTreatment.resolved(environment: ["WANDER_ONBOARDING_TREATMENT": "unknown"]), .approved)
    }

    func testExplorationsPreserveCopySequenceAndPacing() {
        let approved = OnboardingWelcomeConfiguration.resolved(environment: [:])
        for value in ["film", "film-type"] {
            let exploration = OnboardingWelcomeConfiguration.resolved(environment: ["WANDER_ONBOARDING_TREATMENT": value])
            #if DEBUG
            XCTAssertTrue(exploration.visualTreatment.isFilm)
            #else
            XCTAssertEqual(exploration.visualTreatment, .approved)
            #endif
            XCTAssertEqual(exploration.ticker, approved.ticker)
            XCTAssertEqual(exploration.steps, approved.steps)
            for step in approved.steps {
                XCTAssertEqual(exploration.seconds(for: step), approved.seconds(for: step))
            }
        }
    }

    @MainActor func testMatchingFontsAndOriginalTextureAreBundled() throws {
        XCTAssertNotNil(UIFont(name: "HelveticaNeue-CondensedBlack", size: 40))
        XCTAssertNotNil(UIFont(name: "HelveticaNeue-BoldItalic", size: 17))
        XCTAssertNotNil(Bundle.main.url(forResource: "onboarding-film-texture", withExtension: "mp4"))
        let poster = try XCTUnwrap(Bundle.main.path(forResource: "onboarding-film-texture", ofType: "png"))
        XCTAssertNotNil(UIImage(contentsOfFile: poster))
    }
}
