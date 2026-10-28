#if DEBUG && targetEnvironment(simulator)
import XCTest
@testable import Wander

@MainActor
final class LiveTotemUITestFixtureTests: XCTestCase {
    func testReviewFixtureRequiresAllIsolationArguments() {
        let arguments = ["-WanderLiveTotemUITest", "-WanderAuthenticatedUITest",
                         "-WanderUseDemoFixtures", "-WanderUnifiedLiveUITest"]
        XCTAssertTrue(LiveTotemUITestFixtures.isEnabled(arguments: arguments))
        for argument in arguments {
            XCTAssertFalse(LiveTotemUITestFixtures.isEnabled(arguments: arguments.filter { $0 != argument }))
        }
        XCTAssertFalse(LiveTotemUITestFixtures.isEnabled(arguments: []))
    }

    func testReviewExercisesRealMembershipWithoutFabricatingSavedStatusOrDuplicatePins() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = WanderStore(fixtures: LiveTotemUITestFixtures.fixtures(base: .seed(), now: now))
        let page = LiveTotemUITestFixtures.feedPage(store: store, now: now)
        let query = LiveFeedQuery(occurredBefore: now)
        let pins = LiveMapProjection.pins(activities: page.activity, featured: store.visiblePlaces(),
            totemContext: store.liveTotemContext(query: query, currentStateIsComplete: true))
        XCTAssertEqual(pins.count, 8)
        XCTAssertEqual(Set(pins.map(\.id)).count, pins.count)
        let list = try XCTUnwrap(pins.first { $0.id == "totem_list" })
        XCTAssertTrue(list.totemState.hasListMembership)
        XCTAssertFalse(list.totemState.hasSavedStatus)
        XCTAssertTrue(list.totemState.rails.isEmpty)
        let featured = try XCTUnwrap(pins.first { $0.id == "totem_featured" })
        XCTAssertTrue(featured.totemState.isFeatured)
        let featuredList = try XCTUnwrap(pins.first { $0.id == "totem_featured_list" })
        XCTAssertTrue(featuredList.totemState.hasListMembership)
        XCTAssertFalse(featuredList.totemState.isFeatured)
        let wanna = try XCTUnwrap(pins.first { $0.id == "totem_tacos" })
        XCTAssertFalse(wanna.totemState.isFeatured)
        XCTAssertEqual(wanna.totemState.rails, [.init(ownership: .currentUser, status: .wannaGo)])

        let day = LiveFeedQuery(occurredAfter: now.addingTimeInterval(-86_400), occurredBefore: now)
        let filtered = LiveMapProjection.pins(activities: page.activity.filter(day.includes), featured: [],
            totemContext: store.liveTotemContext(query: day, currentStateIsComplete: true), previousPins: pins)
        let coffee = try XCTUnwrap(filtered.first { $0.id == "totem_coffee" })
        XCTAssertTrue(coffee.totemState.hasListMembership, "A 90-day-old membership survives a 24-hour activity filter.")
        XCTAssertEqual(filtered.filter { $0.identity.matches(list.place.place) }.count, 1)
    }
}
#endif
