import XCTest
@testable import Wander

@MainActor
final class FoundersWelcomeTests: XCTestCase {
    func testPlaybackResumesAcrossStoreInstancesAndStaysAccountScoped() {
        let name = "FoundersWelcomeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = FoundersWelcomeStore(defaults: defaults)
        store.save(seconds: 42.75, for: "joe")
        let restored = FoundersWelcomeStore(defaults: defaults)
        XCTAssertEqual(restored.progress(for: "joe").seconds, 42.75)
        XCTAssertFalse(restored.progress(for: "joe").handled)
        XCTAssertEqual(restored.progress(for: "ryan"), .init())
        restored.finish(for: "joe")
        XCTAssertTrue(store.progress(for: "joe").handled)
        XCTAssertFalse(store.progress(for: "ryan").handled)
        // A final periodic callback cannot undo a completed/explicitly skipped film.
        restored.save(seconds: 43, for: "joe")
        XCTAssertTrue(store.progress(for: "joe").handled)
    }

    func testInvalidPlaybackTimesCannotCorruptResumeProgress() {
        let name = "FoundersWelcomeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = FoundersWelcomeStore(defaults: defaults)
        store.save(seconds: -4, for: "person")
        XCTAssertEqual(store.progress(for: "person").seconds, 0)
        store.save(seconds: 200, for: "person")
        XCTAssertEqual(store.progress(for: "person").seconds, FoundersWelcomePlayer.duration)
        store.save(seconds: .nan, for: "person")
        store.save(seconds: .infinity, for: "person")
        XCTAssertEqual(store.progress(for: "person").seconds, FoundersWelcomePlayer.duration)
    }

    func testNativePlayerHasBundledMediaAndDoesNotAutoplay() {
        var saved: Double?
        let model = FoundersWelcomePlayer(initialPosition: 15, savePosition: { saved = $0 })
        XCTAssertNotNil(model.player.currentItem, "The offline welcome movie must be bundled.")
        XCTAssertNil(model.failure)
        XCTAssertFalse(model.hasStarted)
        XCTAssertEqual(model.player.rate, 0)
        model.tearDown()
        XCTAssertEqual(saved, 15)
        XCTAssertNil(model.player.currentItem)
        model.play()
        XCTAssertFalse(model.hasStarted, "A disappearing player cannot restart playback.")
    }
}
