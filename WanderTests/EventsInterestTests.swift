import XCTest
@testable import Wander

@MainActor final class EventsInterestTests: XCTestCase {
    private let saved = EventsInterest(createdAt: Date(timeIntervalSince1970: 1789724400))

    func testAnalyticsEmitsOneConfirmationAndNoHydrationConversion() async {
        let analytics = InterestAnalyticsRecorder()
        let repository = InterestRepositoryDouble()
        let model = EventsInterestModel(cache: EventsInterestCache(defaults: nil))
        await model.load(userID: "private-owner", repository: repository)
        repository.shouldFail = true
        await model.register(repository: repository, analytics: analytics)
        repository.shouldFail = false
        await model.register(repository: repository, analytics: analytics)
        await model.register(repository: repository, analytics: analytics)
        await model.load(userID: "private-owner", repository: repository)
        XCTAssertEqual(analytics.events.map(\.name), [
            "events_interest_submitted", "events_interest_result", "events_interest_submitted", "events_interest_result"
        ])
        XCTAssertEqual(analytics.events.filter { $0.name == "events_interest_result" }.map { $0.properties["outcome"] }, ["failed", "confirmed"])
        XCTAssertFalse(analytics.events.flatMap { $0.properties.values }.contains("private-owner"))
    }

    func testAnalyticsDiscardsCompletionAfterAccountSwitch() async {
        let analytics = InterestAnalyticsRecorder()
        let repository = InterestRepositoryDouble()
        let model = EventsInterestModel(cache: EventsInterestCache(defaults: nil))
        await model.load(userID: "first", repository: repository)
        repository.suspendWrite = true
        let pending = Task { await model.register(repository: repository, analytics: analytics) }
        await repository.waitForWrite()
        await model.load(userID: "second", repository: InterestRepositoryDouble())
        repository.writeContinuation?.resume(returning: saved)
        await pending.value
        XCTAssertEqual(analytics.events.map(\.name), ["events_interest_submitted"])
    }

    func testConfirmedSignupIsAvailableBeforeColdStartLoadAndWorksOffline() async {
        let suite = "EventsInterestTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = InterestRepositoryDouble()
        let first = EventsInterestModel(cache: EventsInterestCache(defaults: defaults))
        await first.load(userID: "owner", repository: repository)
        await first.register(repository: repository)

        let reopened = EventsInterestModel(cache: EventsInterestCache(defaults: UserDefaults(suiteName: suite)!))
        XCTAssertEqual(reopened.presentation(for: "owner"), .registered)
        XCTAssertEqual(reopened.presentation(for: "other"), .unknown)
        XCTAssertEqual(reopened.presentation(for: nil), .unknown)
        repository.shouldFail = true
        let reads = repository.reads
        await reopened.load(userID: "owner", repository: repository)
        XCTAssertTrue(reopened.isRegistered)
        XCTAssertEqual(repository.reads, reads, "Confirmed signup must not wait for the server")
        await reopened.load(userID: "other", repository: repository)
        XCTAssertEqual(reopened.presentation(for: "other"), .unknown)
        XCTAssertFalse(reopened.isRegistered)
        XCTAssertEqual(reopened.presentation(for: "owner"), .registered)
    }

    func testUnknownStateStaysBlankUntilReadCompletesAndHydrationIsCached() async {
        let suite = "EventsInterestTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = InterestRepositoryDouble()
        repository.suspendRead = true
        let model = EventsInterestModel(cache: EventsInterestCache(defaults: defaults))
        XCTAssertEqual(model.presentation(for: "owner"), .unknown)
        let read = Task { await model.load(userID: "owner", repository: repository) }
        await repository.waitForRead()
        XCTAssertEqual(model.presentation(for: "owner"), .unknown)
        repository.readContinuation?.resume(returning: saved)
        await read.value
        let cold = EventsInterestModel(cache: EventsInterestCache(defaults: defaults))
        XCTAssertEqual(cold.presentation(for: "owner"), .registered)
    }

    func testFailedReadsAndWritesNeverCacheConfirmation() async {
        let suite = "EventsInterestTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = EventsInterestCache(defaults: defaults)
        let model = EventsInterestModel(cache: cache)
        let repository = InterestRepositoryDouble()
        repository.shouldFail = true
        await model.load(userID: "owner", repository: repository)
        XCTAssertEqual(model.presentation(for: "owner"), .unknown)
        await model.register(repository: repository)
        XCTAssertNil(cache.interest(for: "owner"))
        repository.shouldFail = false
        await model.load(userID: "owner", repository: repository)
        XCTAssertEqual(model.presentation(for: "owner"), .available)
        XCTAssertEqual(model.presentation(for: "other"), .unknown)
        XCTAssertNil(cache.interest(for: "owner"))
    }

    func testConfirmedRegistrationRestoresIntoNewScreenModel() async {
        let repository = InterestRepositoryDouble()
        repository.saved = saved
        let first = EventsInterestModel(cache: EventsInterestCache(defaults: nil))
        await first.load(userID: "owner", repository: repository)
        XCTAssertTrue(first.isRegistered)
        let reopened = EventsInterestModel(cache: EventsInterestCache(defaults: nil))
        await reopened.load(userID: "owner", repository: repository)
        XCTAssertEqual(reopened.interest, saved)
        await reopened.register(repository: repository)
        XCTAssertEqual(repository.writes, 0)
    }

    func testWhiteStateWaitsForServerAndRapidTapsOnlyWriteOnce() async {
        let repository = InterestRepositoryDouble()
        let model = EventsInterestModel(cache: EventsInterestCache(defaults: nil))
        await model.load(userID: "owner", repository: repository)
        repository.suspendWrite = true
        let pending = Task { await model.register(repository: repository) }
        await repository.waitForWrite()
        XCTAssertTrue(model.isSaving)
        XCTAssertFalse(model.isRegistered)
        await model.register(repository: repository)
        XCTAssertEqual(repository.writes, 1)
        repository.writeContinuation?.resume(returning: saved)
        await pending.value
        XCTAssertTrue(model.isRegistered)
        XCTAssertFalse(model.isSaving)
    }

    func testFailedSaveStaysOrangeAndCanRetry() async {
        let repository = InterestRepositoryDouble()
        let model = EventsInterestModel(cache: EventsInterestCache(defaults: nil))
        await model.load(userID: "owner", repository: repository)
        repository.shouldFail = true
        await model.register(repository: repository)
        XCTAssertFalse(model.isRegistered)
        XCTAssertFalse(model.isSaving)
        XCTAssertNotNil(model.errorMessage)
        repository.shouldFail = false
        await model.register(repository: repository)
        XCTAssertTrue(model.isRegistered)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(repository.writes, 2)
    }

    func testDelayedReadCannotUndoConfirmedTap() async {
        let repository = InterestRepositoryDouble()
        repository.suspendRead = true
        let model = EventsInterestModel(cache: EventsInterestCache(defaults: nil))
        let read = Task { await model.load(userID: "owner", repository: repository) }
        await repository.waitForRead()
        await model.register(repository: repository)
        repository.readContinuation?.resume(returning: nil)
        await read.value
        XCTAssertTrue(model.isRegistered)
        XCTAssertFalse(model.isLoading)
    }

    func testAccountSwitchDiscardsOldRead() async {
        let old = InterestRepositoryDouble()
        old.suspendRead = true
        let model = EventsInterestModel(cache: EventsInterestCache(defaults: nil))
        let read = Task { await model.load(userID: "first", repository: old) }
        await old.waitForRead()
        await model.load(userID: "second", repository: InterestRepositoryDouble())
        old.readContinuation?.resume(returning: saved)
        await read.value
        XCTAssertFalse(model.isRegistered)
    }

    func testSignOutDiscardsOldWriteAndPreventsNewWrites() async {
        let repository = InterestRepositoryDouble()
        let model = EventsInterestModel(cache: EventsInterestCache(defaults: nil))
        await model.load(userID: "owner", repository: repository)
        repository.suspendWrite = true
        let write = Task { await model.register(repository: repository) }
        await repository.waitForWrite()
        await model.load(userID: nil, repository: repository)
        repository.writeContinuation?.resume(returning: saved)
        await write.value
        XCTAssertFalse(model.isRegistered)
        XCTAssertFalse(model.isSaving)
        await model.register(repository: repository)
        XCTAssertEqual(repository.writes, 1)
    }

    func testFailedHydrationStillAllowsIdempotentRegistration() async {
        let repository = InterestRepositoryDouble()
        repository.shouldFail = true
        let model = EventsInterestModel(cache: EventsInterestCache(defaults: nil))
        await model.load(userID: "owner", repository: repository)
        XCTAssertFalse(model.isLoading)
        repository.shouldFail = false
        await model.register(repository: repository)
        XCTAssertTrue(model.isRegistered)
    }

    func testUnconfiguredBackendDoesNotPretendItSaved() async {
        let model = EventsInterestModel(cache: EventsInterestCache(defaults: nil))
        await model.load(userID: "owner", repository: nil)
        await model.register(repository: nil)
        XCTAssertFalse(model.isRegistered)
        XCTAssertNotNil(model.errorMessage)
    }

    func testRPCsUseSessionIdentityAndDecodeServerTimestamp() async throws {
        let rpc = InterestRPCDouble()
        let repository = SupabaseEventsInterestRepository(rpc: rpc)
        let absent = try await repository.currentInterest()
        XCTAssertNil(absent)
        rpc.response = #"[{"created_at":"2026-09-18T09:40:00.000Z"}]"#
        let result = try await repository.registerInterest()
        XCTAssertEqual(result, saved)
        XCTAssertEqual(rpc.names, ["own_events_launch_interest", "register_events_launch_interest"])
        XCTAssertEqual(rpc.parameters, ["{}", "{}"])
    }

    func testMissingRPCConfirmationIsFailure() async {
        let repository = SupabaseEventsInterestRepository(rpc: InterestRPCDouble())
        do {
            _ = try await repository.registerInterest()
            XCTFail("Empty response must not look successful")
        } catch {
            XCTAssertEqual(error as? WanderRemoteError,
                           .invalidResponse("Missing Events interest confirmation"))
        }
    }
}

@MainActor private final class InterestRepositoryDouble: EventsInterestRepository {
    var saved: EventsInterest?
    var shouldFail = false
    var suspendRead = false
    var suspendWrite = false
    var writes = 0
    var reads = 0
    var readContinuation: CheckedContinuation<EventsInterest?, Error>?
    var writeContinuation: CheckedContinuation<EventsInterest, Error>?

    func currentInterest() async throws -> EventsInterest? {
        reads += 1
        if shouldFail { throw URLError(.notConnectedToInternet) }
        if suspendRead {
            return try await withCheckedThrowingContinuation { readContinuation = $0 }
        }
        return saved
    }
    func registerInterest() async throws -> EventsInterest {
        writes += 1
        if shouldFail { throw URLError(.notConnectedToInternet) }
        if suspendWrite {
            return try await withCheckedThrowingContinuation { writeContinuation = $0 }
        }
        let result = saved ?? EventsInterest(createdAt: Date())
        saved = result
        return result
    }
    func waitForRead() async {
        for _ in 0..<1_000 where readContinuation == nil { await Task.yield() }
        XCTAssertNotNil(readContinuation)
    }
    func waitForWrite() async {
        for _ in 0..<1_000 where writeContinuation == nil { await Task.yield() }
        XCTAssertNotNil(writeContinuation)
    }
}

@MainActor private final class InterestRPCDouble: RemoteProcedureCalling {
    var response = "[]"
    var names: [String] = []
    var parameters: [String] = []
    func call<Value: Decodable, Params: Encodable>(
        _ name: String, params: Params, decoder: JSONDecoder
    ) async throws -> Value {
        names.append(name)
        parameters.append(String(decoding: try JSONEncoder().encode(params), as: UTF8.self))
        return try decoder.decode(Value.self, from: Data(response.utf8))
    }
}

private final class InterestAnalyticsRecorder: AnalyticsClient {
    var events: [AnalyticsEvent] = []
    func track(_ event: AnalyticsEvent) { events.append(event) }
    func identify(userID: String) {}
    func resetIdentity() {}
}
