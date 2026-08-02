import XCTest
@testable import Wander

@MainActor
final class PlaceSaveDraftStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDraftRoundTripsEveryUserEnteredField() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let persistence = PlaceSaveDraftPersistence.file(url: url)
        let draft = makeDraft(status: .been)

        persistence.save(draft)

        XCTAssertEqual(persistence.load(), draft)
    }

    func testCoalescedWriterFlushesLatestDraftBeforeBackgrounding() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let persistence = PlaceSaveDraftPersistence.coalescingFile(url: url)
        var draft = makeDraft()
        persistence.save(draft)
        draft.form.note = "Latest note"
        persistence.save(draft)

        persistence.flush()

        XCTAssertEqual(persistence.load()?.form.note, "Latest note")
    }

    func testCorruptDraftIsDiscardedFromDisk() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: url)
        let persistence = PlaceSaveDraftPersistence.file(url: url)

        XCTAssertNil(persistence.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRestoreRejectsAnotherAccountAndClearsPersistedDraft() {
        var persisted: PlaceSaveDraft? = makeDraft(ownerUserID: "user-a")
        let persistence = PlaceSaveDraftPersistence(
            load: { persisted },
            save: { persisted = $0 }
        )
        let store = PlaceSaveDraftStore(persistence: persistence)

        XCTAssertEqual(
            store.restore(ownerUserID: "user-b", now: now),
            .discarded
        )
        XCTAssertNil(store.draft)
        XCTAssertNil(persisted)
    }

    func testRestoreRejectsExpiredDraft() {
        var persisted: PlaceSaveDraft? = makeDraft(
            updatedAt: now.addingTimeInterval(-PlaceSaveDraft.maximumAge - 1)
        )
        let store = PlaceSaveDraftStore(
            persistence: PlaceSaveDraftPersistence(
                load: { persisted },
                save: { persisted = $0 }
            )
        )

        XCTAssertEqual(store.restore(ownerUserID: "user-a", now: now), .discarded)
        XCTAssertNil(persisted)
    }

    func testEditingDraftRestoresWithoutCommitReconciliation() {
        XCTAssertEqual(
            PlaceSaveDraftRecoveryPolicy.outcome(
                for: makeDraft(submittedAt: nil),
                evidence: nil
            ),
            .editing
        )
    }

    func testSubmittedWannaDraftIsCommittedOnlyByMatchingNewerLocalSave() {
        let submittedAt = now.addingTimeInterval(-10)
        let draft = makeDraft(
            status: .wannaGo,
            baselineUserPlaceLocalID: "user-place-1",
            submittedAt: submittedAt
        )

        XCTAssertEqual(
            PlaceSaveDraftRecoveryPolicy.outcome(
                for: draft,
                evidence: PlaceSaveDraftCommitEvidence(
                    userPlaceLocalID: "user-place-1",
                    userPlaceUpdatedAt: now,
                    status: .wannaGo,
                    latestVisitLocalID: nil,
                    latestVisitCreatedAt: nil
                )
            ),
            .committed
        )
        XCTAssertEqual(
            PlaceSaveDraftRecoveryPolicy.outcome(
                for: draft,
                evidence: PlaceSaveDraftCommitEvidence(
                    userPlaceLocalID: "user-place-1",
                    userPlaceUpdatedAt: submittedAt.addingTimeInterval(-1),
                    status: .wannaGo,
                    latestVisitLocalID: nil,
                    latestVisitCreatedAt: nil
                )
            ),
            .retry
        )
    }

    func testSubmittedBeenDraftRequiresANewVisitCreatedAfterSubmission() {
        let submittedAt = now.addingTimeInterval(-10)
        let draft = makeDraft(
            status: .been,
            baselineVisitLocalID: "visit-before",
            submittedAt: submittedAt
        )

        XCTAssertEqual(
            PlaceSaveDraftRecoveryPolicy.outcome(
                for: draft,
                evidence: PlaceSaveDraftCommitEvidence(
                    userPlaceLocalID: "user-place-1",
                    userPlaceUpdatedAt: now,
                    status: .been,
                    latestVisitLocalID: "visit-after",
                    latestVisitCreatedAt: now
                )
            ),
            .committed
        )
        XCTAssertEqual(
            PlaceSaveDraftRecoveryPolicy.outcome(
                for: draft,
                evidence: PlaceSaveDraftCommitEvidence(
                    userPlaceLocalID: "user-place-1",
                    userPlaceUpdatedAt: now,
                    status: .been,
                    latestVisitLocalID: "visit-before",
                    latestVisitCreatedAt: now
                )
            ),
            .retry
        )
    }

    func testPreparingRetryRetainsFormAndAddsRecoveryMessage() {
        var persisted: PlaceSaveDraft?
        let store = PlaceSaveDraftStore(
            persistence: PlaceSaveDraftPersistence(
                load: { persisted },
                save: { persisted = $0 }
            )
        )
        let original = makeDraft(submittedAt: now.addingTimeInterval(-10))
        store.begin(original)

        store.prepareRetry(message: "Try again", now: now)

        XCTAssertEqual(store.draft?.form, original.form)
        XCTAssertNil(store.draft?.submittedAt)
        XCTAssertEqual(store.draft?.recoveryNotice, "Try again")
        XCTAssertEqual(persisted, store.draft)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaceSaveDraftStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("draft.json")
    }

    private func makeDraft(
        ownerUserID: String = "user-a",
        updatedAt: Date? = nil,
        status: PlaceStatus = .wannaGo,
        baselineUserPlaceLocalID: String? = nil,
        baselineVisitLocalID: String? = nil,
        submittedAt: Date? = nil
    ) -> PlaceSaveDraft {
        PlaceSaveDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000199")!,
            ownerUserID: ownerUserID,
            createdAt: now.addingTimeInterval(-60),
            updatedAt: updatedAt ?? now,
            sourceType: .manual,
            candidate: PlaceCandidate(
                id: "candidate-1",
                name: "Bar Raval",
                category: "restaurant",
                primaryCategory: WanderPlaceCategory.restaurantsFood,
                address: "505 College St",
                locality: "Toronto",
                region: "ON",
                country: "Canada",
                latitude: 43.6559,
                longitude: -79.4098,
                sourceProviderPlaceID: "provider-place-1",
                confidence: 0.98
            ),
            baselineUserPlaceLocalID: baselineUserPlaceLocalID,
            baselineVisitLocalID: baselineVisitLocalID,
            form: PlaceSaveDraftForm(
                step: .details,
                selectedAssignment: PlaceCategoryAssignment(
                    primaryCategory: WanderPlaceCategory.restaurantsFood,
                    subcategory: "Tapas Restaurant",
                    source: PlaceCategorySource.user.rawValue
                ),
                selectedStatus: status,
                selectedVisibility: .mutuals,
                selectedRatingScore: 8.5,
                selectedAnswers: ["occasion": ["date night", "friends"]],
                unifiedTags: ["cozy", "late night"],
                selectedCuisine: "Spanish",
                note: "Order the conservas",
                visitedAt: now.addingTimeInterval(-86_400),
                plannedDate: now.addingTimeInterval(86_400),
                photoAttachments: [
                    PlaceSaveDraftPhoto(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000200")!,
                        contentType: "image/jpeg",
                        localAssetRef: "visit-photos/photo.jpg",
                        sourcePhotoID: "photo-library-1",
                        byteSize: 12_345
                    )
                ],
                selectedInviteeUserIDs: ["friend-1", "friend-2"],
                isShowingOptionalDetails: true
            ),
            submittedAt: submittedAt
        )
    }
}
