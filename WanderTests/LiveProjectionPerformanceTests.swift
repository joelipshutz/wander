import XCTest
@testable import Wander

@MainActor
final class LiveProjectionPerformanceTests: XCTestCase {
    private let eventDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testPerformanceProjectionWithNonoverlappingHistory() {
        measureProjection(overlapping: false)
    }

    func testPerformanceProjectionWithOverlappingHistory() {
        measureProjection(overlapping: true)
    }

    func testIdentityIntersectionMatchesPairwiseOracleInBothDirections() {
        let original = makePlace(id: 1, key: "original")
        let providerAlias = makePlace(id: 2, key: "renamed")
        providerAlias.sourceProvider = " MAPKIT "
        providerAlias.sourceProviderPlaceID = original.sourceProviderPlaceID
        providerAlias.latitude += 1

        let street = makePlace(id: 3, key: "street")
        street.sourceProviderPlaceID = nil
        street.address = "10 Main Street"
        let streetAlias = makePlace(id: 4, key: "street")
        streetAlias.sourceProviderPlaceID = nil
        streetAlias.address = "10 Main St."
        streetAlias.country = "United States"
        let distantStreet = makePlace(id: 5, key: "street")
        distantStreet.sourceProviderPlaceID = nil
        distantStreet.address = "10 Main St."
        distantStreet.latitude += 0.01

        let referenced = makePlace(id: 6, key: "reference")
        let referenceAlias = makePlace(id: 7, key: "reference")
        referenceAlias.sourceProviderPlaceID = referenced.id.uppercased()
        let uncorroborated = makePlace(id: 8, key: "different")
        uncorroborated.sourceProviderPlaceID = referenced.id

        let caseSensitive = makePlace(id: 9, key: "case-a")
        caseSensitive.sourceProviderPlaceID = "PlaceTokenA"
        let caseMismatch = makePlace(id: 10, key: "case-b")
        caseMismatch.sourceProviderPlaceID = "placetokena"
        let invalidCoordinates = makePlace(id: 11, key: "invalid")
        invalidCoordinates.latitude = .nan
        let exactInvalidAlias = makePlace(id: 11, key: "invalid-alias")
        exactInvalidAlias.latitude = .nan

        let examples = [original, providerAlias, street, streetAlias, distantStreet,
                        referenced, referenceAlias, uncorroborated, caseSensitive,
                        caseMismatch, invalidCoordinates, exactInvalidAlias]
        let unrelated = (100..<164).map { makePlace(id: $0, key: "unrelated-\($0)") }
        let collections: [[LocalPlace]] = [[]] + examples.map { [$0] } + [
            examples, unrelated, unrelated + [providerAlias], unrelated + [streetAlias],
            unrelated + [referenceAlias], unrelated + [exactInvalidAlias]
        ]
        let identities = collections.map { LivePlaceIdentity(places: $0) }

        XCTAssertTrue(identities[1].matches(providerAlias), "An opaque provider identity survives renaming and movement.")
        XCTAssertTrue(LivePlaceIdentity(places: [street]).matches(streetAlias))
        XCTAssertFalse(LivePlaceIdentity(places: [street]).matches(distantStreet))
        XCTAssertTrue(LivePlaceIdentity(places: [referenced]).matches(referenceAlias))
        XCTAssertFalse(LivePlaceIdentity(places: [referenced]).matches(uncorroborated))
        XCTAssertFalse(LivePlaceIdentity(places: [caseSensitive]).matches(caseMismatch))
        XCTAssertTrue(LivePlaceIdentity(places: [invalidCoordinates]).matches(exactInvalidAlias))

        for left in collections.indices {
            for right in collections.indices {
                // This oracle deliberately uses pairwise place matching, not
                // intersects or the implementation's choice of traversal side.
                let expected = collections[left].contains { lhs in
                    let singleton = LivePlaceIdentity(places: [lhs])
                    return collections[right].contains { singleton.matches($0) }
                }
                XCTAssertEqual(identities[left].intersects(identities[right]), expected,
                               "Intersection differs for collections \(left), \(right)")
                XCTAssertEqual(identities[right].intersects(identities[left]), expected,
                               "Intersection must remain symmetric for collections \(left), \(right)")
            }
        }
    }

    private struct Fixture {
        let activities: [FeedActivity]
        let ownHistory: [VisiblePlace]
        let listHistory: [LocalPlace]
        let overlapping: Bool
    }

    private struct PinSnapshot: Equatable {
        let id: String
        let representativeID: String
        let activities: [String]
        let priorOwnCheckIn: Bool
        let aliases: Set<String>
        let placeIDs: Set<String>
        let state: LiveTotemState

        init(_ pin: LivePlacePin) {
            id = pin.id
            representativeID = pin.place.place.id
            activities = pin.activities.map(\.id)
            priorOwnCheckIn = pin.hasPriorOwnCheckIn
            aliases = pin.identity.aliases
            placeIDs = pin.identity.placeIDs
            state = pin.totemState
        }
    }

    private func measureProjection(overlapping: Bool) {
        let fixture = makeFixture(overlapping: overlapping)
        let initial = project(fixture, previous: [])
        assertProjection(initial, fixture: fixture)
        let expected = initial.map(PinSnapshot.init)
        var samples: [Double] = []
        for _ in 0..<3 {
            let start = ContinuousClock.now
            let pins = project(fixture, previous: initial)
            let elapsed = start.duration(to: .now).components
            samples.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
            XCTAssertEqual(pins.map(PinSnapshot.init), expected,
                           "Repeated projection must preserve every event, alias, identifier and totem state.")
        }
        let sorted = samples.sorted()
        let scenario = overlapping ? "overlap" : "nonoverlap"
        // Keep device-dependent timing as comparable evidence, not a flaky CI
        // threshold. Baseline and candidate run this identical end-to-end path.
        let measurement = "REC675_PERF live_projection scenario=\(scenario) pins=300 own_history=1000 list_history=1000 includes_context=true iterations=3 median_ms=\(sorted[1]) min_ms=\(sorted[0]) max_ms=\(sorted[2])"
        print(measurement)
        let attachment = XCTAttachment(string: measurement)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func project(_ fixture: Fixture, previous: [LivePlacePin]) -> [LivePlacePin] {
        let context = LiveTotemContext(currentUserID: "viewer", query: LiveFeedQuery(),
            currentSavedPlaces: fixture.ownHistory, currentListPlaces: fixture.listHistory,
            currentStateIsComplete: true)
        return LiveMapProjection.pins(activities: fixture.activities, featured: [],
            ownCheckInPlaces: fixture.ownHistory, totemContext: context, previousPins: previous)
    }

    private func assertProjection(_ pins: [LivePlacePin], fixture: Fixture) {
        XCTAssertEqual(pins.count, 300)
        XCTAssertEqual(Set(pins.flatMap(\.activities).map(\.id)), Set(fixture.activities.map(\.id)))
        XCTAssertEqual(Set(pins.map(\.id)).count, pins.count)
        let byID = Dictionary(uniqueKeysWithValues: pins.map { ($0.id, $0) })
        for index in 0..<300 {
            guard let pin = byID[identifier(index)] else {
                XCTFail("Missing original pin \(index)")
                continue
            }
            let owns = fixture.overlapping && index < 150
            let listed = fixture.overlapping && index < 100
            XCTAssertEqual(pin.activities.map(\.id), ["event-\(index)"])
            XCTAssertEqual(pin.hasPriorOwnCheckIn, owns)
            XCTAssertEqual(pin.totemState.hasListMembership, listed)
            XCTAssertEqual(pin.totemState.hasSavedStatus, true)
            XCTAssertFalse(pin.totemState.isFeatured)
            XCTAssertTrue(pin.totemState.rails.contains { $0.ownership == .social && $0.status == .been })
            XCTAssertEqual(pin.totemState.rails.contains { $0.ownership == .currentUser && $0.status == .been }, owns)
            XCTAssertEqual(pin.identity.placeIDs.count, 1 + (owns ? 1 : 0) + (listed ? 1 : 0))
        }
    }

    private func makeFixture(overlapping: Bool) -> Fixture {
        let viewer = LocalProfile(localID: "viewer", handle: "viewer", displayName: "Viewer")
        let friend = LocalProfile(localID: "friend", handle: "friend", displayName: "Friend")
        let actor = ProfileShell(id: friend.id, handle: friend.handle, displayName: friend.displayName,
                                 avatarURL: nil, bio: nil, relationship: .mutual)
        let activities = (0..<300).map { index in
            let place = visible(makePlace(id: index, key: "pin-\(index)"), owner: friend)
            return FeedActivity(id: "event-\(index)", kind: .placeBeen, actor: actor,
                                place: place, occurredAt: eventDate.addingTimeInterval(Double(index)))
        }
        let own = (0..<1_000).map { index in
            let key = overlapping && index < 150 ? "pin-\(index)" : "own-\(index)"
            return visible(makePlace(id: 10_000 + index, key: key), owner: viewer)
        }
        let lists = (0..<1_000).map { index in
            let key = overlapping && index < 100 ? "pin-\(index)" : "list-\(index)"
            return makePlace(id: 20_000 + index, key: key)
        }
        return Fixture(activities: activities, ownHistory: own, listHistory: lists, overlapping: overlapping)
    }

    private func visible(_ place: LocalPlace, owner: LocalProfile) -> VisiblePlace {
        let save = LocalUserPlace(localID: "save-\(place.id)", userID: owner.id, placeID: place.id,
            status: .been, visibility: .followers, savedAt: eventDate, sourceType: "manual")
        return VisiblePlace(id: save.id, place: place, userPlace: save, owner: owner)
    }

    private func makePlace(id: Int, key: String) -> LocalPlace {
        LocalPlace(localID: identifier(id), canonicalName: "Fixture \(key)", category: "coffee",
            address: "\(key) Main Street", locality: "Sampleton", region: "CA", country: "US",
            latitude: 34.05, longitude: -118.24,
            sourceProvider: "mapkit", sourceProviderPlaceID: "fixture-\(key)")
    }

    private func identifier(_ index: Int) -> String {
        String(format: "67500000-0000-4000-8000-%012d", index)
    }
}
