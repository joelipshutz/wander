import XCTest
@testable import Wander

private actor DiscoveryContacts: ContactProvider {
    var status: ContactProviderAuthorization = .authorized
    var identifiers: [ContactDiscoveryIdentifier] = [.init(kind: .email, value: "friend@example.test")]
    var reads = 0
    func authorization() async -> ContactProviderAuthorization { status }
    func requestAccess() async -> ContactProviderAuthorization { status }
    func matches() async throws -> [ContactMatch] { [] }
    func discoveryIdentifiers() async throws -> [ContactDiscoveryIdentifier] { reads += 1; return identifiers }
    func setStatus(_ value: ContactProviderAuthorization) { status = value }
    func setIdentifiers(_ values: [ContactDiscoveryIdentifier]) { identifiers = values }
    func readCount() -> Int { reads }
}

@MainActor private final class DiscoveryRepository: ContactDiscoveryRepository {
    var enabled = false
    var writes: [Bool] = []
    var matchCalls = 0
    var shouldFail = false
    var results: [ProfileShell] = []
    var matchAction: (() async -> [ProfileShell])?
    func isEnabled() async throws -> Bool { enabled }
    func setEnabled(_ value: Bool) async throws {
        writes.append(value)
        if shouldFail { throw ContactDiscoveryError.unavailable }
        enabled = value
    }
    func match(_ identifiers: [ContactDiscoveryIdentifier], region: String?) async throws -> [ProfileShell] {
        matchCalls += 1
        if shouldFail { throw ContactDiscoveryError.unavailable }
        if let matchAction { return await matchAction() }
        return results
    }
}

@MainActor final class ContactDiscoveryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "ContactDiscoveryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    private func person(_ id: String, isPrivate: Bool = false) -> ProfileShell {
        ProfileShell(id: id, handle: id, displayName: id, avatarURL: nil, bio: nil,
            isPrivateProfile: isPrivate, relationship: .nonFollower)
    }
    func testExistingSystemPermissionDoesNotReadOrUploadWithoutNewConsent() async throws {
        let provider = DiscoveryContacts(); let repo = DiscoveryRepository()
        repo.enabled = true // Consent on another device must not authorize this address book.
        let service = ContactDiscoveryService(repository: repo, provider: provider, defaults: defaults, activeUserID: { "viewer" })
        let matches = try await service.matches(userID: "viewer")
        let reads = await provider.readCount()
        XCTAssertTrue(matches.isEmpty); XCTAssertEqual(reads, 0); XCTAssertEqual(repo.matchCalls, 0)
        XCTAssertFalse(service.hasConsent(userID: "viewer"))
    }
    func testConsentUsesAllowedIdentifiersAndFiltersSelfAndPrivateProfiles() async throws {
        let repo = DiscoveryRepository(); repo.results = [person("friend"), person("viewer"), person("private", isPrivate: true)]
        let service = ContactDiscoveryService(repository: repo, provider: DiscoveryContacts(), defaults: defaults, activeUserID: { "viewer" })
        try await service.enable(userID: "viewer")
        let matches = try await service.matches(userID: "viewer")
        XCTAssertEqual(matches.map(\.id), ["friend"]); XCTAssertEqual(repo.writes, [true])
        XCTAssertFalse(service.hasConsent(userID: "other"))
        let persisted = defaults.persistentDomain(forName: suite)!
        XCTAssertEqual(persisted.count, 1)
        XCTAssertTrue(persisted.values.allSatisfy { $0 is Bool })
    }
    func testDeniedPermissionDoesNotEnableOrRead() async {
        let provider = DiscoveryContacts(); await provider.setStatus(.denied)
        let repo = DiscoveryRepository()
        let service = ContactDiscoveryService(repository: repo, provider: provider, defaults: defaults, activeUserID: { "viewer" })
        do { try await service.enable(userID: "viewer"); XCTFail("Denied permission must fail") } catch {}
        let reads = await provider.readCount()
        XCTAssertEqual(reads, 0); XCTAssertTrue(repo.writes.isEmpty); XCTAssertFalse(service.hasConsent(userID: "viewer"))
    }
    func testRevocationClearsConsentAndServerIndexBeforeAnotherRead() async throws {
        let provider = DiscoveryContacts(); let repo = DiscoveryRepository()
        let service = ContactDiscoveryService(repository: repo, provider: provider, defaults: defaults, activeUserID: { "viewer" })
        try await service.enable(userID: "viewer"); await provider.setStatus(.denied)
        let results = try await service.matches(userID: "viewer"); let reads = await provider.readCount()
        XCTAssertTrue(results.isEmpty); XCTAssertEqual(reads, 0); XCTAssertEqual(repo.writes, [true, false])
        XCTAssertFalse(service.hasConsent(userID: "viewer"))
    }
    func testOfflineDisableSurvivesRestartAndRetriesWithoutReadingContacts() async throws {
        let provider = DiscoveryContacts(); let repo = DiscoveryRepository()
        let service = ContactDiscoveryService(repository: repo, provider: provider, defaults: defaults, activeUserID: { "viewer" })
        try await service.enable(userID: "viewer"); repo.shouldFail = true
        do { try await service.disable(userID: "viewer"); XCTFail("Expected failure") } catch {}
        XCTAssertFalse(service.hasConsent(userID: "viewer"))
        repo.shouldFail = false
        let restored = ContactDiscoveryService(repository: repo, provider: provider, defaults: defaults, activeUserID: { "viewer" })
        let results = try await restored.matches(userID: "viewer"); let reads = await provider.readCount()
        XCTAssertTrue(results.isEmpty); XCTAssertEqual(reads, 0); XCTAssertEqual(repo.writes, [true, false, false])
        XCTAssertFalse(repo.enabled)
    }
    func testEmptyLimitedSelectionProducesNoMatchRequest() async throws {
        let provider = DiscoveryContacts(); await provider.setIdentifiers([])
        let repo = DiscoveryRepository()
        let service = ContactDiscoveryService(repository: repo, provider: provider, defaults: defaults, activeUserID: { "viewer" })
        try await service.enable(userID: "viewer")
        let results = try await service.matches(userID: "viewer")
        XCTAssertTrue(results.isEmpty); XCTAssertEqual(repo.matchCalls, 0)
    }
    func testLateResultAfterDisableIsDiscarded() async throws {
        let repo = DiscoveryRepository(); let friend = person("friend")
        let started = expectation(description: "match started")
        var continuation: CheckedContinuation<[ProfileShell], Never>?
        repo.matchAction = { await withCheckedContinuation { continuation = $0; started.fulfill() } }
        let service = ContactDiscoveryService(repository: repo, provider: DiscoveryContacts(), defaults: defaults, activeUserID: { "viewer" })
        try await service.enable(userID: "viewer")
        let task = Task { try await service.matches(userID: "viewer") }
        await fulfillment(of: [started], timeout: 3)
        try await service.disable(userID: "viewer")
        continuation?.resume(returning: [friend])
        let results = try await task.value
        XCTAssertTrue(results.isEmpty)
    }
    func testAccountSwitchRejectsLateResults() async throws {
        let repo = DiscoveryRepository(); let friend = person("friend")
        let started = expectation(description: "match started")
        var activeID = "viewer"
        var continuation: CheckedContinuation<[ProfileShell], Never>?
        repo.matchAction = { await withCheckedContinuation { continuation = $0; started.fulfill() } }
        let service = ContactDiscoveryService(repository: repo, provider: DiscoveryContacts(), defaults: defaults, activeUserID: { activeID })
        try await service.enable(userID: "viewer")
        let task = Task { try await service.matches(userID: "viewer") }
        await fulfillment(of: [started], timeout: 3)
        activeID = "other"; continuation?.resume(returning: [friend])
        do { _ = try await task.value; XCTFail("Old account results must be rejected") } catch {}
        XCTAssertFalse(service.hasConsent(userID: "other"))
    }
    func testContactsRankBeforeGeneralAndDeduplicateWithoutFollowing() {
        let friend = person("friend"); let general = person("general")
        let result = PeopleRecommendationMerge.combine(contacts: [friend, friend], general: [
            .init(profile: general, reason: .followsYou, rank: 1), .init(profile: friend, reason: .suggested, rank: 2)
        ], limit: 20)
        XCTAssertEqual(result.map(\.id), ["friend", "general"])
        XCTAssertEqual(result.map(\.reason), [.contacts, .followsYou]); XCTAssertEqual(result.map(\.rank), [1, 2])
        XCTAssertEqual(PeopleRecommendationMerge.combine(contacts: [], general: result, limit: 1).count, 1)
    }
}
