import UIKit
import XCTest
@testable import Wander

final class OnboardingFilmTreatmentTests: XCTestCase {
    func testTrackingHitsMatchEventsCadenceWithoutContinuousTearing() {
        for time in [1.70, 1.85, 4.75, 6.95, 7.10, 9.70] {
            XCTAssertTrue(OnboardingFilmFrame(time: time, moving: true).tracking)
        }
        for time in [0.0, 1.5, 1.9, 4.9, 6.8, 7.2, 8.0] {
            XCTAssertFalse(OnboardingFilmFrame(time: time, moving: true).tracking)
        }
        let frames = (0..<192).map { OnboardingFilmFrame(time: Double($0) / 24, moving: true) }
        XCTAssertTrue((12...18).contains(frames.filter(\.tracking).count))
    }

    func testTrackingDistortsRowsAndDensityFaultsRecover() {
        let fault = OnboardingFilmFrame(time: 1.78, moving: true)
        let tear = fault.displacement(row: fault.bandCenter, width: 390)
        let intact = fault.displacement(row: 0, width: 390)
        XCTAssertGreaterThan(abs(tear - intact), 10)
        XCTAssertLessThan(OnboardingFilmFrame(time: 0.9, moving: true).density, 0.2)
        XCTAssertGreaterThan(OnboardingFilmFrame(time: 1.3, moving: true).density, 0.85)
    }

    func testStaticFrameHasNoMotionOrDensityFailureEvenAtFaultTime() {
        let frame = OnboardingFilmFrame(time: 1.78, moving: false)
        XCTAssertFalse(frame.tracking)
        XCTAssertEqual(frame.verticalSlip, 0)
        XCTAssertEqual(frame.displacement(row: frame.bandCenter, width: 390), 0)
        XCTAssertEqual(frame.density, 0.94)
    }

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
