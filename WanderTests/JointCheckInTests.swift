import XCTest
@testable import Wander

@MainActor
final class JointCheckInTests: XCTestCase {
    private let groupID = "e5660000-0000-0000-0000-000000000001"
    private let eventID = "e5660000-0000-0000-0000-000000000002"

    func testProfileSubjectMovesFirstWithoutChangingConversationOrRoster() throws {
        let group = try projection(count: 3)
        XCTAssertEqual(group.ordered(for: "person-2").map(\.person.id), ["person-2", "person-0", "person-1"])
        XCTAssertEqual(group.ordered(for: "hidden-person").map(\.person.id), group.contributions.map(\.person.id))
        XCTAssertEqual(group.canonicalActivityID, eventID)
        XCTAssertEqual(group.attribution(for: "person-2"), "Person 2, Person 0 and 1 other checked in")
    }

    func testOneTwoAndTenContributorsUseOnlyReadablePeople() throws {
        XCTAssertEqual(try projection(count: 1).attribution(), "Person 0 checked in")
        XCTAssertEqual(try projection(count: 2).attribution(), "Person 0 and Person 1 checked in")
        XCTAssertEqual(try projection(count: 10).contributions.count, 10)
        XCTAssertThrowsError(try projection(count: 0))
        XCTAssertThrowsError(try projection(count: 11))
    }

    func testMalformedV2NeverFallsBackToSoloContent() throws {
        var json = fixture(count: 2)
        json["model_version"] = 3
        XCTAssertThrowsError(try decode(json).projection())
        json = fixture(count: 2)
        var people = try XCTUnwrap(json["contributions"] as? [[String: Any]])
        people[1]["participant_id"] = people[0]["participant_id"]
        json["contributions"] = people
        XCTAssertThrowsError(try decode(json).projection())
        json["canonical_activity_id"] = "bad-id"
        XCTAssertThrowsError(try decode(json).projection())
    }

    func testNullRatingAndNoteStayUnratedAndBlank() throws {
        let group = try projection(count: 2)
        XCTAssertNil(group.contributions[0].rating)
        XCTAssertNil(group.contributions[0].note)
        XCTAssertEqual(group.contributions[1].rating, 4.5)
        XCTAssertEqual(group.contributions[1].note, "Own note 1")
    }

    func testJointEventCannotBeAbsorbedIntoNearbyWannaOrListActivity() throws {
        let group = try projection(count: 2)
        let actor = group.contributions[0].person
        let place = LocalPlace(localID: "place", canonicalName: "Fictional Cafe", category: "coffee", latitude: 34, longitude: -118)
        let save = LocalUserPlace(localID: "save", userID: actor.id, placeID: place.id, status: .been, visibility: .followers, sourceType: "manual")
        let visible = VisiblePlace(id: save.id, place: place, userPlace: save,
            owner: LocalProfile(localID: actor.id, handle: "person0", displayName: "Person 0"))
        let date = Date.now.addingTimeInterval(-60)
        let joint = FeedActivity(id: eventID, kind: .placeBeen, actor: actor, place: visible, occurredAt: date, jointCheckIn: group)
        let wanna = FeedActivity(id: "wanna", kind: .placeWannaGo, actor: actor, place: visible, occurredAt: date)
        XCTAssertEqual(FeedPresentation.groupedActivity([joint, wanna]).count, 2)
    }

    func testContextsRejectMappingToHiddenOrDifferentVisit() throws {
        let group = fixture(count: 1)
        let data = try JSONSerialization.data(withJSONObject: ["groups": [group], "mappings": [["visit_id": UUID().uuidString, "group_id": groupID]]])
        let response = try RemoteDecoding.decoder.decode(RemoteJointCheckInContextsDTO.self, from: data)
        XCTAssertThrowsError(try response.contexts())
    }

    func testMediaAttributionDoesNotCopyAnotherPersonsPhoto() throws {
        let dto = try decode(fixture(count: 2))
        let mine = RemoteFeedMediaDTO(id: "mine", urlString: "https://example.com/own.jpg", storageBucket: nil, storagePath: nil,
            accessibilityLabel: "Own photo", participantID: dto.contributions[1].participantID)
        let group = try dto.projection(sourceMedia: [mine], renderedMedia: [FeedMediaPreview(id: "mine", urlString: "https://example.com/own.jpg", accessibilityLabel: "Own photo")])
        XCTAssertTrue(group.contributions[0].media.isEmpty)
        XCTAssertEqual(group.contributions[1].media.map(\.id), ["mine"])
    }

    func testJointShareExportsOnlyTheVenueIdentity() throws {
        let group = try projection(count: 2)
        let placeID = "e5660000-0000-0000-0000-000000000003"
        let context = ActivityEngagementContext(activityID: eventID, actor: group.contributions[0].person,
            placeName: "Fictional Cafe", placeServerID: placeID, placeDetail: "Coffee · Seattle",
            status: .been, occurredAt: group.occurredAt, note: "Private to this audience", rating: 4.5,
            jointCheckIn: group)
        let presentation = try XCTUnwrap(ActivitySharePreviewPresentation(context: context))
        XCTAssertEqual(presentation.content, WanderShareContent.place(serverID: placeID,
            name: context.placeName, message: context.shareMessage))
        XCTAssertEqual(context.shareCard.kind, .place)
        XCTAssertEqual(context.shareCard.ownerName, "")
        XCTAssertNil(context.shareCard.date)
        XCTAssertFalse(presentation.content.message.contains("Person"))
        XCTAssertFalse(presentation.content.message.contains("Private"))
        XCTAssertFalse(presentation.content.item.absoluteString.contains(eventID))
    }

    func testCapabilityFallbackRequiresExactMissingRPC() async throws {
        let rpc = JointReadProbe()
        rpc.failure = .invalidResponse("PGRST202 public.new_projection missing")
        let value: JointProbeValue = try await rpc.versionedRead("new_projection", legacy: "legacy_projection", params: JointProbeValue(value: 1))
        XCTAssertEqual(value.value, 2)
        XCTAssertEqual(rpc.calls, ["new_projection", "legacy_projection"])
        for failure in ["401 not_authenticated", "PGRST202 public.another_function missing", "bad JSON", "network timeout"] {
            rpc.calls = []
            rpc.failure = .invalidResponse(failure)
            do {
                let _: JointProbeValue = try await rpc.versionedRead("new_projection", legacy: "legacy_projection", params: JointProbeValue(value: 1))
                XCTFail("Unexpected downgrade")
            } catch { XCTAssertEqual(rpc.calls, ["new_projection"]) }
        }
        rpc.calls = []
        rpc.failure = .invalidResponse("RPC new_projection failed with 400: {\"code\":\"42883\",\"message\":\"function app.internal_helper() does not exist\",\"details\":\"SQL function new_projection\"}")
        do {
            let _: JointProbeValue = try await rpc.versionedRead("new_projection", legacy: "legacy_projection", params: JointProbeValue(value: 1))
            XCTFail("A broken deployed RPC must not downgrade to a different audience")
        } catch { XCTAssertEqual(rpc.calls, ["new_projection"]) }
    }

    func testKnownV2IdentityNeverUsesLegacyFallback() async {
        let rpc = JointReadProbe()
        rpc.failure = .invalidResponse("42883 new_projection missing")
        do {
            let _: JointProbeValue = try await rpc.versionedRead("new_projection", legacy: "legacy_projection", params: JointProbeValue(value: 1), allowsLegacy: false)
            XCTFail("Unexpected downgrade")
        } catch { XCTAssertEqual(rpc.calls, ["new_projection"]) }
    }

    func testFrozenCreateIsDurableAndCannotBeReplacedOrEditedWhilePending() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "person-0", displayName: "Person 0", handle: "person0")))
        store.setPrivateProfile(false)
        let result = store.saveCandidate(PlaceCandidate(id: "fictional-cafe", name: "Fictional Cafe", category: "coffee", latitude: 34, longitude: -118, confidence: 1),
            status: .been, visibility: .followers, note: "Original own note", sourceType: .manual)
        let visit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)
        XCTAssertTrue(store.queueJointCheckIn(sourceVisitID: visit.id, inviteeUserIDs: ["person-1"]))
        let original = try XCTUnwrap(store.pendingSharedVisitInvites.first)
        XCTAssertTrue(store.queueJointCheckIn(sourceVisitID: visit.id, inviteeUserIDs: ["person-2"]))
        XCTAssertEqual(store.pendingSharedVisitInvites, [original])
        XCTAssertNil(store.updateVisit(visitID: visit.id, note: "Changed after send", replacesNote: true))
        XCTAssertTrue(store.sharedVisitCompanions(for: visit.id).isEmpty, "Pending invitations are never accepted faces")
        let data = try JSONEncoder().encode(WanderStoreSnapshot(store: store))
        let snapshot = try JSONDecoder().decode(WanderStoreSnapshot.self, from: data)
        XCTAssertEqual(snapshot.pendingSharedVisitInvites, [original])
    }

    func testLegacyOutboxDecodesWithoutAnyV2Intent() throws {
        let json = """
        {"id":"old","ownerUserID":"owner","sourceVisitID":"visit","inviteeUserIDs":["friend"],"createdAt":0}
        """
        let value = try JSONDecoder().decode(PendingSharedVisitInvite.self, from: Data(json.utf8))
        XCTAssertNil(value.jointMutation)
        XCTAssertNil(value.requiresReview)
    }

    func testFailedContextRefreshRedactsPeopleWithoutTurningKnownJointIntoSolo() async throws {
        let group = try projection(count: 2)
        let visitID = group.contributions[0].visitID
        let repository = JointContextProbe()
        repository.result = JointCheckInContexts(mappings: [visitID: groupID], groups: [groupID: group])
        let backend = WanderBackend(sharedVisitRepository: repository)
        let store = WanderStore(fixtures: .empty())
        await store.refreshJointCheckInContexts(visitIDs: [visitID], backend: backend)
        XCTAssertEqual(store.jointCheckIn(for: visitID), group)
        repository.fails = true
        await store.refreshJointCheckInContexts(visitIDs: [visitID], backend: backend)
        XCTAssertNil(store.jointCheckIn(for: visitID), "Do not retain names, notes or photos after failed reauthorization")
        XCTAssertEqual(store.unavailableJointActivityID(for: visitID), eventID, "Keep only identity so the UI cannot imply a solo thread")
        repository.fails = false
        repository.result = JointCheckInContexts(mappings: [:], groups: [:], isSupported: false)
        await store.refreshJointCheckInContexts(visitIDs: [visitID], backend: backend)
        XCTAssertEqual(store.unavailableJointActivityID(for: visitID), eventID, "Missing support cannot downgrade a known v2 identity")
        repository.result = JointCheckInContexts(mappings: [:], groups: [:])
        await store.refreshJointCheckInContexts(visitIDs: [visitID], backend: backend)
        XCTAssertNil(store.unavailableJointActivityID(for: visitID), "A successful absent mapping confirms detachment")
    }

    func testColdRestartKeepsSharedIdentityWithoutRestoringOtherPeoplesContent() async throws {
        let group = try projection(count: 2)
        let visitID = group.contributions[0].visitID
        let repository = JointContextProbe()
        repository.result = JointCheckInContexts(mappings: [visitID: groupID], groups: [groupID: group])
        var saved: WanderStoreSnapshot?
        let persistence = WanderStorePersistence(load: { saved }, save: { saved = $0 })
        let store = WanderStore(fixtures: .empty(), persistence: persistence)
        store.apply(authState: .signedIn(AuthSession(userID: "person-0", displayName: "Person 0", handle: "person0")))
        await store.refreshJointCheckInContexts(visitIDs: [visitID], backend: WanderBackend(sharedVisitRepository: repository))
        let encoded = try JSONEncoder().encode(XCTUnwrap(saved))
        let restoredSnapshot = try JSONDecoder().decode(WanderStoreSnapshot.self, from: encoded)
        let restored = WanderStore(fixtures: .empty(), persistence: WanderStorePersistence(load: { restoredSnapshot }, save: { _ in }))
        XCTAssertEqual(restored.unavailableJointActivityID(for: visitID), eventID)
        XCTAssertNil(restored.jointCheckIn(for: visitID))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("Own note 1"))
        restored.apply(authState: .signedIn(AuthSession(userID: "person-0", displayName: "Person 0", handle: "person0")))
        XCTAssertEqual(restored.unavailableJointActivityID(for: visitID), eventID)
        restored.apply(authState: .signedIn(AuthSession(userID: "another-account", displayName: "Another", handle: "another")))
        XCTAssertNil(restored.unavailableJointActivityID(for: visitID))
    }

    func testBlockRedactsJointContextAndAccountSwitchDiscardsItsIdentity() async throws {
        let group = try projection(count: 2)
        let visitID = group.contributions[0].visitID
        let repository = JointContextProbe()
        repository.result = JointCheckInContexts(mappings: [visitID: groupID], groups: [groupID: group])
        let store = WanderStore(fixtures: .empty())
        store.apply(authState: .signedIn(AuthSession(userID: "person-0", displayName: "Person 0", handle: "person0")))
        await store.refreshJointCheckInContexts(visitIDs: [visitID], backend: WanderBackend(sharedVisitRepository: repository))
        store.block(userID: "person-1")
        XCTAssertNil(store.jointCheckIn(for: visitID))
        XCTAssertEqual(store.unavailableJointActivityID(for: visitID), eventID)
        await store.refreshJointCheckInContexts(visitIDs: [visitID], backend: WanderBackend(sharedVisitRepository: repository))
        XCTAssertNil(store.jointCheckIn(for: visitID), "A server response racing the pending block cannot restore the blocked person")
        store.apply(authState: .signedIn(AuthSession(userID: "another-account", displayName: "Another", handle: "another")))
        XCTAssertNil(store.unavailableJointActivityID(for: visitID))
    }

    func testResponseStartedBeforeBlockCannotRestoreTheOldAudience() async throws {
        let group = try projection(count: 2)
        let visitID = group.contributions[0].visitID
        let repository = JointContextProbe()
        repository.result = JointCheckInContexts(mappings: [visitID: groupID], groups: [groupID: group])
        let backend = WanderBackend(sharedVisitRepository: repository)
        let store = WanderStore(fixtures: .empty())
        await store.refreshJointCheckInContexts(visitIDs: [visitID], backend: backend)
        let started = expectation(description: "Context read suspended after authorization")
        repository.onSuspended = { started.fulfill() }
        let pending = Task { await store.refreshJointCheckInContexts(visitIDs: [visitID], backend: backend) }
        await fulfillment(of: [started], timeout: 2)
        let previousRevision = store.jointPrivacyRevision
        store.block(userID: "person-1")
        XCTAssertGreaterThan(store.jointPrivacyRevision, previousRevision)
        repository.suspendedRead?.resume(returning: repository.result)
        repository.suspendedRead = nil
        await pending.value
        XCTAssertNil(store.jointCheckIn(for: visitID))
        XCTAssertEqual(store.unavailableJointActivityID(for: visitID), eventID)
    }

    func testBackgroundRefreshCannotRebaseAnOpenEditorsVersion() async throws {
        let store = WanderStore(fixtures: .empty())
        store.apply(authState: .signedIn(AuthSession(userID: "person-0", displayName: "Person 0", handle: "person0")))
        store.setPrivateProfile(false)
        let saved = store.saveCandidate(PlaceCandidate(id: "fixture", name: "Fictional Cafe", category: "coffee", latitude: 34, longitude: -118, confidence: 1),
            status: .been, visibility: .followers, note: "Original note", sourceType: .manual)
        let visit = try XCTUnwrap(store.visits(for: saved.userPlaceID).first)
        let remoteID = "e5660000-0000-0000-0002-000000000000"
        visit.serverID = remoteID
        var json = fixture(count: 1)
        var members = try XCTUnwrap(json["contributions"] as? [[String: Any]])
        members[0]["updated_at"] = "2026-09-20T12:00:01.123456Z"
        json["contributions"] = members
        let fresh = try decode(json).projection()
        let repository = JointContextProbe()
        repository.result = JointCheckInContexts(mappings: [remoteID: groupID], groups: [groupID: fresh])
        await store.refreshJointCheckInContexts(visitIDs: [visit.id], backend: WanderBackend(sharedVisitRepository: repository))
        XCTAssertEqual(repository.requestedIDs, [remoteID], "Local IDs must refresh their server identity")
        XCTAssertNil(store.updateVisit(visitID: visit.id, note: "Stale editor text", replacesNote: true,
            expectedJointUpdatedAt: "2026-09-20T12:00:00.123456Z"))
        XCTAssertEqual(visit.note, "Original note")
        XCTAssertTrue(store.pendingSharedVisitInvites.isEmpty)
    }

    func testRepeatedLeaveAfterTransportFailureReusesOneDurableOperation() async throws {
        let group = try projection(count: 2)
        let store = WanderStore(fixtures: .empty())
        store.apply(authState: .signedIn(AuthSession(userID: "person-0", displayName: "Person 0", handle: "person0")))
        let repository = JointContextProbe()
        let backend = WanderBackend(sharedVisitRepository: repository)
        let first = await store.leaveJointCheckIn(group, backend: backend)
        let second = await store.leaveJointCheckIn(group, backend: backend)
        XCTAssertFalse(first)
        XCTAssertFalse(second)
        XCTAssertEqual(store.pendingSharedVisitInvites.count, 1)
        XCTAssertEqual(repository.leaveOperationIDs.count, 2)
        XCTAssertEqual(Set(repository.leaveOperationIDs).count, 1)
    }

    func testFailedAcceptanceRestoresOnlyOwnDraftAndKeepsBlankRating() async throws {
        let invitation = SharedVisitInvitation(participantID: "participant", groupID: groupID,
            invitationGeneration: 2, snapshotRevision: 3, status: .pending, invitedAt: .now,
            sourceVisitID: "source", sourceOwnerUserID: "ryan", sourceOwnerHandle: "ryan",
            sourceOwnerDisplayName: "Ryan", sourceOwnerAvatarURL: nil, placeID: "fictional-place",
            placeName: "Fictional Cafe", category: "coffee", primaryCategory: "coffee", subcategory: nil,
            address: nil, locality: nil, region: nil, country: nil, latitude: 34, longitude: -118,
            sourceProvider: "manual", sourceProviderPlaceID: nil, visitedAt: .now.addingTimeInterval(-60),
            note: "Another person's note", ratingScore: 5, attributeAnswers: [], tags: [], photos: [], modelVersion: 2)
        let draft = SharedVisitAcceptanceDraft(participantID: invitation.participantID, invitationGeneration: 2,
            snapshotRevision: 3, operationID: UUID().uuidString, userPlaceID: UUID().uuidString,
            visitID: UUID().uuidString, visibility: .mutuals, visitedAt: invitation.visitedAt,
            note: "My saved response", ratingScore: nil,
            attributes: [PlaceAttributeDraft(questionKey: "place_tags", valueType: "multi_tag", stringValues: ["Cozy"])],
            selectedPhotoIDs: [], modelVersion: 2,
            ownPhotos: [PlaceSaveDraftPhoto(id: UUID(), contentType: "image/jpeg", localAssetRef: "fictional-own-asset", sourcePhotoID: nil, byteSize: 10)])
        let store = WanderStore(fixtures: .empty())
        let ownerID = store.currentUser.id
        let result = await store.acceptJointCheckIn(invitation: invitation, draft: draft,
            backend: WanderBackend(sharedVisitRepository: JointContextProbe()))
        XCTAssertNil(result)
        let restored = try XCTUnwrap(store.pendingJointAcceptanceDraft(participantID: invitation.participantID))
        XCTAssertEqual(restored, draft)
        let snapshot = try JSONDecoder().decode(WanderStoreSnapshot.self,
            from: JSONEncoder().encode(WanderStoreSnapshot(store: store)))
        XCTAssertEqual(snapshot.pendingSharedVisitInvites, store.pendingSharedVisitInvites)
        let context = MapPlaceSaveContext.sharedVisit(invitation, defaultVisibility: .followers, pendingDraft: restored)
        XCTAssertEqual(context.initialNote, "My saved response")
        XCTAssertNil(context.initialRatingScore)
        XCTAssertEqual(context.initialVisibility, .mutuals)
        XCTAssertEqual(context.originalAttributes, draft.attributes)
        XCTAssertEqual(context.initialVisitedAt, invitation.visitedAt)
        let fresh = MapPlaceSaveContext.sharedVisit(invitation, defaultVisibility: .followers)
        XCTAssertEqual(fresh.initialNote, "")
        XCTAssertNil(fresh.initialRatingScore)
        store.apply(authState: .signedIn(AuthSession(userID: "another-owner", displayName: "Another", handle: "another")))
        XCTAssertNil(store.pendingJointAcceptanceDraft(participantID: invitation.participantID))
        XCTAssertEqual(store.pendingSharedVisitInvites.first?.ownerUserID, ownerID)
    }

    func testAcceptancePhotoRetryDeduplicatesOwnAssetsAndPreservesDeletion() throws {
        let store = WanderStore(fixtures: .empty())
        let saved = store.saveCandidate(PlaceCandidate(id: "photo-fixture", name: "Fictional Cafe", category: "coffee", latitude: 34, longitude: -118, confidence: 1),
            status: .been, visibility: .followers, note: nil, sourceType: .manual)
        let visit = try XCTUnwrap(store.visits(for: saved.userPlaceID).first)
        let own = PlaceSaveDraftPhoto(id: UUID(), contentType: "image/jpeg", localAssetRef: "fictional-own-asset", sourcePhotoID: nil, byteSize: 10)
        let source = PlaceSaveDraftPhoto(id: UUID(), contentType: "image/jpeg", localAssetRef: "fictional-source-asset", sourcePhotoID: "another-person-photo", byteSize: 10)
        store.recordJointAcceptancePhotos([own, source], visitID: visit.id)
        store.recordJointAcceptancePhotos([own, source], visitID: visit.id)
        let photo = try XCTUnwrap(store.photos(for: visit.id).first)
        XCTAssertEqual(store.photos(for: visit.id).count, 1)
        XCTAssertEqual(photo.localAssetRef, own.localAssetRef)
        XCTAssertTrue(store.deleteVisitPhoto(photoID: photo.id))
        store.recordJointAcceptancePhotos([own], visitID: visit.id)
        XCTAssertTrue(store.photos(for: visit.id).isEmpty, "A delayed acceptance retry must not restore a deleted asset")
        XCTAssertEqual(store.visitPhotos.count, 1)
    }

    private func projection(count: Int) throws -> JointCheckInProjection { try decode(fixture(count: count)).projection() }
    private func decode(_ value: [String: Any]) throws -> RemoteJointCheckInDTO {
        try RemoteDecoding.decoder.decode(RemoteJointCheckInDTO.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func fixture(count: Int) -> [String: Any] {
        let people: [[String: Any]] = (0..<count).map { index in
            ["participant_id": String(format: "e5660000-0000-0000-0001-%012d", index),
             "visit_id": String(format: "e5660000-0000-0000-0002-%012d", index),
             "user_place_id": String(format: "e5660000-0000-0000-0003-%012d", index),
             "person": ["id": "person-\(index)", "handle": "person\(index)", "display_name": "Person \(index)"],
             "note": index == 0 ? NSNull() : "Own note \(index)", "rating": index == 0 ? NSNull() : 4.5,
             "media": [], "viewer_can_edit": index == 0]
        }
        return ["group_id": groupID, "canonical_activity_id": eventID, "model_version": 2, "revision": 1,
                "occurred_at": "2026-09-20T12:00:00Z", "viewer_can_manage": true, "contributions": people]
    }
}

private struct JointProbeValue: Codable { let value: Int }
@MainActor
private final class JointReadProbe: RemoteProcedureCalling {
    var calls: [String] = []
    var failure = WanderRemoteError.invalidResponse("PGRST202 new_projection missing")
    func call<Value: Decodable, Params: Encodable>(_ name: String, params: Params, decoder: JSONDecoder) async throws -> Value {
        calls.append(name)
        if name == "new_projection" { throw failure }
        return try decoder.decode(Value.self, from: Data("{\"value\":2}".utf8))
    }
}

@MainActor
private final class JointContextProbe: SharedVisitRepository {
    var result = JointCheckInContexts(mappings: [:], groups: [:])
    var fails = false
    var requestedIDs: [String] = []
    var leaveOperationIDs: [String] = []
    var onSuspended: (() -> Void)?
    var suspendedRead: CheckedContinuation<JointCheckInContexts, Error>?
    func leaveJoint(groupID: String, expectedRevision: Int, operationID: String) async throws -> JointCheckInLeaveResult {
        leaveOperationIDs.append(operationID)
        throw WanderRemoteError.invalidResponse("Network unavailable")
    }
    func jointContexts(visitIDs: [String]) async throws -> JointCheckInContexts {
        requestedIDs = visitIDs
        if let onSuspended {
            return try await withCheckedThrowingContinuation { continuation in
                suspendedRead = continuation
                onSuspended()
            }
        }
        if fails { throw WanderRemoteError.invalidResponse("Network unavailable") }
        return result
    }
    func createInvites(sourceVisitID: String, inviteeUserIDs: [String]) async throws -> [SharedVisitInviteResult] { [] }
    func inviteeUserIDs(sourceVisitID: String) async throws -> [String] { [] }
    func setInvitees(sourceVisitID: String, inviteeUserIDs: [String]) async throws -> [SharedVisitInviteResult] { [] }
    func inbox(before: Date?, limit: Int) async throws -> [SharedVisitInvitation] { [] }
    func context(participantID: String, generation: Int) async throws -> SharedVisitInvitation? { nil }
    func resolveDestination(participantID: String, generation: Int) async throws -> SharedVisitDestination? { nil }
    func accept(_ draft: SharedVisitAcceptanceDraft) async throws -> SharedVisitAcceptanceResult { throw WanderRemoteError.notConfigured }
    func decline(participantID: String, generation: Int) async throws {}
    func companionContext(visitIDs: [String]) async throws -> [SharedVisitCompanion] { [] }
    func downloadPhotoData(bucket: String, path: String) async throws -> Data { Data() }
    func uploadPhotoData(bucket: String, path: String, data: Data, contentType: String) async throws {}
    func markPhotoUploaded(photoID: String) async throws {}
}
