import Combine
import XCTest
@testable import Wander

@MainActor
final class MapAppearancePreferenceTests: XCTestCase {
    func testFreshStoresDefaultToGrayscaleWithoutEnablingDarkMap() {
        for fixtures in [WanderFixtures.empty(), WanderFixtures.seed()] {
            let store = WanderStore(fixtures: fixtures)

            XCTAssertFalse(store.isColoredMapEnabled)
            XCTAssertFalse(store.isDarkMapEnabled)
        }
    }

    func testOlderSnapshotDefaultsToGrayscaleAndPreservesDarkMap() throws {
        let original = WanderStore(fixtures: .seed())
        original.isColoredMapEnabled = true
        original.isDarkMapEnabled = true
        let data = try JSONEncoder().encode(WanderStoreSnapshot(store: original))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        for storesNull in [false, true] {
            var legacy = object
            legacy.removeValue(forKey: "isColoredMapEnabled")
            if storesNull { legacy["isColoredMapEnabled"] = NSNull() }
            let snapshot = try JSONDecoder().decode(
                WanderStoreSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy)
            )
            let restored = WanderStore(fixtures: .empty(), persistence: WanderStorePersistence(
                load: { snapshot }, save: { _ in }
            ))

            XCTAssertFalse(restored.isColoredMapEnabled)
            XCTAssertTrue(restored.isDarkMapEnabled)
            XCTAssertEqual(restored.currentUser.id, original.currentUser.id)
        }
    }

    func testOlderSnapshotWithoutAppearanceKeysKeepsBothDefaultsOff() throws {
        let original = WanderStore(fixtures: .empty())
        let data = try JSONEncoder().encode(WanderStoreSnapshot(store: original))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "isColoredMapEnabled")
        legacy.removeValue(forKey: "isDarkMapEnabled")
        let snapshot = try JSONDecoder().decode(
            WanderStoreSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy)
        )
        let restored = WanderStore(fixtures: .empty(), persistence: WanderStorePersistence(
            load: { snapshot }, save: { _ in }
        ))

        XCTAssertFalse(restored.isColoredMapEnabled)
        XCTAssertFalse(restored.isDarkMapEnabled)
    }

    func testColoredMapChangesPublishImmediatelyWithoutChangingDarkMap() {
        let store = WanderStore(fixtures: .empty())
        store.isDarkMapEnabled = true
        var publications = 0
        let observation = store.objectWillChange.sink { publications += 1 }
        defer { observation.cancel() }

        store.isColoredMapEnabled = true

        XCTAssertTrue(store.isColoredMapEnabled)
        XCTAssertTrue(store.isDarkMapEnabled)
        XCTAssertEqual(publications, 1)

        store.isColoredMapEnabled = false

        XCTAssertFalse(store.isColoredMapEnabled)
        XCTAssertTrue(store.isDarkMapEnabled)
        XCTAssertEqual(publications, 2)
    }

    func testColoredMapOnAndOffSurvivePersistenceAndReload() throws {
        let (persistence, directory) = makePersistence()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WanderStore(fixtures: .empty(), persistence: persistence)
        store.isDarkMapEnabled = true

        for enabled in [true, false] {
            store.isColoredMapEnabled = enabled
            XCTAssertEqual(try XCTUnwrap(persistence.load()).isColoredMapEnabled, enabled)
            let restored = WanderStore(fixtures: .empty(), persistence: persistence)

            XCTAssertEqual(restored.isColoredMapEnabled, enabled)
            XCTAssertTrue(restored.isDarkMapEnabled)
        }
    }

    func testSignOutAndAccountSwitchPreserveAppearanceLikeDarkMap() {
        let store = WanderStore(fixtures: .seed())
        store.isColoredMapEnabled = true
        store.isDarkMapEnabled = true

        store.apply(authState: .signedOut)

        XCTAssertTrue(store.isColoredMapEnabled)
        XCTAssertTrue(store.isDarkMapEnabled)

        store.apply(authState: .signedIn(AuthSession(
            userID: "user_second", displayName: "Second Person", handle: "second"
        )))

        XCTAssertEqual(store.currentUser.serverID, "user_second")
        XCTAssertTrue(store.isColoredMapEnabled)
        XCTAssertTrue(store.isDarkMapEnabled)
    }

    func testAccountDeletionResetsAndPersistsBothAppearancePreferences() {
        let (persistence, directory) = makePersistence()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WanderStore(fixtures: .seed(), persistence: persistence)
        store.isColoredMapEnabled = true
        store.isDarkMapEnabled = true

        store.resetAfterAccountDeletion()

        XCTAssertFalse(store.isColoredMapEnabled)
        XCTAssertFalse(store.isDarkMapEnabled)
        let restored = WanderStore(fixtures: .empty(), persistence: persistence)
        XCTAssertFalse(restored.isColoredMapEnabled)
        XCTAssertFalse(restored.isDarkMapEnabled)
    }

    private func makePersistence() -> (WanderStorePersistence, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("map-appearance-tests-\(UUID().uuidString)", isDirectory: true)
        return (.file(url: directory.appendingPathComponent("store.json")), directory)
    }
}
