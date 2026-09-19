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
        XCTAssertEqual(frame.verticalSlip(height: 852), 0)
        XCTAssertEqual(frame.displacement(row: frame.bandCenter, width: 390), 0)
        XCTAssertEqual(frame.density, 0.94)
    }

    func testFilmClockSurvivesSceneChangesAndResumesWithoutJumping() {
        let start = Date(timeIntervalSince1970: 100)
        var clock = OnboardingFilmClock(epoch: start)
        clock.setPlaying(true, at: start)
        let newSceneClock = clock
        XCTAssertEqual(newSceneClock.elapsed(at: start.addingTimeInterval(17)), 17)
        clock.setPlaying(false, at: start.addingTimeInterval(17))
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(40)), 17)
        clock.setPlaying(true, at: start.addingTimeInterval(40))
        clock.setPlaying(true, at: start.addingTimeInterval(41))
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(42)), 19)
    }

    func testReferenceRasterAndFaultSizeScaleWithViewport() {
        let fault = OnboardingFilmFrame(time: 1.78, moving: true)
        XCTAssertEqual(OnboardingFilmFrame.rasterScale, 720.0 / 393.0)
        XCTAssertEqual(fault.damageBand(row: fault.bandCenter), 1)
        XCTAssertEqual(fault.damageBand(row: fault.bandCenter + 0.081), 0)
        XCTAssertEqual(fault.verticalSlip(height: 1704), fault.verticalSlip(height: 852) * 2, accuracy: 0.0001)
        XCTAssertEqual(fault.chromaDelay(row: fault.bandCenter), 15.6 / OnboardingFilmFrame.rasterScale, accuracy: 0.0001)
        // Type power is six hundredths ahead of tape time in the original.
        XCTAssertLessThan(OnboardingFilmFrame(time: 0.68, moving: true).density, 0.4)
        XCTAssertGreaterThan(OnboardingFilmFrame(time: 0.62, moving: true).density, 0.85)
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
