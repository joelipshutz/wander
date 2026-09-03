import MapKit
import UIKit
import XCTest
@testable import Wander

@MainActor
final class MapSnapshotListTests: XCTestCase {
    func testSelectionIncludesBothStatusesBeyondEightyPinsAndDeduplicates() {
        let places = (0..<201).map { pin(id: String($0), longitude: Double($0 % 180), status: $0 % 2 == 0 ? .been : .wanna) }
        let selected = MapSnapshotSelection.placeIDs(places: places + [places[0]]) { _ in true }
        XCTAssertEqual(selected.count, 201)
        XCTAssertEqual(selected, places.map(\.id))
    }

    func testSelectionUsesScreenProjectionAndRejectsOffscreenOrInvalidCoordinates() {
        let places = [pin(id: "west", longitude: 179), pin(id: "east", longitude: -179),
                      pin(id: "outside", longitude: 0), pin(id: "invalid", longitude: .nan)]
        // A viewport straddling the date line must retain both sides. Production
        // uses MapKit's screen projection, never a naive min/max longitude range.
        let selected = MapSnapshotSelection.placeIDs(places: places) { abs($0.longitude) >= 179 }
        XCTAssertEqual(selected, ["west", "east"])
        XCTAssertTrue(MapSnapshotSelection.placeIDs(places: places) { _ in false }.isEmpty)
    }

    func testSnapshotPersistsCoverAndMembershipWithoutChangingSourceSaves() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = WanderStorePersistence.file(url: directory.appendingPathComponent("store.json"))
        let store = WanderStore(fixtures: .seed(), persistence: persistence)
        let own = store.currentUserVisiblePlaces
        XCTAssertFalse(own.isEmpty)
        let before = own.map { ($0.userPlace.id, $0.userPlace.status) }
        let foreignIDs = store.visiblePlaces().filter { $0.owner.id != store.currentUser.id }.map { $0.place.id }
        let data = jpeg()
        let list = try XCTUnwrap(store.createMapSnapshotList(
            placeIDs: own.map { $0.place.id } + own.map { $0.place.id } + foreignIDs,
            coverData: data
        ))
        XCTAssertTrue(list.isStealth)
        XCTAssertEqual(list.snapshotCoverData, data)
        XCTAssertNil(list.snapshotCoverPath)
        XCTAssertEqual(Set(store.visiblePlaces(in: list).map { $0.place.id }), Set(own.map { $0.place.id }))
        XCTAssertEqual(store.currentUserVisiblePlaces.map { $0.userPlace.id }, before.map { $0.0 })
        XCTAssertEqual(store.currentUserVisiblePlaces.map { $0.userPlace.status }, before.map { $0.1 })

        let restored = WanderStore(fixtures: .empty(), persistence: persistence)
        let restoredList = try XCTUnwrap(restored.placeLists.first { $0.localID == list.localID })
        XCTAssertEqual(restoredList.snapshotCoverData, data)
        XCTAssertEqual(restored.visiblePlaces(in: restoredList).count, store.visiblePlaces(in: list).count)
        XCTAssertTrue(restored.updatePlaceList(id: list.localID, name: "Weekend", description: "A plan",
                                               visibility: .stealth, collaboratorUserIDs: []))
        XCTAssertEqual(restored.placeLists.first { $0.localID == list.localID }?.snapshotCoverData, data)
    }

    func testEmptyForeignOnlyAndInvalidImageDoNotCreateLists() {
        let store = WanderStore(fixtures: .seed())
        let count = store.placeLists.count
        XCTAssertNil(store.createMapSnapshotList(placeIDs: [], coverData: jpeg()))
        XCTAssertNil(store.createMapSnapshotList(placeIDs: ["missing"], coverData: jpeg()))
        XCTAssertNil(store.createMapSnapshotList(placeIDs: store.currentUserVisiblePlaces.map { $0.place.id }, coverData: Data([1, 2])))
        XCTAssertEqual(store.placeLists.count, count)
    }

    private func jpeg() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }.jpegData(compressionQuality: 0.8)!
    }

    private func pin(id: String, longitude: Double, status: YourMapPrototypeStatus = .been) -> YourMapPrototypePlace {
        YourMapPrototypePlace(id: id, name: id, latitude: 0, longitude: longitude, status: status,
                              category: "Coffee", city: "", country: "", tags: [], rating: 4,
                              visitCount: 1, lastVisitedAt: .now)
    }
}
