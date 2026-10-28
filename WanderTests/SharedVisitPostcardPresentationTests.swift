import XCTest
@testable import Wander

@MainActor
final class SharedVisitPostcardPresentationTests: XCTestCase {
    func testOneHeaderUsesCanonicalSourceAndBothAuthorizedNotesAndPhotoPile() throws {
        let source = post("source", actor: "alex", name: "Alex Example", note: "Source note", photos: ["source-photo"])
        let accepted = post("accepted", actor: "sam", name: "Sam Example", note: "Accepted note", photos: ["accepted-photo"])
        let collection = try XCTUnwrap(SharedVisitPostCollection(groupID: "group", commentActivityID: source.id,
            posts: [accepted, source]))
        let presentation = try XCTUnwrap(SharedVisitPostcardPresentation(collection: collection, viewerID: "viewer", permits: { _ in true }))
        XCTAssertEqual(presentation.context.actor.id, "alex")
        XCTAssertEqual(presentation.attribution, "Alex Example Checked-In With Sam Example")
        XCTAssertEqual(Set(presentation.posts.compactMap(\.note)), ["Source note", "Accepted note"])
        XCTAssertEqual(Set(presentation.context.media.map(\.id)), ["source-photo", "accepted-photo"])
        XCTAssertEqual(presentation.mediaAuthors["accepted-photo"]?.id, "sam")
        XCTAssertEqual(presentation.context.activityID, source.id)
    }

    func testPendingIdentityIsOwnerOnlyAndAddsNoContributions() throws {
        let source = post("source", actor: "alex", name: "Alex Example", note: "Source note", photos: ["source-photo"])
        let pending = FeedSharedVisitCompanion(profile: profile("sam", "Sam Example"), status: .pending)
        let collection = try XCTUnwrap(SharedVisitPostCollection(groupID: "group", commentActivityID: source.id,
            posts: [source], companions: [pending]))
        let owner = try XCTUnwrap(SharedVisitPostcardPresentation(collection: collection, viewerID: "alex", permits: { _ in true }))
        XCTAssertEqual(owner.attribution, "Alex Example Checked-In With Sam Example")
        XCTAssertFalse(owner.attribution.localizedCaseInsensitiveContains("pending"))
        XCTAssertEqual(owner.posts.count, 1)
        XCTAssertEqual(owner.context.media.map(\.id), ["source-photo"])
        let viewer = try XCTUnwrap(SharedVisitPostcardPresentation(collection: collection, viewerID: "viewer", permits: { _ in true }))
        XCTAssertTrue(viewer.companions.isEmpty)
    }

    func testDeclinedOrRemovedIdentityIsNotDisplayedAfterRefresh() throws {
        let source = post("source", actor: "alex", name: "Alex Example")
        for status: SharedVisitParticipantStatus in [.declined, .cancelled, .removed, .expired] {
            let collection = try XCTUnwrap(SharedVisitPostCollection(groupID: "group", commentActivityID: source.id,
                posts: [source], companions: [.init(profile: profile("sam", "Sam Example"), status: status)]))
            let presentation = try XCTUnwrap(SharedVisitPostcardPresentation(collection: collection, viewerID: "alex", permits: { _ in true }))
            XCTAssertTrue(presentation.companions.isEmpty)
            XCTAssertEqual(presentation.attribution, "Alex Example Checked-In")
        }
    }

    func testLocalDenialRemovesMemberNotePhotoAndIdentityAndCannotRetargetCanonicalAction() throws {
        let source = post("source", actor: "alex", name: "Alex Example", photos: ["one"])
        let accepted = post("accepted", actor: "sam", name: "Sam Example", note: "Accepted note", photos: ["two"])
        let collection = try XCTUnwrap(SharedVisitPostCollection(groupID: "group", commentActivityID: source.id, posts: [source, accepted],
            companions: [.init(profile: accepted.actor, status: .accepted)]))
        let presentation = try XCTUnwrap(SharedVisitPostcardPresentation(collection: collection, viewerID: "viewer", permits: { $0.id != "sam" }))
        XCTAssertTrue(presentation.companions.isEmpty)
        XCTAssertEqual(presentation.posts.map(\.id), [source.id])
        XCTAssertEqual(presentation.context.media.map(\.id), ["one"])
        XCTAssertNil(SharedVisitPostcardPresentation(collection: collection, viewerID: "viewer", permits: { $0.id != "alex" }))
    }

    func testPhotoIdentityDeduplicatesWithoutGuessingSameContent() throws {
        let source = post("source", actor: "alex", name: "Alex Example", photos: ["same", "one"])
        let accepted = post("accepted", actor: "sam", name: "Sam Example", photos: ["same", "two"])
        let collection = try XCTUnwrap(SharedVisitPostCollection(groupID: "group", commentActivityID: source.id, posts: [source, accepted]))
        let presentation = try XCTUnwrap(SharedVisitPostcardPresentation(collection: collection, viewerID: "viewer", permits: { _ in true }))
        XCTAssertEqual(presentation.context.media.map(\.id), ["same", "one", "two"])
        XCTAssertEqual(presentation.mediaAuthors["same"]?.id, "alex")
    }

    func testMembershipRefreshInvalidatesLoadedIdentityIncludingEmptyResult() {
        let member = SharedVisitCompanion(visitID: "visit", userID: "sam", handle: "sam", displayName: "Sam", avatarURL: nil)
        let unknown = SharedVisitMembershipSnapshot.key(visitIDs: ["visit"], cache: [:])
        let accepted = SharedVisitMembershipSnapshot.key(visitIDs: ["visit"], cache: ["visit": [member]])
        let removed = SharedVisitMembershipSnapshot.key(visitIDs: ["visit"], cache: ["visit": []])
        XCTAssertNotEqual(unknown, accepted)
        XCTAssertNotEqual(accepted, removed)
        XCTAssertNotEqual(unknown, removed)
    }

    func testMembershipSnapshotIgnoresUnrelatedVisitsAndOrderingButTracksIdentityChanges() {
        let sam = SharedVisitCompanion(visitID: "visit", userID: "sam", handle: "sam", displayName: "Sam", avatarURL: nil)
        let alex = SharedVisitCompanion(visitID: "visit", userID: "alex", handle: "alex", displayName: "Alex", avatarURL: nil)
        let baseline = SharedVisitMembershipSnapshot.key(visitIDs: ["visit"], cache: ["visit": [sam, alex]])
        XCTAssertEqual(baseline, SharedVisitMembershipSnapshot.key(visitIDs: ["visit", "visit"],
            cache: ["visit": [alex, sam], "unrelated": []]))
        let renamed = SharedVisitCompanion(visitID: "visit", userID: "sam", handle: "sam", displayName: "Samuel", avatarURL: nil)
        XCTAssertNotEqual(baseline, SharedVisitMembershipSnapshot.key(visitIDs: ["visit"], cache: ["visit": [renamed, alex]]))
    }

    private func profile(_ id: String, _ name: String) -> ProfileShell {
        .init(id: id, handle: id, displayName: name, avatarURL: nil, bio: nil, relationship: .mutual)
    }
    private func post(_ id: String, actor: String, name: String, note: String? = nil, photos: [String] = []) -> FeedActivity {
        let place = LocalPlace(localID: "shared-place", canonicalName: "Example Café", category: "coffee", latitude: 0, longitude: 0)
        let parent = LocalUserPlace(localID: "save-\(actor)", userID: actor, placeID: place.id, status: .been,
            visibility: .followers, sourceType: "manual")
        return FeedActivity(id: id, kind: .placeBeen, actor: profile(actor, name),
            place: VisiblePlace(id: parent.id, place: place, userPlace: parent,
                owner: LocalProfile(localID: actor, handle: actor, displayName: name)),
            occurredAt: .distantPast, note: note, media: photos.map { .init(id: $0, accessibilityLabel: "Example photo") })
    }
}
