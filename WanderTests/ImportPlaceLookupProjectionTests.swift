import Foundation
import XCTest
@testable import Wander

@MainActor
final class ImportPlaceLookupProjectionTests: XCTestCase {
    func testStrictShortlistPreservesAliasesProviderConflictsAndFallbackPrecedence() {
        let alias = place("  LOCAL\tAlias  ", serverID: " SERVER  Alias ", name: "Different name",
            provider: "mapkit", providerID: "conflicting-provider-id")
        assertParity([alias], candidate(id: "local alias", name: "Other", providerID: "other"), expected: alias)
        assertParity([alias], candidate(id: "server alias", name: "Other", providerID: "other"), expected: alias)

        let branch = place("branch", name: "Branch Coffee", provider: "mapkit", providerID: "branch-one")
        assertParity([branch], candidate(name: "Branch Coffee", providerID: "branch-two"), expected: nil)
        assertParity([branch], candidate(name: "Branch Coffee", provider: "google", providerID: "branch-two"), expected: branch)
        assertParity([branch], candidate(name: "Branch Coffee", providerID: nil), expected: nil,
            "A missing provider ID still uses the candidate ID, as the strict matcher requires")

        let missingProviderID = place("without-provider-id", name: "Branch Coffee", providerID: nil)
        assertParity([missingProviderID], candidate(name: "Branch Coffee", providerID: "new-id"), expected: missingProviderID)

        let earlyFallback = place("early", name: "Café First", provider: "legacy", providerID: nil,
            address: "10 Harbor Street", latitude: 35, longitude: -119)
        let laterExact = place("later", name: "Other name", provider: "mapkit", providerID: "exact-id")
        let fallbackCandidate = candidate(name: "Cafe First", providerID: "exact-id", address: "10 Harbor St")
        assertParity([earlyFallback, laterExact], fallbackCandidate, expected: earlyFallback)
        assertParity([laterExact, earlyFallback], fallbackCandidate, expected: laterExact)

        let separatorA = place("separator-a", name: "First", provider: "a:b", providerID: "c")
        let separatorB = place("separator-b", name: "Second", provider: "a", providerID: "b:c")
        assertParity([separatorA, separatorB], candidate(name: "Neither", provider: "a", providerID: "b:c"), expected: separatorB)
        assertParity([place("blank", name: "", provider: "", providerID: nil)],
            candidate(id: "", name: "", provider: "", providerID: nil), expected: nil)
    }

    func testProjectionRevalidatesDirectAliasNameAndProviderMutations() {
        let mutable = place("original", name: "Original", provider: "legacy", providerID: nil)
        let places = [mutable]
        let projection = ImportPlaceLookupProjection(places: places, collectionRevision: 0)
        let target = candidate(id: "target-alias", name: "Target", provider: "mapkit", providerID: "target-provider")
        assertParity(projection, places, target, expected: nil)

        mutable.localID = " TARGET-ALIAS "
        assertParity(projection, places, target, expected: mutable)
        mutable.localID = "original"
        mutable.serverID = "TARGET-ALIAS"
        assertParity(projection, places, target, expected: mutable)
        mutable.serverID = nil
        assertParity(projection, places, target, expected: nil)

        mutable.canonicalName = "Target"
        assertParity(projection, places, target, expected: mutable)
        mutable.canonicalName = "Original"
        assertParity(projection, places, target, expected: nil)

        mutable.sourceProviderPlaceID = " TARGET-PROVIDER "
        assertParity(projection, places, target, expected: nil)
        mutable.sourceProvider = " MAPKIT "
        assertParity(projection, places, target, expected: mutable)
        mutable.sourceProviderPlaceID = "different-provider-id"
        assertParity(projection, places, target, expected: nil)
    }

    func testFinalPredicateReadsAddressAndCoordinateEditsWithoutChangingShortlistKeys() {
        let mutable = place("fallback", name: "Fallback", provider: "legacy", providerID: nil,
            address: "Old Street", latitude: 35, longitude: -119)
        let places = [mutable]
        let projection = ImportPlaceLookupProjection(places: places, collectionRevision: 0)
        let target = candidate(name: "Fallback", providerID: "new", address: "20 Harbor Road")
        assertParity(projection, places, target, expected: nil)
        mutable.address = "20 Harbor Rd"
        assertParity(projection, places, target, expected: mutable)
        mutable.locality = "Different city"
        assertParity(projection, places, target, expected: nil)
        mutable.address = nil
        mutable.latitude = target.latitude!
        mutable.longitude = target.longitude!
        assertParity(projection, places, target, expected: mutable)
        mutable.longitude += 1
        assertParity(projection, places, target, expected: nil)
    }

    func testAppendReplacementAndReorderingKeepOriginalArrayFirstBehavior() {
        let first = place("first", name: "Shared", provider: "legacy", providerID: nil)
        let second = place("second", name: "Shared", provider: "legacy", providerID: nil)
        let target = candidate(name: "Shared", providerID: "target")
        let projection = ImportPlaceLookupProjection(places: [first], collectionRevision: 0)
        assertParity(projection, [first], target, expected: first)
        projection.didAppend(second, totalCount: 2, collectionRevision: 1)
        assertParity(projection, [first, second], target, revision: 1, expected: first)
        assertParity(projection, [second, first], target, revision: 2, expected: second)

        let replacement = place("replacement", name: "Shared", provider: "legacy", providerID: nil)
        assertParity(projection, [replacement, first], target, revision: 3, expected: replacement)
        // Raw reference validation also protects an unannounced replacement.
        assertParity(projection, [second, first], target, revision: 3, expected: second)
    }

    func testStoreScopeMatchesOrdinaryReadsAndImmediatelyFindsNewSaves() throws {
        let first = place("first", name: "Shared", provider: "legacy", providerID: nil)
        let later = place("later", name: "Other", providerID: "exact")
        let store = makeStore(places: [first, later])
        let target = candidate(name: "Shared", providerID: "exact")
        let expected = try XCTUnwrap(store.existingImportSave(matching: target))
        XCTAssertEqual(expected.userPlaceID, "lookup-save-0")
        let novel = candidate(id: "new-candidate", name: "New place", providerID: "new-provider",
            latitude: 36, longitude: -120)

        try store.withImportPlaceLookupProjection {
            XCTAssertEqual(store.existingImportSave(matching: target)?.userPlaceID, expected.userPlaceID)
            XCTAssertNil(store.existingImportSave(matching: novel))
            let added = store.saveImportedCandidate(novel, status: .wannaGo, visibility: .selfOnly,
                note: nil, sourceType: .link)
            XCTAssertEqual(store.existingImportSave(matching: novel)?.userPlaceID, added.userPlaceID)
            let repeated = store.saveImportedCandidate(novel, status: .wannaGo, visibility: .selfOnly,
                note: "Must not replace the original", sourceType: .link)
            XCTAssertEqual(repeated.userPlaceID, added.userPlaceID)
            XCTAssertEqual(store.places.count, 3)
            XCTAssertEqual(store.userPlaces.count, 3)
            let saved = try XCTUnwrap(store.userPlaces.first { $0.id == added.userPlaceID })
            XCTAssertNil(saved.note)
            first.canonicalName = "Renamed inside import"
            XCTAssertEqual(store.existingImportSave(matching: target)?.userPlaceID, "lookup-save-1")

            store.withImportPlaceLookupProjection {
                first.canonicalName = "Shared"
                XCTAssertEqual(store.existingImportSave(matching: target)?.userPlaceID, expected.userPlaceID)
            }
            XCTAssertEqual(store.existingImportSave(matching: target)?.userPlaceID, expected.userPlaceID)
        }
        first.canonicalName = "Changed after import"
        XCTAssertEqual(store.existingImportSave(matching: target)?.userPlaceID, "lookup-save-1")
        first.canonicalName = "Shared"
        XCTAssertEqual(store.existingImportSave(matching: target)?.userPlaceID, expected.userPlaceID)
    }

    func testThrowingScopeRestoresOrdinaryLookup() {
        enum ExpectedFailure: Error { case stop }
        let mutable = place("mutable", name: "Original", provider: "legacy", providerID: nil)
        let store = makeStore(places: [mutable])
        let target = candidate(name: "Changed", providerID: "target")
        XCTAssertThrowsError(try store.withImportPlaceLookupProjection {
            XCTAssertNil(store.existingImportSave(matching: target))
            throw ExpectedFailure.stop
        })
        mutable.canonicalName = "Changed"
        XCTAssertEqual(store.existingImportSave(matching: target)?.userPlaceID, "lookup-save-0")
    }

    private func assertParity(_ places: [LocalPlace], _ candidate: PlaceCandidate,
                              expected: LocalPlace?, _ message: String = "",
                              file: StaticString = #filePath, line: UInt = #line) {
        assertParity(ImportPlaceLookupProjection(places: places, collectionRevision: 0), places,
            candidate, expected: expected, message, file: file, line: line)
    }

    private func assertParity(_ projection: ImportPlaceLookupProjection, _ places: [LocalPlace],
                              _ candidate: PlaceCandidate, revision: UInt64 = 0,
                              expected: LocalPlace?, _ message: String = "",
                              file: StaticString = #filePath, line: UInt = #line) {
        let reference = places.first { VisiblePlaceGrouping.matches($0, candidate: candidate) }
        let actual = projection.firstMatch(for: candidate, in: places, collectionRevision: revision)
        XCTAssertTrue(reference === expected, "Reference precondition: \(message)", file: file, line: line)
        XCTAssertTrue(actual === reference, message, file: file, line: line)
    }

    private func makeStore(places: [LocalPlace]) -> WanderStore {
        let owner = LocalProfile(localID: "lookup-owner", handle: "lookup", displayName: "Lookup")
        let saves = places.enumerated().map { index, place in
            LocalUserPlace(localID: "lookup-save-\(index)", userID: owner.id, placeID: place.id,
                status: .wannaGo, visibility: .selfOnly, sourceType: "manual")
        }
        return WanderStore(fixtures: WanderFixtures(currentUser: owner, profiles: [owner], places: places,
            userPlaces: saves, placeAttributes: [], follows: [], blocks: [],
            placeLists: [], placeListMembers: [], placeListItems: [],
            contactProvider: FakeContactProvider(seededMatches: [])))
    }

    private func place(_ id: String, serverID: String? = nil, name: String,
                       provider: String = "mapkit", providerID: String?, address: String? = nil,
                       latitude: Double = 34, longitude: Double = -118) -> LocalPlace {
        LocalPlace(localID: id, serverID: serverID, canonicalName: name, category: "park",
            address: address, locality: "Los Angeles", region: "CA", country: "US",
            latitude: latitude, longitude: longitude, sourceProvider: provider,
            sourceProviderPlaceID: providerID)
    }

    private func candidate(id: String = "candidate-id", name: String,
                           provider: String = "mapkit", providerID: String?, address: String? = nil,
                           latitude: Double = 34, longitude: Double = -118) -> PlaceCandidate {
        PlaceCandidate(id: id, name: name, category: "park", address: address,
            locality: "Los Angeles", region: "CA", country: "US",
            latitude: latitude, longitude: longitude, sourceProvider: provider,
            sourceProviderPlaceID: providerID, confidence: 1)
    }
}
