import CoreGraphics
import CoreLocation
import MapKit
import XCTest
@testable import Wander

final class ListMapPresentationTests: XCTestCase {
    func testContentStateDistinguishesEmptyUnresolvedPartialAndMappedLists() {
        XCTAssertEqual(
            ListMapContentState(
                totalItemCount: 0,
                resolvedPlaceCount: 0,
                mappedPlaceCount: 0
            ),
            .empty
        )
        XCTAssertEqual(
            ListMapContentState(
                totalItemCount: 4,
                resolvedPlaceCount: 0,
                mappedPlaceCount: 0
            ),
            .unresolved(total: 4)
        )
        XCTAssertEqual(
            ListMapContentState(
                totalItemCount: 5,
                resolvedPlaceCount: 3,
                mappedPlaceCount: 2
            ),
            .partial(mapped: 2, total: 5)
        )
        XCTAssertEqual(
            ListMapContentState(
                totalItemCount: 3,
                resolvedPlaceCount: 3,
                mappedPlaceCount: 3
            ),
            .mapped(count: 3)
        )
    }

    func testPinFocusChangesRailSelectionWithoutOpeningAPlace() {
        var state = ListMapInteractionState()

        state.handle(.focus("place-1"), validPlaceIDs: ["place-1", "place-2"])

        XCTAssertEqual(state.focusedPlaceID, "place-1")
        XCTAssertNil(state.openPlaceID)
    }

    func testTileOpenSelectsTheDestinationOnTheFirstEvent() {
        var state = ListMapInteractionState(focusedPlaceID: "place-1")

        state.handle(.open("place-2"), validPlaceIDs: ["place-1", "place-2"])

        XCTAssertEqual(state.focusedPlaceID, "place-1")
        XCTAssertEqual(state.openPlaceID, "place-2")
    }

    func testInteractionStateReconcilesFocusedAndOpenPlacesThatDisappear() {
        var state = ListMapInteractionState(
            focusedPlaceID: "removed-focus",
            openPlaceID: "still-visible"
        )

        state.reconcile(validPlaceIDs: ["still-visible"])

        XCTAssertNil(state.focusedPlaceID)
        XCTAssertEqual(state.openPlaceID, "still-visible")

        state.reconcile(validPlaceIDs: [])

        XCTAssertNil(state.focusedPlaceID)
        XCTAssertNil(state.openPlaceID)
    }

    func testClustererGroupsNearbyPlacesAndKeepsDispersedPlacesSeparate() {
        let coordinates = [
            coordinate("near-a", latitude: 34.05220, longitude: -118.24370),
            coordinate("near-b", latitude: 34.05245, longitude: -118.24335),
            coordinate("far", latitude: 34.09000, longitude: -118.19000)
        ]

        let clusters = ListMapClusterer.clusters(
            for: coordinates,
            in: region(
                center: CLLocationCoordinate2D(latitude: 34.055, longitude: -118.24),
                latitudeDelta: 0.1,
                longitudeDelta: 0.1
            ),
            viewportSize: CGSize(width: 390, height: 800)
        )

        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(
            Set(clusters.first(where: \.isCluster)?.memberIDs ?? []),
            Set(["near-a", "near-b"])
        )
        XCTAssertEqual(clusters.first(where: { !$0.isCluster })?.memberIDs, ["far"])
    }

    func testClustererFiltersInvalidCoordinatesAndZeroSentinels() {
        let clusters = ListMapClusterer.clusters(
            for: [
                coordinate("zero", latitude: 0, longitude: 0),
                coordinate("invalid-latitude", latitude: 91, longitude: -118.2),
                coordinate("not-a-number", latitude: .nan, longitude: -118.2),
                coordinate("valid", latitude: 34.0522, longitude: -118.2437)
            ],
            in: region(
                center: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437),
                latitudeDelta: 0.05,
                longitudeDelta: 0.05
            ),
            viewportSize: CGSize(width: 390, height: 800)
        )

        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].memberIDs, ["valid"])
        XCTAssertFalse(clusters[0].isCluster)
    }

    func testClustererPreservesEveryValidMemberExactlyOnce() {
        let coordinates = [
            coordinate("a", latitude: 34.05220, longitude: -118.24370),
            coordinate("b", latitude: 34.05235, longitude: -118.24350),
            coordinate("c", latitude: 34.05250, longitude: -118.24330),
            coordinate("d", latitude: 34.09500, longitude: -118.18500)
        ]

        let clusters = ListMapClusterer.clusters(
            for: coordinates,
            in: region(
                center: CLLocationCoordinate2D(latitude: 34.06, longitude: -118.235),
                latitudeDelta: 0.12,
                longitudeDelta: 0.12
            ),
            viewportSize: CGSize(width: 390, height: 800)
        )
        let members = clusters.flatMap(\.memberIDs)

        XCTAssertEqual(members.count, coordinates.count)
        XCTAssertEqual(Set(members), Set(coordinates.map(\.id)))
        XCTAssertEqual(
            Set(clusters.first(where: \.isCluster)?.memberIDs ?? []),
            Set(["a", "b", "c"])
        )
    }

    private func coordinate(
        _ id: String,
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees
    ) -> ListMapCoordinate {
        ListMapCoordinate(
            id: id,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )
    }

    private func region(
        center: CLLocationCoordinate2D,
        latitudeDelta: CLLocationDegrees,
        longitudeDelta: CLLocationDegrees
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }
}
