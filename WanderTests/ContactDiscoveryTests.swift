import XCTest
@testable import Wander

private actor DiscoveryContacts: ContactProvider {
    var status: ContactProviderAuthorization = .authorized
    var identifiers: [ContactDiscoveryIdentifier] = [.init(kind: .email, value: "friend@example.test")]
    var reads = 0
    private var authorizationCalls = 0
    private var pauseCall: Int?
    private var paused: XCTestExpectation?
    private var authorizationContinuation: CheckedContinuation<ContactProviderAuthorization, Never>?
    func suspendAuthorization(call: Int, started: XCTestExpectation) { pauseCall = call; paused = started }
    func resumeAuthorization() { authorizationContinuation?.resume(returning: status); authorizationContinuation = nil }
    func authorization() async -> ContactProviderAuthorization {
        authorizationCalls += 1
        if authorizationCalls == pauseCall {
            return await withCheckedContinuation { authorizationContinuation = $0; paused?.fulfill() }
        }
        return status
    }
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
    var statusAction: (() async -> Bool)?
    var disableAction: (() async -> Void)?
    func isEnabled() async throws -> Bool { if let statusAction { return await statusAction() }; return enabled }
    func setEnabled(_ value: Bool) async throws {
        writes.append(value)
        if shouldFail { throw ContactDiscoveryError.unavailable }
        if !value, let disableAction { await disableAction() }
        enabled = value
    }
    func match(_ identifiers: [ContactDiscoveryIdentifier], region: String?) async throws -> [ProfileShell] {
        matchCalls += 1
        if shouldFail { throw ContactDiscoveryError.unavailable }
        if let matchAction { return await matchAction() }
        return results
    }
}

@MainActor private final class RankedDiscoveryRepository: ProfileRepository, FollowRepository {
    var receivedContactIDs: [String] = []
    var receivedLimit: Int?
    var ranked: [DiscoverPeopleRecommendation] = []
    var general: [DiscoverPeopleRecommendation] = []
    var rankedAction: (() async throws -> [DiscoverPeopleRecommendation])?
    var generalReads = 0
    var followWrites = 0
    func currentProfile() async throws -> LocalProfile? { nil }
    func profile(id: String) async throws -> ProfileViewState { throw ContactDiscoveryError.unavailable }
    func searchProfiles(handleQuery: String) async throws -> [ProfileShell] { [] }
    func rankedPeopleRecommendations(contactIDs: [String], limit: Int) async throws -> [DiscoverPeopleRecommendation] {
        receivedContactIDs = contactIDs; receivedLimit = limit
        if let rankedAction { return try await rankedAction() }
        return ranked
    }
    func discoverProfileRecommendations(limit: Int) async throws -> [DiscoverPeopleRecommendation] {
        generalReads += 1; return general
    }
    func follow(userID: String) async throws { followWrites += 1 }
    func unfollow(userID: String) async throws { followWrites += 1 }
    func followers(userID: String) async throws -> [ProfileShell] { [] }
    func following(userID: String) async throws -> [ProfileShell] { [] }
    func relationship(to userID: String) async throws -> ViewerRelationship { .nonFollower }
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
    func testAccountSwitchDuringAuthorizationPreventsUpload() async throws {
        let provider = DiscoveryContacts(); let repo = DiscoveryRepository()
        let started = expectation(description: "upload authorization suspended")
        await provider.suspendAuthorization(call: 2, started: started)
        var activeID = "viewer"
        let service = ContactDiscoveryService(repository: repo, provider: provider, defaults: defaults, activeUserID: { activeID })
        try await service.enable(userID: "viewer")
        let task = Task { try await service.matches(userID: "viewer") }
        await fulfillment(of: [started], timeout: 3)
        activeID = "other"; await provider.resumeAuthorization()
        do { _ = try await task.value; XCTFail("Account changed before upload") } catch {}
        XCTAssertEqual(repo.matchCalls, 0)
    }
    func testDisableDuringFinalAuthorizationDiscardsResults() async throws {
        let provider = DiscoveryContacts(); let repo = DiscoveryRepository(); repo.results = [person("friend")]
        let started = expectation(description: "result authorization suspended")
        await provider.suspendAuthorization(call: 3, started: started)
        let service = ContactDiscoveryService(repository: repo, provider: provider, defaults: defaults, activeUserID: { "viewer" })
        try await service.enable(userID: "viewer")
        let task = Task { try await service.matches(userID: "viewer") }
        await fulfillment(of: [started], timeout: 3)
        try await service.disable(userID: "viewer"); await provider.resumeAuthorization()
        let results = try await task.value
        XCTAssertTrue(results.isEmpty)
    }
    func testDisableDuringResultEligibilityCheckRejectsResults() async throws {
        let provider = DiscoveryContacts(); let repo = DiscoveryRepository()
        let started = expectation(description: "eligibility authorization suspended")
        await provider.suspendAuthorization(call: 1, started: started)
        let service = ContactDiscoveryService(repository: repo, provider: provider, defaults: defaults, activeUserID: { "viewer" })
        try await service.enable(userID: "viewer")
        let task = Task { await service.canUseResults(userID: "viewer") }
        await fulfillment(of: [started], timeout: 3)
        try await service.disable(userID: "viewer"); await provider.resumeAuthorization()
        let permitted = await task.value
        XCTAssertFalse(permitted)
    }
    func testStaleDisabledStatusCannotUndoNewConsent() async throws {
        let repo = DiscoveryRepository()
        let started = expectation(description: "status suspended")
        var continuation: CheckedContinuation<Bool, Never>?
        repo.statusAction = { await withCheckedContinuation { continuation = $0; started.fulfill() } }
        let service = ContactDiscoveryService(repository: repo, provider: DiscoveryContacts(), defaults: defaults, activeUserID: { "viewer" })
        let task = Task { try await service.reconcile(userID: "viewer") }
        await fulfillment(of: [started], timeout: 3)
        try await service.enable(userID: "viewer")
        continuation?.resume(returning: false)
        let enabled = try await task.value
        XCTAssertTrue(enabled); XCTAssertTrue(service.hasConsent(userID: "viewer"))
    }
    func testChangedContactSelectionInvalidatesPendingMatch() async throws {
        let repo = DiscoveryRepository(); let friend = person("removed")
        let started = expectation(description: "match suspended")
        var continuation: CheckedContinuation<[ProfileShell], Never>?
        repo.matchAction = { await withCheckedContinuation { continuation = $0; started.fulfill() } }
        let service = ContactDiscoveryService(repository: repo, provider: DiscoveryContacts(), defaults: defaults, activeUserID: { "viewer" })
        try await service.enable(userID: "viewer")
        let task = Task { try await service.matches(userID: "viewer") }
        await fulfillment(of: [started], timeout: 3)
        service.invalidateContactAccess(); continuation?.resume(returning: [friend])
        let results = try await task.value
        XCTAssertTrue(results.isEmpty)
    }
    func testDuplicateDisableIsCoalescedAndReenableWaitsForIt() async throws {
        let repo = DiscoveryRepository()
        let started = expectation(description: "disable suspended")
        var continuation: CheckedContinuation<Void, Never>?
        repo.disableAction = { await withCheckedContinuation { continuation = $0; started.fulfill() } }
        let service = ContactDiscoveryService(repository: repo, provider: DiscoveryContacts(), defaults: defaults, activeUserID: { "viewer" })
        try await service.enable(userID: "viewer")
        let first = Task { try await service.disable(userID: "viewer") }
        await fulfillment(of: [started], timeout: 3)
        let second = Task { try await service.matches(userID: "viewer") }
        let enable = Task { try await service.enable(userID: "viewer") }
        await Task.yield()
        XCTAssertEqual(repo.writes, [true, false])
        continuation?.resume()
        try await first.value; _ = try await second.value; try await enable.value
        XCTAssertEqual(repo.writes, [true, false, true])
        XCTAssertTrue(repo.enabled); XCTAssertTrue(service.hasConsent(userID: "viewer"))
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

    func testBackendPreservesCombinedRankingAndPassesOnlyPermittedContactIDs() async throws {
        let contacts = DiscoveryRepository(); contacts.results = [person("friend")]
        let service = ContactDiscoveryService(repository: contacts, provider: DiscoveryContacts(), defaults: defaults, activeUserID: { "viewer" })
        try await service.enable(userID: "viewer")
        let profiles = RankedDiscoveryRepository()
        profiles.ranked = [.init(profile: person("curated"), reason: .suggested, rank: 1),
            .init(profile: person("friend"), reason: .contacts, rank: 2),
            .init(profile: person("local"), reason: .nearby, rank: 3)]
        let backend = WanderBackend(profileRepository: profiles, contactDiscovery: service, followRepository: profiles)
        let result = try await backend.peopleRecommendations(userID: "viewer", limit: 12)
        XCTAssertEqual(result, profiles.ranked)
        XCTAssertEqual(profiles.receivedContactIDs, ["friend"])
        XCTAssertEqual(profiles.receivedLimit, 12)
        XCTAssertEqual(profiles.generalReads, 0)
        XCTAssertEqual(profiles.followWrites, 0)
    }

    func testBackendRankingFailureFallsBackToContactsAndGeneralWithoutFollowing() async throws {
        let contacts = DiscoveryRepository(); contacts.results = [person("friend")]
        let service = ContactDiscoveryService(repository: contacts, provider: DiscoveryContacts(), defaults: defaults, activeUserID: { "viewer" })
        try await service.enable(userID: "viewer")
        let profiles = RankedDiscoveryRepository()
        profiles.rankedAction = { throw ContactDiscoveryError.unavailable }
        profiles.general = [.init(profile: person("general"), reason: .followsYou, rank: 1),
            .init(profile: person("friend"), reason: .suggested, rank: 2)]
        let backend = WanderBackend(profileRepository: profiles, contactDiscovery: service, followRepository: profiles)
        let result = try await backend.peopleRecommendations(userID: "viewer")
        XCTAssertEqual(result.map(\.id), ["friend", "general"])
        XCTAssertEqual(result.map(\.reason), [.contacts, .followsYou])
        XCTAssertEqual(profiles.generalReads, 1)
        XCTAssertEqual(profiles.followWrites, 0)
    }

    func testBackendRevocationDuringRankingDiscardsContactResults() async throws {
        let contacts = DiscoveryRepository(); contacts.results = [person("friend")]
        let provider = DiscoveryContacts()
        let service = ContactDiscoveryService(repository: contacts, provider: provider, defaults: defaults, activeUserID: { "viewer" })
        try await service.enable(userID: "viewer")
        let profiles = RankedDiscoveryRepository()
        let started = expectation(description: "ranking suspended")
        var continuation: CheckedContinuation<[DiscoverPeopleRecommendation], Never>?
        profiles.rankedAction = { await withCheckedContinuation { continuation = $0; started.fulfill() } }
        let backend = WanderBackend(profileRepository: profiles, contactDiscovery: service, followRepository: profiles)
        let task = Task { try await backend.peopleRecommendations(userID: "viewer") }
        await fulfillment(of: [started], timeout: 3)
        await provider.setStatus(.denied)
        continuation?.resume(returning: [.init(profile: person("friend"), reason: .contacts, rank: 1),
            .init(profile: person("local"), reason: .nearby, rank: 2)])
        let result = try await task.value
        XCTAssertEqual(result.map(\.id), ["local"])
        XCTAssertEqual(profiles.followWrites, 0)
    }
}
