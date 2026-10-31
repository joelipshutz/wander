import Foundation
import SwiftData
import XCTest
@testable import Wander

/// Exercises the production operation-local observation helper with real
/// SwiftData models, including explicit cancellation at every scope exit.
@MainActor
final class ListInsertionObservationTests: XCTestCase {
    func testEveryGroupingFieldInvalidatesSynchronouslyAndReadsTheCompletedWrite() {
        let mutations: [(String, (LocalPlace) -> Void)] = [
            ("localID", { $0.localID = "changed-local" }),
            ("serverID", { $0.serverID = "changed-server" }),
            ("serverID nil", { $0.serverID = nil }),
            ("name", { $0.canonicalName = "Changed name" }),
            ("provider", { $0.sourceProvider = "changed-provider" }),
            ("providerID", { $0.sourceProviderPlaceID = "changed-provider-id" }),
            ("providerID nil", { $0.sourceProviderPlaceID = nil }),
            ("address", { $0.address = "20 Other Street" }),
            ("address nil", { $0.address = nil }),
            ("locality", { $0.locality = "Other city" }),
            ("region", { $0.region = nil }),
            ("country", { $0.country = nil }),
            ("latitude", { $0.latitude = 35 }),
            ("longitude", { $0.longitude = -119 })
        ]
        for (name, mutate) in mutations {
            let place = makePlace(name)
            let projection = ListInsertionPlaceObservation()
            defer { projection.finish() }
            _ = projection.read([place])
            let token = projection.validity
            XCTAssertTrue(token.isValid, name)
            mutate(place)
            // No run-loop yield or actor hop is allowed between write and check.
            XCTAssertFalse(token.isValid, name)
            XCTAssertEqual(token.callbackCount, 1, name)
            XCTAssertEqual(projection.read([place]), [ListInsertionPlaceFingerprint(place)], name)
            XCTAssertEqual(projection.fingerprintReadCount, 2, name)
        }
    }

    func testManagedSwiftDataModelUsesTheSameSynchronousInvalidation() throws {
        let container = try ModelContainer(for: LocalPlace.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let place = makePlace("managed")
        container.mainContext.insert(place)
        try container.mainContext.save()
        let projection = ListInsertionPlaceObservation()
        defer { projection.finish() }
        _ = projection.read([place])
        let token = projection.validity
        place.address = "Changed managed address"
        XCTAssertFalse(token.isValid)
        XCTAssertEqual(projection.read([place]), [ListInsertionPlaceFingerprint(place)])
        try container.mainContext.save()
        XCTAssertEqual(projection.read([place]), [ListInsertionPlaceFingerprint(place)])
    }

    func testSignedZeroCoordinatesDoNotEvadeBitExactFingerprintInvalidation() {
        for latitude in [true, false] {
            let place = makePlace("zero")
            place.latitude = 0
            place.longitude = 0
            let projection = ListInsertionPlaceObservation()
            defer { projection.finish() }
            let before = projection.read([place])
            let token = projection.validity
            if latitude { place.latitude = -0.0 } else { place.longitude = -0.0 }
            let storedBits = latitude ? place.latitude.bitPattern : place.longitude.bitPattern
            XCTAssertEqual(storedBits, Double(-0.0).bitPattern)
            XCTAssertFalse(token.isValid, "Double equality must not conceal a grouping-coordinate bit change")
            let after = projection.read([place])
            XCTAssertNotEqual(before, after)
            XCTAssertEqual(after, [ListInsertionPlaceFingerprint(place)])
        }
    }

    func testCountOrderAndSameValueReplacementAreValidatedOutsideObservation() {
        let first = makePlace("first")
        let second = makePlace("second")
        let projection = ListInsertionPlaceObservation()
        defer { projection.finish() }
        XCTAssertEqual(projection.read([first, second]), [first, second].map(ListInsertionPlaceFingerprint.init))
        let reads = projection.fingerprintReadCount
        _ = projection.read([first, second])
        XCTAssertEqual(projection.fingerprintReadCount, reads)
        XCTAssertEqual(projection.identityValidationCount, 4)

        XCTAssertEqual(projection.read([second, first]), [second, first].map(ListInsertionPlaceFingerprint.init))
        let replacement = makePlace("first")
        XCTAssertEqual(replacement.localID, first.localID)
        XCTAssertEqual(projection.read([second, replacement]), [second, replacement].map(ListInsertionPlaceFingerprint.init))
        XCTAssertEqual(projection.read([replacement]), [ListInsertionPlaceFingerprint(replacement)])
        XCTAssertEqual(projection.read([]), [])
    }

    func testAppendedAliasBridgeGetsItsOwnObservationWithoutRereadingExistingFields() {
        let first = makePlace("first")
        let second = makePlace("second")
        second.latitude = 35
        second.address = "20 Other Street"
        let bridge = makePlace("bridge")
        bridge.sourceProviderPlaceID = first.sourceProviderPlaceID
        bridge.latitude = second.latitude
        let projection = ListInsertionPlaceObservation()
        defer { projection.finish() }
        _ = projection.read([first, second])
        XCTAssertEqual(projection.fingerprintReadCount, 2)
        let places = [first, second, bridge]
        XCTAssertEqual(projection.read(places), places.map(ListInsertionPlaceFingerprint.init))
        XCTAssertEqual(projection.fingerprintReadCount, 3)
        XCTAssertTrue(VisiblePlaceGrouping.groupingAliases(for: first)
            .isDisjoint(with: VisiblePlaceGrouping.groupingAliases(for: second)))
        let aliases = VisiblePlaceGrouping.groupingAliases(for: bridge)
        XCTAssertFalse(aliases.isDisjoint(with: VisiblePlaceGrouping.groupingAliases(for: first)))
        XCTAssertFalse(aliases.isDisjoint(with: VisiblePlaceGrouping.groupingAliases(for: second)))

        let token = projection.validity
        bridge.latitude = 36
        XCTAssertFalse(token.isValid)
        XCTAssertEqual(projection.read(places), places.map(ListInsertionPlaceFingerprint.init))
    }

    func testDuplicateReferenceObjectsStayAliveUntilReplacementValidationAndScopeFinish() throws {
        var first: LocalPlace? = makePlace("duplicate")
        var second: LocalPlace? = makePlace("duplicate")
        weak var weakFirst = first
        weak var weakSecond = second
        let projection = ListInsertionPlaceObservation()
        defer { projection.finish() }
        _ = projection.read([try XCTUnwrap(first), try XCTUnwrap(second)])
        second = nil
        XCTAssertNotNil(weakSecond, "Identity checks must retain duplicate-reference nonwinners too")

        let replacement = makePlace("duplicate")
        replacement.address = "Replacement raw fields"
        XCTAssertEqual(projection.read([try XCTUnwrap(first), replacement]),
            [try XCTUnwrap(first), replacement].map(ListInsertionPlaceFingerprint.init))
        XCTAssertNil(weakSecond, "A replaced object is released after old observations are cancelled")
        first = nil
        XCTAssertNotNil(weakFirst)
        projection.finish()
        XCTAssertNil(weakFirst, "Explicit finish must release the retained model array")
    }

    func testEqualAssignmentsPreserveValuesAndDoNotLoseTheNextRealInvalidation() {
        let place = makePlace("equal")
        let projection = ListInsertionPlaceObservation()
        defer { projection.finish() }
        let before = projection.read([place])
        let sameName = place.canonicalName
        place.canonicalName = sameName
        // Foundation may coalesce equal assignments. Either notification
        // behavior is safe only if the following genuine write remains tracked.
        XCTAssertEqual(projection.read([place]), before)
        let token = projection.validity
        place.canonicalName = "Different next write"
        XCTAssertFalse(token.isValid)
        XCTAssertEqual(projection.read([place]), [ListInsertionPlaceFingerprint(place)])
    }

    func testSentinelCancelsOldGenerationAndFinishRemovesRemainingCallbacks() {
        let places = [makePlace("a"), makePlace("b"), makePlace("c")]
        let projection = ListInsertionPlaceObservation()
        _ = projection.read(places)
        let oldToken = projection.validity // Deliberately retain it to detect residual callbacks.
        places[0].canonicalName = "First generation edit"
        XCTAssertEqual(oldToken.callbackCount, 1)
        _ = projection.read(places)
        XCTAssertEqual(oldToken.callbackCount, 3, "Sentinel must flush both unchanged-model registrations")
        let newToken = projection.validity
        XCTAssertTrue(newToken.isValid)
        places[1].address = "Second generation edit"
        XCTAssertEqual(newToken.callbackCount, 1)
        XCTAssertEqual(oldToken.callbackCount, 3, "Old callbacks must never reach a new generation")

        projection.finish()
        XCTAssertEqual(newToken.callbackCount, 3)
        for place in places {
            place.latitude += 1
            place.canonicalName += " after finish"
        }
        projection.finish()
        XCTAssertEqual(oldToken.callbackCount, 3)
        XCTAssertEqual(newToken.callbackCount, 3, "No residual callback may run after explicit finish")
    }

    func testNestedScopesReturnThrowAndDeallocateTheirTokensAndSentinels() {
        enum ExpectedFailure: Error { case requested }
        let place = makePlace("scope")
        weak var outerToken: ListInsertionObservationValidity?
        weak var outerSentinel: ListInsertionObservationSentinel?
        weak var innerToken: ListInsertionObservationValidity?
        weak var innerSentinel: ListInsertionObservationSentinel?
        XCTAssertThrowsError(try withProjection { outer in
            _ = outer.read([place])
            outerToken = outer.validity
            outerSentinel = outer.sentinel
            withProjection { inner in
                _ = inner.read([place])
                innerToken = inner.validity
                innerSentinel = inner.sentinel
                place.address = "Nested edit"
                XCTAssertFalse(outer.validity.isValid)
                XCTAssertEqual(inner.read([place]), [ListInsertionPlaceFingerprint(place)])
                innerToken = inner.validity
            }
            XCTAssertNil(innerToken)
            XCTAssertNil(innerSentinel)
            XCTAssertEqual(outer.read([place]), [ListInsertionPlaceFingerprint(place)])
            // Capture the current generation after rearming the outer scope.
            outerToken = outer.validity
            throw ExpectedFailure.requested
        })
        XCTAssertNil(outerToken)
        XCTAssertNil(outerSentinel)
        place.address = "After both scopes"
    }

    func testLocaleChangeCancelsAndRebuildsEvenWithUnchangedModelIdentity() {
        let place = makePlace("locale")
        let projection = ListInsertionPlaceObservation()
        defer { projection.finish() }
        _ = projection.read([place], localeID: "en_US")
        let previousToken = projection.validity
        XCTAssertEqual(projection.read([place], localeID: "tr_TR"), [ListInsertionPlaceFingerprint(place)])
        XCTAssertEqual(previousToken.callbackCount, 1)
        XCTAssertTrue(projection.validity.isValid)
        XCTAssertEqual(projection.fingerprintReadCount, 2)
    }

    private func withProjection<Result>(_ operation: (ListInsertionPlaceObservation) throws -> Result) rethrows -> Result {
        let projection = ListInsertionPlaceObservation()
        defer { projection.finish() }
        return try operation(projection)
    }

    private func makePlace(_ id: String) -> LocalPlace {
        LocalPlace(localID: id, serverID: "server-\(id)", canonicalName: "Shared name",
            category: "park", address: "10 Main Street", locality: "City", region: "Region", country: "US",
            latitude: 34, longitude: -118, sourceProvider: "fixture", sourceProviderPlaceID: "provider-\(id)")
    }
}
