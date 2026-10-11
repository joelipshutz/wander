import XCTest
@testable import Wander

@MainActor final class LiveBrowseSelectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testDefaultFollowingUsesFixedSevenDayBoundsIncludingUnmappedActivity() {
        let selection = LiveBrowseSelection(now: now)
        XCTAssertEqual(selection.scope, .following)
        XCTAssertEqual(selection.radius, .fiveKilometers)
        XCTAssertEqual(selection.occurredAfter, now.addingTimeInterval(-7 * 86_400))
        XCTAssertEqual(selection.occurredBefore, now)
        XCTAssertTrue(selection.includes(event("start", offset: -7 * 86_400)))
        XCTAssertTrue(selection.includes(event("end")))
        XCTAssertFalse(selection.includes(event("old", offset: -7 * 86_400 - 1)))
        XCTAssertFalse(selection.includes(event("future", offset: 1)))
    }

    func testTwentyFourHourAndAllTimeNeverMixFutureItemsIntoPastActivity() {
        var selection = LiveBrowseSelection(now: now)
        selection.time = .day
        XCTAssertEqual(selection.time.title, "Past 24 hours")
        XCTAssertTrue(selection.includes(event("day", offset: -86_400)))
        XCTAssertFalse(selection.includes(event("older", offset: -86_401)))
        selection.time = .all
        XCTAssertNil(selection.occurredAfter)
        XCTAssertTrue(selection.includes(event("historical", offset: -400 * 86_400)))
        XCTAssertFalse(selection.includes(event("tomorrow", offset: 86_400)))
    }

    func testNearbyRequiresAnExplicitKnownCityAndDoesNotFallBackToEverywhere() {
        var selection = LiveBrowseSelection(now: now)
        selection.scope = .nearby
        XCTAssertFalse(selection.isValid)
        XCTAssertFalse(selection.includes(event("unmapped")))
        selection.cityID = "unrecognized-city"
        XCTAssertFalse(selection.isValid)
        selection.cityID = "los-angeles"
        XCTAssertTrue(selection.isValid)
        XCTAssertFalse(selection.includes(event("unmapped")))
    }

    func testFiveKilometerRadiusExpandsOnlyWhenTwentyFiveIsSelected() {
        var selection = LiveBrowseSelection(now: now)
        selection.scope = .nearby
        selection.cityID = "los-angeles"
        let near = event("near", place: place("near", latitude: 34.06))
        let tenKilometers = event("middle", place: place("middle", latitude: 34.14))
        let outside = event("outside", place: place("outside", latitude: 34.35))
        XCTAssertTrue(selection.includes(near))
        XCTAssertFalse(selection.includes(tenKilometers))
        selection.radius = .twentyFiveKilometers
        XCTAssertTrue(selection.includes(near))
        XCTAssertTrue(selection.includes(tenKilometers))
        XCTAssertFalse(selection.includes(outside))
        XCTAssertFalse(selection.includes(event("invalid", place: place("invalid", latitude: .nan))))
        selection.scope = .following
        XCTAssertTrue(selection.includes(outside))
    }

    func testPersonAndCategorySelectionsIntersectWithoutBroadeningEither() {
        let coffee = place("coffee", category: WanderPlaceCategory.coffeeTeaSweets)
        let food = place("food", category: WanderPlaceCategory.restaurantsFood)
        var selection = LiveBrowseSelection(now: now)
        selection.personIDs = ["selected-person"]
        selection.categoryIDs = [coffee.effectiveCategory]
        XCTAssertTrue(selection.includes(event("match", personID: "selected-person", place: coffee)))
        XCTAssertFalse(selection.includes(event("other-person", personID: "other-person", place: coffee)))
        XCTAssertFalse(selection.includes(event("other-category", personID: "selected-person", place: food)))
        XCTAssertFalse(selection.includes(event("no-category", personID: "selected-person")))
        selection.personIDs = ["not-loaded"]
        XCTAssertFalse(selection.includes(event("still-excluded", personID: "selected-person", place: coffee)))
    }

    func testReturningToNearbyRestartsAtFiveKilometersWithoutChangingOtherRefinements() {
        var selection = LiveBrowseSelection(now: now)
        selection.scope = .nearby
        selection.cityID = "los-angeles"
        selection.radius = .twentyFiveKilometers
        selection.personIDs = ["selected-person"]
        selection.scope = .following
        selection.scope = .nearby
        XCTAssertEqual(selection.radius, .fiveKilometers)
        XCTAssertEqual(selection.cityID, "los-angeles")
        XCTAssertEqual(selection.personIDs, ["selected-person"])
    }

    func testCategoryUsesViewerEffectiveProjectionAndActivityKindStillApplies() {
        let visible = place("custom", category: WanderPlaceCategory.restaurantsFood)
        visible.userPlace.viewerPrimaryCategory = WanderPlaceCategory.coffeeTeaSweets
        var selection = LiveBrowseSelection(now: now)
        selection.categoryIDs = [visible.effectiveCategory]
        selection.activityType = .checkIns
        XCTAssertTrue(selection.includes(event("check", place: visible, kind: .placeBeen)))
        XCTAssertFalse(selection.includes(event("wanna", place: visible, kind: .placeWannaGo)))
        XCTAssertFalse(selection.includes(event("collection", place: visible, kind: .listItemAdded)))
    }

    func testFacetChoicesComeOnlyFromLoadedInputAndDeduplicatePeopleAndCategories() {
        let coffee = place("coffee", category: WanderPlaceCategory.coffeeTeaSweets)
        let rows = [event("first", personID: "a", place: coffee), event("repeat", personID: "a", place: coffee),
                    event("list", personID: "b")]
        XCTAssertEqual(LiveBrowseSelection.people(in: rows).map(\.id), ["a", "b"])
        XCTAssertEqual(LiveBrowseSelection.categories(in: rows), [coffee.effectiveCategory])
        XCTAssertTrue(LiveBrowseSelection.people(in: []).isEmpty)
        XCTAssertTrue(LiveBrowseSelection.categories(in: []).isEmpty)
    }

    func testRecommitUpdatesBothTimeBoundsWithoutMutatingThePriorSelection() {
        var previous = LiveBrowseSelection(now: now)
        previous.time = .day
        previous.personIDs = ["person"]
        previous.cityID = "los-angeles"
        let later = previous.committed(at: now.addingTimeInterval(60))
        XCTAssertEqual(previous.occurredBefore, now)
        XCTAssertEqual(later.occurredAfter, now.addingTimeInterval(60 - 86_400))
        XCTAssertEqual(later.occurredBefore, now.addingTimeInterval(60))
        XCTAssertEqual(later.personIDs, previous.personIDs)
        XCTAssertEqual(later.cityID, previous.cityID)
        XCTAssertFalse(previous.includes(event("new", personID: "person", offset: 30)))
        XCTAssertTrue(later.includes(event("new", personID: "person", offset: 30)))
    }

    func testSummaryAndCountsDescribeLocalRefinementsWithoutClaimingServerTotals() {
        var selection = LiveBrowseSelection(now: now)
        XCTAssertEqual(selection.activeFilterCount, 0)
        selection.scope = .nearby
        selection.cityID = "los-angeles"
        selection.radius = .twentyFiveKilometers
        selection.time = .day
        selection.personIDs = ["opaque-1", "opaque-2"]
        selection.categoryIDs = [WanderPlaceCategory.coffeeTeaSweets]
        XCTAssertEqual(selection.activeFilterCount, 4)
        XCTAssertTrue(selection.summary.contains("25 km"))
        XCTAssertTrue(selection.summary.contains("Los Angeles"))
        XCTAssertTrue(selection.summary.contains("2 people"))
        XCTAssertFalse(selection.summary.contains("opaque-1"))
    }

    private func event(_ id: String, personID: String = "person", place: VisiblePlace? = nil,
                       kind: FeedActivityKind = .listCreated, offset: TimeInterval = 0) -> FeedActivity {
        FeedActivity(id: id, kind: kind,
                     actor: ProfileShell(id: personID, handle: personID, displayName: personID,
                                         avatarURL: nil, bio: nil, relationship: .mutual),
                     place: place, occurredAt: now.addingTimeInterval(offset))
    }

    private func place(_ id: String, category: String = WanderPlaceCategory.coffeeTeaSweets,
                       latitude: Double = 34.05) -> VisiblePlace {
        let place = LocalPlace(localID: id, canonicalName: "Example place", category: category,
                               primaryCategory: category, categorySource: PlaceCategorySource.user.rawValue,
                               latitude: latitude, longitude: -118.24)
        let owner = LocalProfile(localID: "person", handle: "person", displayName: "Example person")
        return VisiblePlace(id: "save-\(id)", place: place,
                            userPlace: LocalUserPlace(localID: "save-\(id)", userID: owner.id, placeID: id,
                                                      status: .been, visibility: .mutuals, sourceType: "manual"),
                            owner: owner)
    }
}
