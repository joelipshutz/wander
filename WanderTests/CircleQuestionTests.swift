import XCTest
@testable import Wander

@MainActor final class CircleQuestionTests: XCTestCase {
    func testRemoteRepositoryUsesAuthenticatedRPCAndDecodesServerShape() async throws {
        let transport = CircleQuestionTransport()
        let repository = SupabaseCircleQuestionRepository(rpc: transport)
        let result = try await repository.publish(CircleQuestionReviewRepository.sample.draft)
        XCTAssertEqual(transport.procedure, "circle_question_publish")
        XCTAssertEqual(Set(try XCTUnwrap(transport.parameters).keys), ["input_draft"])
        XCTAssertEqual(result.author.name, "Question owner")
        XCTAssertEqual(result.draft.topic, "everything")
        XCTAssertEqual(result.replies.first?.places.first?.note, "Try the patio")
        XCTAssertEqual(result.createdAt, ISO8601DateFormatter().date(from: "2026-11-03T12:00:00Z"))
    }
    func testAnalyticsAcknowledgesOnceAndCarriesNoContent() async {
        let state = CircleQuestionStore(repository: CircleQuestionReviewRepository())
        let recorder = CircleQuestionAnalyticsRecorder(); state.analytics = recorder
        state.reset(userID: "one")
        let draft = CircleQuestionReviewRepository.sample.draft
        _ = await state.perform(event: .posted, requestID: draft.id) { try await $0.publish(draft) }
        _ = await state.perform(event: .posted, requestID: draft.id) { try await $0.publish(draft) }
        XCTAssertEqual(recorder.events.count, 2)
        XCTAssertTrue(recorder.events[0].properties.isEmpty)
        XCTAssertEqual(Set(recorder.events[1].properties.keys), ["need", "action", "surface"])
    }
    func testQuestionLinksAndPushesUseValidatedQuestionRoute() {
        let id = "eeecc001-0000-4000-8000-000000000001"
        XCTAssertEqual(WanderDeepLinkRoute.parse(URL(string: "recme://questions/\(id)")!), .sharedQuestion(questionID: id))
        XCTAssertNil(WanderDeepLinkRoute.parse(URL(string: "recme://questions/not-a-uuid")!))
        XCTAssertEqual(PushNotificationManager.destination(from: URL(string: "recme://questions/\(id)")!), .question(id: id))
    }
    func testEverythingClearsSubcategories() {
        var draft = CircleQuestionReviewRepository.sample.draft
        draft.selectEverything()
        XCTAssertEqual(draft.topic, "everything")
        XCTAssertTrue(draft.subcategories.isEmpty)
    }
    func testRemovingCategoryRemovesItsSubcategories() {
        var draft = CircleQuestionReviewRepository.sample.draft
        draft.toggleCategory(WanderPlaceCategory.coffeeTeaSweets)
        XCTAssertTrue(draft.subcategories.isEmpty)
    }
    func testStealthCannotPostWithoutRecipients() {
        var draft = CircleQuestionReviewRepository.sample.draft
        XCTAssertTrue(draft.isValid)
        draft.stealth = true
        XCTAssertFalse(draft.isValid)
        draft.audience = .people; draft.recipientIDs = ["maya"]
        XCTAssertTrue(draft.isValid)
    }
    func testDurationAndCoordinatesAreBounded() {
        var draft = CircleQuestionReviewRepository.sample.draft
        for days in [0, 31] { draft.days = days; XCTAssertFalse(draft.isValid) }
        draft.days = 30; XCTAssertTrue(draft.isValid)
        draft.area?.latitude = .nan; XCTAssertFalse(draft.isValid)
    }
    func testPinExpirationDoesNotRemoveConversation() {
        let question = CircleQuestionReviewRepository.sample
        XCTAssertTrue(question.isOnMap(at: question.expiresAt.addingTimeInterval(-1)))
        XCTAssertFalse(question.isOnMap(at: question.expiresAt))
        XCTAssertFalse(question.draft.headline.isEmpty)
    }
    func testBasketDeduplicatesAcrossSearchAndListsWithoutLosingNotes() {
        var basket = CircleQuestionBasket()
        let search = CircleQuestionPlace(id: "mapkit", name: "Cafe", detail: "Main St", latitude: 34, longitude: -118)
        var saved = search; saved.id = "saved-place"
        basket.toggle(search); basket.setNote("Try the patio", for: search.selectionKey)
        basket.selectAll([saved, saved])
        XCTAssertEqual(basket.places.count, 1)
        XCTAssertEqual(basket.places[0].note, "Try the patio")
        basket.toggle(saved); XCTAssertTrue(basket.places.isEmpty)
    }
    func testMissingRepositoryKeepsDraftAndNeverPretendsToPublish() async {
        let state = CircleQuestionStore()
        state.reset(userID: "one")
        let success = await state.perform { try await $0.publish(CircleQuestionReviewRepository.sample.draft) }
        XCTAssertFalse(success); XCTAssertTrue(state.items.isEmpty); XCTAssertNotNil(state.message)
    }
    func testAccountSwitchClearsQuestionContent() async {
        let state = CircleQuestionStore(repository: CircleQuestionReviewRepository())
        await state.load(userID: "one"); XCTAssertFalse(state.items.isEmpty)
        state.reset(userID: "two"); XCTAssertTrue(state.items.isEmpty)
    }
    func testRetryDoesNotDuplicateRecommendations() async throws {
        let repository = CircleQuestionReviewRepository()
        let id = repository.items[0].id; let request = UUID()
        _ = try await repository.reply(questionID: id, clientID: request, places: [], note: "Try the patio")
        let result = try await repository.reply(questionID: id, clientID: request, places: [], note: "Try the patio")
        XCTAssertEqual(result.replies.count, 1)
    }
}

@MainActor private final class CircleQuestionTransport: RemoteProcedureCalling {
    var procedure = ""
    var parameters: [String: Any]?
    func call<Value: Decodable, Params: Encodable>(_ name: String, params: Params, decoder: JSONDecoder) async throws -> Value {
        procedure = name
        parameters = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any]
        let payload = #"{"draft":{"id":"eeecc001-0000-4000-8000-000000000001","categories":[],"subcategories":[],"area":{"name":"Santa Monica","detail":"California, US","latitude":34.01,"longitude":-118.49,"city":"Santa Monica"},"note":"A quiet patio","audience":"people","recipientIDs":[],"stealth":false,"days":7},"author":{"id":"owner","name":"Question owner","isFriend":false},"createdAt":"2026-11-03T12:00:00.000000+00:00","expiresAt":"2026-11-10T12:00:00+00:00","likes":1,"liked":true,"replies":[{"id":"eeecc001-0000-4000-8000-000000000003","author":{"id":"friend","name":"Friend","isFriend":true},"note":"A favorite","places":[{"id":"cafe","name":"Cafe","detail":"Main St","latitude":34,"longitude":-118,"note":"Try the patio"}],"createdAt":"2026-11-03T13:00:00+00:00"}]}"#
        return try decoder.decode(Value.self, from: Data(payload.utf8))
    }
}

private final class CircleQuestionAnalyticsRecorder: AnalyticsClient {
    var events: [AnalyticsEvent] = []
    func track(_ event: AnalyticsEvent) { events.append(event) }
    func identify(userID: String) {}
    func resetIdentity() {}
}
