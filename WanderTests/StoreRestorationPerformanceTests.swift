import XCTest
@testable import Wander

@MainActor
final class StoreRestorationPerformanceTests: XCTestCase {
    func testLegacyRestorePreservesAttributeOrderAcrossLocalAndServerAliases() throws {
        let empty = WanderFixtures.empty()
        let place = LocalPlace(localID: "legacy-place", canonicalName: "Legacy fixture", category: "park",
            latitude: 34, longitude: -118)
        let save = LocalUserPlace(localID: "legacy-local", serverID: "legacy-server",
            userID: empty.currentUser.id, placeID: place.id, status: .been,
            visibility: .selfOnly, sourceType: "manual")
        let attributes = [
            LocalPlaceAttribute(localID: "server-first", userPlaceID: save.id,
                questionKey: "tags", valueType: "multi_tag", valueJSON: "[\"quiet\"]"),
            LocalPlaceAttribute(localID: "unrelated", userPlaceID: "unrelated-save",
                questionKey: "tags", valueType: "multi_tag", valueJSON: "[\"loud\"]"),
            LocalPlaceAttribute(localID: "local-second", userPlaceID: save.localID,
                questionKey: "tags", valueType: "multi_tag", valueJSON: "[\"views\"]")
        ]
        let fixtures = WanderFixtures(currentUser: empty.currentUser, profiles: [empty.currentUser], places: [place],
            userPlaces: [save], placeAttributes: attributes, follows: [], blocks: [],
            placeLists: [], placeListMembers: [], placeListItems: [], contactProvider: empty.contactProvider)
        let snapshot = WanderStoreSnapshot(store: WanderStore(fixtures: fixtures))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        object.removeValue(forKey: "placeVisits")
        let legacy = try JSONDecoder().decode(WanderStoreSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        let restored = legacy.restoredState(contactProvider: empty.contactProvider)
        let visit = try XCTUnwrap(restored.placeVisits.first)
        let expected = [attributes[0], attributes[2]].map {
            PlaceAttributeDraft(questionKey: $0.questionKey, valueType: $0.valueType, valueJSON: $0.valueJSON)
        }
        XCTAssertEqual(restored.placeVisits.count, 1)
        XCTAssertEqual(visit.userPlaceID, save.id)
        XCTAssertEqual(VisitAttributeAnswers.drafts(fromAttributeAnswersJSON: visit.attributeAnswersJSON), expected)
        XCTAssertEqual(visit.tags, VisitAttributeAnswers.tags(from: expected))
    }

    func testCurrentSnapshotDecodeAndStoreRestoreBenchmark() throws {
        try measureRestoration(legacy: false)
    }

    func testLegacySnapshotDecodeAndStoreRestoreBenchmark() throws {
        try measureRestoration(legacy: true)
    }

    private func measureRestoration(legacy: Bool) throws {
        let original = WanderStore(fixtures: .performanceScale())
        let snapshot = WanderStoreSnapshot(store: original)
        var data = try JSONEncoder().encode(snapshot)
        if legacy {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object.removeValue(forKey: "placeVisits")
            data = try JSONSerialization.data(withJSONObject: object)
        }
        let fixtureData = data
        var samples: [Double] = []
        for _ in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            let restored = WanderStore(fixtures: .empty(), persistence: WanderStorePersistence(
                load: { try? JSONDecoder().decode(WanderStoreSnapshot.self, from: fixtureData) }, save: { _ in }))
            samples.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            XCTAssertEqual(restored.currentUser.id, original.currentUser.id)
            XCTAssertEqual(restored.places.count, original.places.count)
            XCTAssertEqual(restored.userPlaces.count, original.userPlaces.count)
            XCTAssertEqual(restored.placeAttributes.count, original.placeAttributes.count)
            XCTAssertFalse(restored.placeVisits.isEmpty)
            if !legacy {
                XCTAssertEqual(restored.placeVisits.map(\.id), original.placeVisits.map(\.id))
                XCTAssertEqual(restored.placeVisits.map(\.tags), original.placeVisits.map(\.tags))
            }
        }
        let report = "REC675 snapshot_restore legacy=\(legacy) saves=\(original.userPlaces.count) samples_ms=\(samples) median_ms=\(samples.sorted()[2])"
        let attachment = XCTAttachment(string: report)
        attachment.name = "REC675-snapshot-restore-\(legacy ? "legacy" : "current")"
        attachment.lifetime = .keepAlways
        add(attachment)
        print(report)
    }
}
