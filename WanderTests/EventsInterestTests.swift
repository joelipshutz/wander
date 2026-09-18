import XCTest
@testable import Wander

@MainActor final class EventsInterestTests: XCTestCase {
    private let saved = EventsInterest(createdAt: Date(timeIntervalSince1970: 1789724400))

    func testConfirmedRegistrationRestoresIntoNewScreenModel() async {
        let repository = InterestRepositoryDouble()
        repository.saved = saved
        let first = EventsInterestModel()
        await first.load(userID: "owner", repository: repository)
        XCTAssertTrue(first.isRegistered)
        let reopened = EventsInterestModel()
        await reopened.load(userID: "owner", repository: repository)
        XCTAssertEqual(reopened.interest, saved)
        await reopened.register(repository: repository)
        XCTAssertEqual(repository.writes, 0)
    }

    func testWhiteStateWaitsForServerAndRapidTapsOnlyWriteOnce() async {
        let repository = InterestRepositoryDouble()
        let model = EventsInterestModel()
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
        let model = EventsInterestModel()
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
        let model = EventsInterestModel()
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
        let model = EventsInterestModel()
        let read = Task { await model.load(userID: "first", repository: old) }
        await old.waitForRead()
        await model.load(userID: "second", repository: InterestRepositoryDouble())
        old.readContinuation?.resume(returning: saved)
        await read.value
        XCTAssertFalse(model.isRegistered)
    }

    func testSignOutDiscardsOldWriteAndPreventsNewWrites() async {
        let repository = InterestRepositoryDouble()
        let model = EventsInterestModel()
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
        let model = EventsInterestModel()
        await model.load(userID: "owner", repository: repository)
        XCTAssertFalse(model.isLoading)
        repository.shouldFail = false
        await model.register(repository: repository)
        XCTAssertTrue(model.isRegistered)
    }

    func testUnconfiguredBackendDoesNotPretendItSaved() async {
        let model = EventsInterestModel()
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
    var readContinuation: CheckedContinuation<EventsInterest?, Error>?
    var writeContinuation: CheckedContinuation<EventsInterest, Error>?

    func currentInterest() async throws -> EventsInterest? {
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
