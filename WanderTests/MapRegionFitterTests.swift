import CoreLocation
import MapKit
import XCTest
@testable import Wander

final class MapRegionFitterTests: XCTestCase {
    func testEmptyAndOnlyInvalidCoordinatesReturnNil() {
        XCTAssertNil(MapRegionFitter.region(fitting: []))
        XCTAssertNil(
            MapRegionFitter.region(
                fitting: [
                    CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    CLLocationCoordinate2D(latitude: .nan, longitude: -118.3),
                    CLLocationCoordinate2D(latitude: 34, longitude: .infinity),
                    CLLocationCoordinate2D(latitude: 91, longitude: 0),
                    CLLocationCoordinate2D(latitude: 0, longitude: 181)
                ]
            )
        )
    }

    func testFiltersInvalidCoordinatesAndZeroSentinel() {
        let validCoordinate = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        let region = MapRegionFitter.region(
            fitting: [
                CLLocationCoordinate2D(latitude: 0, longitude: 0),
                CLLocationCoordinate2D(latitude: .nan, longitude: -118.3),
                CLLocationCoordinate2D(latitude: 34, longitude: .infinity),
                validCoordinate
            ]
        )

        XCTAssertEqual(region?.center.latitude, validCoordinate.latitude)
        XCTAssertEqual(region?.center.longitude, validCoordinate.longitude)
        XCTAssertEqual(region?.span.latitudeDelta, 0.025)
        XCTAssertEqual(region?.span.longitudeDelta, 0.025)
    }

    func testFitsMultipleCoordinatesWithPadding() {
        let region = MapRegionFitter.region(
            fitting: [
                CLLocationCoordinate2D(latitude: 34.0, longitude: -118.3),
                CLLocationCoordinate2D(latitude: 34.1, longitude: -118.1)
            ]
        )

        XCTAssertEqual(region?.center.latitude ?? 0, 34.05, accuracy: 0.0001)
        XCTAssertEqual(region?.center.longitude ?? 0, -118.2, accuracy: 0.0001)
        XCTAssertGreaterThan(region?.span.latitudeDelta ?? 0, 0.1)
        XCTAssertGreaterThan(region?.span.longitudeDelta ?? 0, 0.2)
    }

    func testTightClusterContainsEveryCoordinate() throws {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 34.05220, longitude: -118.24370),
            CLLocationCoordinate2D(latitude: 34.05228, longitude: -118.24361),
            CLLocationCoordinate2D(latitude: 34.05212, longitude: -118.24379)
        ]

        let region = try XCTUnwrap(
            MapRegionFitter.region(fitting: coordinates, minimumSpan: 0.000_01)
        )

        XCTAssertGreaterThan(region.span.latitudeDelta, 0)
        XCTAssertGreaterThan(region.span.longitudeDelta, 0)
        assert(region: region, contains: coordinates)
    }

    func testDispersedCoordinatesUseARegionThatContainsEveryCoordinate() throws {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437),
            CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        ]

        let region = try XCTUnwrap(MapRegionFitter.region(fitting: coordinates))

        XCTAssertGreaterThan(region.span.latitudeDelta, 13)
        XCTAssertGreaterThan(region.span.longitudeDelta, 48)
        assert(region: region, contains: coordinates)
    }

    func testAntimeridianCoordinatesUseShortestLongitudeArc() throws {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 37.7, longitude: 179.6),
            CLLocationCoordinate2D(latitude: 37.8, longitude: -179.7),
            CLLocationCoordinate2D(latitude: 37.9, longitude: 179.9)
        ]

        let region = try XCTUnwrap(MapRegionFitter.region(fitting: coordinates))

        XCTAssertEqual(abs(region.center.longitude), 179.95, accuracy: 0.0001)
        XCTAssertLessThan(region.span.longitudeDelta, 1)
        assert(region: region, contains: coordinates)
    }

    func testSpansAreClampedToMapKitBounds() throws {
        let region = try XCTUnwrap(
            MapRegionFitter.region(
                fitting: [
                    CLLocationCoordinate2D(latitude: -90, longitude: -90),
                    CLLocationCoordinate2D(latitude: 90, longitude: 90)
                ],
                minimumSpan: 720,
                paddingMultiplier: 4
            )
        )

        XCTAssertEqual(region.center.latitude, 0)
        XCTAssertEqual(region.span.latitudeDelta, 180)
        XCTAssertEqual(region.span.longitudeDelta, 360)
        XCTAssertTrue(CLLocationCoordinate2DIsValid(region.center))
    }

    func testViewportInsetsExpandAndShiftRegionIntoVisibleMapArea() {
        let source = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34, longitude: -118),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.2)
        )

        let adjusted = MapRegionFitter.region(
            source,
            accountingForViewportHeight: 800,
            obscuredTopHeight: 80,
            obscuredBottomHeight: 200
        )

        XCTAssertEqual(adjusted.span.latitudeDelta, 0.1 * (800 / 520), accuracy: 0.000_001)
        XCTAssertEqual(adjusted.span.longitudeDelta, source.span.longitudeDelta)
        XCTAssertLessThan(adjusted.center.latitude, source.center.latitude)

        let sourceCenterY = projectedY(
            latitude: source.center.latitude,
            in: adjusted,
            viewportHeight: 800
        )
        XCTAssertEqual(sourceCenterY, 340, accuracy: 0.001)
    }

    func testSingleCoordinateUsesMinimumSpan() {
        let region = MapRegionFitter.region(
            fitting: [CLLocationCoordinate2D(latitude: 34.0, longitude: -118.3)]
        )

        XCTAssertEqual(region?.span.latitudeDelta, 0.025)
        XCTAssertEqual(region?.span.longitudeDelta, 0.025)
    }

    func testSubmittedCategorySearchOnlyZoomsOutToFitExpandedResults() throws {
        let viewportHeight: CGFloat = 844
        let obscuredTopHeight: CGFloat = 128
        let obscuredBottomHeight: CGFloat = 320
        let submittedRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.075, longitude: -118.285),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.14)
        )
        let resultCoordinates = [
            CLLocationCoordinate2D(latitude: 34.076, longitude: -118.283),
            CLLocationCoordinate2D(latitude: 34.1478, longitude: -118.1445),
            CLLocationCoordinate2D(latitude: 33.7701, longitude: -118.1937),
            CLLocationCoordinate2D(latitude: 33.5427, longitude: -117.7854)
        ]

        let region = try XCTUnwrap(
            MapSubmittedSearchCameraPolicy.region(
                fitting: resultCoordinates,
                submittedRegion: submittedRegion,
                viewportHeight: viewportHeight,
                obscuredTopHeight: obscuredTopHeight,
                obscuredBottomHeight: obscuredBottomHeight
            )
        )

        XCTAssertGreaterThanOrEqual(
            region.span.latitudeDelta,
            submittedRegion.span.latitudeDelta
        )
        XCTAssertGreaterThanOrEqual(
            region.span.longitudeDelta,
            submittedRegion.span.longitudeDelta
        )
        assert(region: region, contains: resultCoordinates)
        for coordinate in resultCoordinates {
            XCTAssertGreaterThanOrEqual(projectedY(
                latitude: coordinate.latitude,
                in: region,
                viewportHeight: viewportHeight
            ), obscuredTopHeight)
            XCTAssertLessThanOrEqual(projectedY(
                latitude: coordinate.latitude,
                in: region,
                viewportHeight: viewportHeight
            ), viewportHeight - obscuredBottomHeight)
        }
    }

    func testSubmittedCategorySearchNeedsAtLeastOneResultToMoveCamera() {
        let submittedRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.075, longitude: -118.285),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.14)
        )

        XCTAssertNil(
            MapSubmittedSearchCameraPolicy.region(
                fitting: [],
                submittedRegion: submittedRegion,
                viewportHeight: 800,
                obscuredTopHeight: 80,
                obscuredBottomHeight: 240
            )
        )
    }

    func testSubmittedCategorySearchDoesNotZoomOutForResultsAlreadyInsideViewport() throws {
        let submittedRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.075, longitude: -118.285),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.14)
        )

        let region = try XCTUnwrap(
            MapSubmittedSearchCameraPolicy.region(
                fitting: [
                    CLLocationCoordinate2D(latitude: 34.076, longitude: -118.283),
                    CLLocationCoordinate2D(latitude: 34.074, longitude: -118.287)
                ],
                submittedRegion: submittedRegion,
                viewportHeight: 800,
                obscuredTopHeight: 0,
                obscuredBottomHeight: 218
            )
        )

        XCTAssertEqual(
            region.span.latitudeDelta,
            submittedRegion.span.latitudeDelta,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            region.span.longitudeDelta,
            submittedRegion.span.longitudeDelta,
            accuracy: 0.000_001
        )
    }

    private func assert(
        region: MKCoordinateRegion,
        contains coordinates: [CLLocationCoordinate2D],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let halfLatitudeSpan = region.span.latitudeDelta / 2
        let halfLongitudeSpan = region.span.longitudeDelta / 2

        for coordinate in coordinates {
            XCTAssertLessThanOrEqual(
                abs(coordinate.latitude - region.center.latitude),
                halfLatitudeSpan + 0.000_001,
                file: file,
                line: line
            )
            XCTAssertLessThanOrEqual(
                shortestLongitudeDistance(
                    from: region.center.longitude,
                    to: coordinate.longitude
                ),
                halfLongitudeSpan + 0.000_001,
                file: file,
                line: line
            )
        }
    }

    private func shortestLongitudeDistance(
        from first: CLLocationDegrees,
        to second: CLLocationDegrees
    ) -> CLLocationDegrees {
        let absoluteDifference = abs(first - second)
        return min(absoluteDifference, 360 - absoluteDifference)
    }

    private func projectedY(
        latitude: CLLocationDegrees,
        in region: MKCoordinateRegion,
        viewportHeight: CGFloat
    ) -> CGFloat {
        viewportHeight * (
            0.5 - CGFloat(latitude - region.center.latitude) / region.span.latitudeDelta
        )
    }
}
