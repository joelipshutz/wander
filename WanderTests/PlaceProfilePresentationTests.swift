import SwiftUI
import UIKit
import XCTest
@testable import Wander

final class PlaceProfilePresentationTests: XCTestCase {
    @MainActor
    func testEverySaveEntryPointUsesTheSharedHalfSheetDetent() {
        XCTAssertEqual(MapPlaceSaveFlowSheet.compactHeight, 560)
        XCTAssertEqual(
            MapPlaceSaveFlowSheet.compactDetent,
            .height(MapPlaceSaveFlowSheet.compactHeight)
        )
    }

    func testAttachedEditorRoutingIsLimitedToFlaggedNewSaveModes() throws {
        let checkIn = try XCTUnwrap(
            PlaceProfileSaveActionPolicy.resolve(state: .unsaved).actions.first {
                $0.kind == .checkIn
            }
        )
        let wanna = try XCTUnwrap(
            PlaceProfileSaveActionPolicy.resolve(state: .unsaved).actions.first {
                $0.kind == .wanna
            }
        )
        let candidate = PlaceCandidate(
            id: "candidate-attached-check-in",
            name: "Griffith Coffee",
            category: "coffee shop",
            address: "Los Angeles, CA",
            latitude: 34.1,
            longitude: -118.3,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "mapkit-griffith-coffee",
            confidence: 0.95
        )
        let base = MapPlaceSaveContext.addCandidate(
            candidate,
            sourceType: .manual,
            defaultVisibility: .followers
        )

        let attached = try XCTUnwrap(
            PlaceProfileSaveActionPolicy.attachedFirstSaveContext(
                route: .floatingActions,
                state: .unsaved,
                action: checkIn,
                baseContext: base
            )
        )
        XCTAssertEqual(attached.candidate, candidate)
        XCTAssertEqual(attached.initialStatus, .been)
        XCTAssertFalse(attached.requiresStatusConfirmation)
        XCTAssertTrue(attached.startsOnDetails)
        guard case .add(.manual) = attached.mode else {
            return XCTFail("Attached first check-in must preserve the original add source")
        }

        let attachedWanna = try XCTUnwrap(
            PlaceProfileSaveActionPolicy.attachedFirstSaveContext(
                route: .floatingActions,
                state: .unsaved,
                action: wanna,
                baseContext: base
            )
        )
        XCTAssertEqual(attachedWanna.candidate, candidate)
        XCTAssertEqual(attachedWanna.initialStatus, .wannaGo)
        XCTAssertFalse(attachedWanna.requiresStatusConfirmation)
        XCTAssertTrue(attachedWanna.startsOnDetails)
        guard case .add(.manual) = attachedWanna.mode else {
            return XCTFail("Attached first Wanna must preserve the original add source")
        }

        for action in [checkIn, wanna] {
            XCTAssertNil(
                PlaceProfileSaveActionPolicy.attachedFirstSaveContext(
                    route: .legacy,
                    state: .unsaved,
                    action: action,
                    baseContext: base
                )
            )
        }
        for state in [
            PlaceProfileSaveActionState.wanna,
            .checkInHistory,
            .sharedInvite,
            .readOnly
        ] {
            for action in [checkIn, wanna] {
                XCTAssertNil(
                    PlaceProfileSaveActionPolicy.attachedFirstSaveContext(
                        route: .floatingActions,
                        state: state,
                        action: action,
                        baseContext: base
                    )
                )
            }
        }
    }

    func testAttachedEditorRejectsExistingAndRepeatContextsForBothActions() throws {
        let checkIn = try XCTUnwrap(
            PlaceProfileSaveActionPolicy.resolve(state: .unsaved).actions.first {
                $0.kind == .checkIn
            }
        )
        let wanna = try XCTUnwrap(
            PlaceProfileSaveActionPolicy.resolve(state: .unsaved).actions.first {
                $0.kind == .wanna
            }
        )
        let currentUser = profile(id: "user_current_attached", handle: "current")
        let currentWanna = summary(
            owner: currentUser,
            place: place(id: "place_current_wanna_attached", category: "coffee"),
            status: .wannaGo,
            ratingScore: nil,
            tags: []
        ).visiblePlace
        let existing = MapPlaceSaveContext.reselectCurrentUserSave(
            currentWanna,
            defaultVisibility: .followers,
            attributes: [],
            latestVisit: nil
        )

        for action in [checkIn, wanna] {
            XCTAssertNil(
                PlaceProfileSaveActionPolicy.attachedFirstSaveContext(
                    route: .floatingActions,
                    state: .unsaved,
                    action: action,
                    baseContext: existing
                )
            )
        }

        let repeatContext = MapPlaceSaveContext.addVisitVisiblePlace(
            currentWanna,
            attributes: [],
            latestVisit: nil
        )
        for action in [checkIn, wanna] {
            XCTAssertNil(
                PlaceProfileSaveActionPolicy.attachedFirstSaveContext(
                    route: .floatingActions,
                    state: .unsaved,
                    action: action,
                    baseContext: repeatContext
                )
            )
        }
    }

    func testAttachedEditorRoutesExistingWannaEditAndCheckInConversion() throws {
        let currentUser = profile(id: "user_current_edit_wanna", handle: "current")
        let currentWanna = summary(
            owner: currentUser,
            place: place(id: "place_current_edit_wanna", category: "park"),
            status: .wannaGo,
            ratingScore: nil,
            tags: ["sunset"]
        ).visiblePlace
        currentWanna.userPlace.note = "Bring a picnic blanket."
        let base = MapPlaceSaveContext.reselectCurrentUserSave(
            currentWanna,
            defaultVisibility: .followers,
            attributes: [],
            latestVisit: nil
        )
        let wannaActions = PlaceProfileSaveActionPolicy.resolve(state: .wanna).actions
        let checkIn = try XCTUnwrap(wannaActions.first { $0.kind == .checkIn })
        let selectedWanna = try XCTUnwrap(wannaActions.first { $0.kind == .wanna })

        let attached = try XCTUnwrap(
            PlaceProfileSaveActionPolicy.attachedSaveContext(
                route: .floatingActions,
                state: .wanna,
                action: selectedWanna,
                baseContext: base
            )
        )
        guard case .editWant(let visiblePlace) = attached.mode else {
            return XCTFail("The selected existing Wanna action must use the edit-Wanna path")
        }
        XCTAssertEqual(visiblePlace.userPlace.id, currentWanna.userPlace.id)
        XCTAssertEqual(attached.initialStatus, .wannaGo)
        XCTAssertEqual(attached.initialNote, "Bring a picnic blanket.")
        XCTAssertTrue(attached.startsOnDetails)
        XCTAssertTrue(attached.showsRemoveControl)

        let draft = try XCTUnwrap(
            PlaceSaveDraft.restorableFlow(
                ownerUserID: currentUser.id,
                context: attached
            )
        )
        XCTAssertEqual(draft.baselineUserPlaceLocalID, currentWanna.userPlace.localID)
        XCTAssertEqual(draft.form.note, "Bring a picnic blanket.")
        XCTAssertEqual(draft.form.selectedStatus, .wannaGo)
        XCTAssertEqual(draft.form.step, .details)

        let conversion = try XCTUnwrap(
            PlaceProfileSaveActionPolicy.attachedSaveContext(
                route: .floatingActions,
                state: .wanna,
                action: checkIn,
                baseContext: base
            )
        )
        guard case .addVisit(let visiblePlace) = conversion.mode else {
            return XCTFail("Existing Wanna to Check in must use the add-visit path")
        }
        XCTAssertEqual(visiblePlace.userPlace.id, currentWanna.userPlace.id)
        XCTAssertEqual(conversion.initialStatus, .been)
        XCTAssertEqual(conversion.initialNote, "")
        XCTAssertTrue(conversion.startsOnDetails)
        XCTAssertFalse(conversion.showsRemoveControl)
        XCTAssertTrue(conversion.allowsPhotoAttachments)

        let conversionDraft = try XCTUnwrap(
            PlaceSaveDraft.restorableFlow(
                ownerUserID: currentUser.id,
                context: conversion
            )
        )
        XCTAssertEqual(conversionDraft.baselineUserPlaceLocalID, currentWanna.userPlace.localID)
        XCTAssertEqual(conversionDraft.form.note, "")
        XCTAssertEqual(conversionDraft.form.selectedStatus, .been)
        XCTAssertEqual(conversionDraft.form.step, .details)

        XCTAssertNil(
            PlaceProfileSaveActionPolicy.attachedSaveContext(
                route: .legacy,
                state: .wanna,
                action: selectedWanna,
                baseContext: base
            )
        )
        XCTAssertNil(
            PlaceProfileSaveActionPolicy.attachedSaveContext(
                route: .legacy,
                state: .wanna,
                action: checkIn,
                baseContext: base
            )
        )
    }

    func testAttachedEditorRejectsMismatchedActionAndStatus() throws {
        let candidate = PlaceCandidate(
            id: "candidate-attached-mismatch",
            name: "Griffith Coffee",
            category: "coffee shop",
            address: "Los Angeles, CA",
            latitude: 34.1,
            longitude: -118.3,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "mapkit-griffith-coffee-mismatch",
            confidence: 0.95
        )
        let base = MapPlaceSaveContext.addCandidate(
            candidate,
            sourceType: .manual,
            defaultVisibility: .followers
        )
        let mismatched = PlaceProfileSaveAction(
            kind: .wanna,
            title: "Wanna",
            isSelected: false,
            destinationStatus: .been
        )

        XCTAssertNil(
            PlaceProfileSaveActionPolicy.attachedFirstSaveContext(
                route: .legacy,
                state: .unsaved,
                action: mismatched,
                baseContext: base
            )
        )
        XCTAssertNil(
            PlaceProfileSaveActionPolicy.attachedFirstSaveContext(
                route: .floatingActions,
                state: .unsaved,
                action: mismatched,
                baseContext: base
            )
        )
    }

    func testFloatingSnapshotRefreshesActionsWithoutChangingTheCapturedRoute() {
        let snapshot = PlaceProfileSaveActionPolicy.snapshot(
            state: .unsaved,
            isSignedIn: true,
            resolvedFlagValue: true,
            launchArguments: []
        )
        let flagOffSnapshot = PlaceProfileSaveActionPolicy.snapshot(
            state: .unsaved,
            isSignedIn: true,
            resolvedFlagValue: false,
            launchArguments: []
        )

        let refreshed = snapshot.refreshingPresentation(for: .checkInHistory)

        XCTAssertEqual(refreshed.route, .floatingActions)
        XCTAssertEqual(refreshed.presentation.actions.map(\.title), ["Check in again", "Edit / history"])
        XCTAssertEqual(flagOffSnapshot.route, .legacy)
        XCTAssertEqual(snapshot.route, .floatingActions)
        let legacy = PlaceProfileSaveActionSnapshot(
            route: .legacy,
            presentation: .empty
        )
        XCTAssertEqual(legacy.refreshingPresentation(for: .unsaved), legacy)
    }

    @MainActor
    func testFloatingActionsStackOnlyForMultipleAccessibilitySizeActions() {
        XCTAssertFalse(
            PlaceProfileFloatingActions.shouldStackActions(
                isAccessibilitySize: false,
                actionCount: 2
            )
        )
        XCTAssertFalse(
            PlaceProfileFloatingActions.shouldStackActions(
                isAccessibilitySize: true,
                actionCount: 1
            )
        )
        XCTAssertTrue(
            PlaceProfileFloatingActions.shouldStackActions(
                isAccessibilitySize: true,
                actionCount: 2
            )
        )
        XCTAssertEqual(PlaceProfileFloatingActions.minimumActionHeight, 48)
    }

    @MainActor
    func testFloatingActionsUseSelectedPrimaryAndNeutralSecondaryGlass() {
        let checkIn = PlaceProfileSaveAction(
            kind: .checkIn,
            title: "Check in",
            isSelected: false,
            destinationStatus: .been
        )
        let selectedWanna = PlaceProfileSaveAction(
            kind: .wanna,
            title: "Wanna",
            isSelected: true,
            destinationStatus: .wannaGo
        )
        let editHistory = PlaceProfileSaveAction(
            kind: .editHistory,
            title: "Edit / history",
            isSelected: false,
            destinationStatus: nil
        )

        XCTAssertEqual(PlaceProfileFloatingActions.glassTone(for: checkIn), .deepBlackAction)
        XCTAssertEqual(PlaceProfileFloatingActions.glassTone(for: selectedWanna), .neutral)
        XCTAssertEqual(PlaceProfileFloatingActions.glassTone(for: editHistory), .neutral)
        XCTAssertEqual(
            PlaceProfileFloatingActions.glassTone(for: checkIn, variant: .option2),
            .blackAction
        )
        XCTAssertEqual(
            PlaceProfileFloatingActions.glassTone(for: checkIn, variant: .option3),
            .blackAction
        )
        XCTAssertEqual(
            PlaceProfileFloatingActions.glassTone(for: checkIn, variant: .option4),
            .blackAction
        )
        XCTAssertEqual(
            PlaceProfileFloatingActions.glassTone(for: checkIn, variant: .option5),
            .deepBlackAction
        )
        XCTAssertEqual(
            PlaceProfileFloatingActions.glassTone(for: selectedWanna, variant: .option4),
            .lightAction
        )
    }

    @MainActor
    func testFloatingActionComparisonResolvesOnlyExplicitValidDebugOptions() {
        XCTAssertEqual(PlaceProfileFloatingActionVariant.productionDefault, .option5)
        XCTAssertEqual(PlaceProfileFloatingActionVariant.resolved(from: []), .option5)
        XCTAssertEqual(
            PlaceProfileFloatingActionVariant.resolved(
                from: ["Wander", PlaceProfileFloatingActionVariant.selectionLaunchArgument, "2"]
            ),
            .option2
        )
        XCTAssertEqual(
            PlaceProfileFloatingActionVariant.resolved(
                from: ["Wander", PlaceProfileFloatingActionVariant.selectionLaunchArgument, "3"]
            ),
            .option3
        )
        XCTAssertEqual(
            PlaceProfileFloatingActionVariant.resolved(
                from: ["Wander", PlaceProfileFloatingActionVariant.selectionLaunchArgument, "4"]
            ),
            .option4
        )
        XCTAssertEqual(
            PlaceProfileFloatingActionVariant.resolved(
                from: ["Wander", PlaceProfileFloatingActionVariant.selectionLaunchArgument, "5"]
            ),
            .option5
        )
        XCTAssertEqual(
            PlaceProfileFloatingActionVariant.resolved(from: [], storedRawValue: 5),
            .option5
        )
        XCTAssertEqual(
            PlaceProfileFloatingActionVariant.resolved(
                from: ["Wander", PlaceProfileFloatingActionVariant.selectionLaunchArgument]
            ),
            .option5
        )
        XCTAssertEqual(
            PlaceProfileFloatingActionVariant.resolved(
                from: ["Wander", PlaceProfileFloatingActionVariant.selectionLaunchArgument, "6"]
            ),
            .option5
        )
        XCTAssertEqual(
            PlaceProfileFloatingActionVariant.resolved(from: [], storedRawValue: 6),
            .option5
        )
    }

    @MainActor
    func testFloatingActionComparisonKeepsCompactOptionsAccessible() {
        XCTAssertFalse(PlaceProfileFloatingActionVariant.option1.usesCompactButtons)
        XCTAssertFalse(PlaceProfileFloatingActionVariant.option2.usesCompactButtons)
        XCTAssertTrue(PlaceProfileFloatingActionVariant.option3.usesCompactButtons)
        XCTAssertTrue(PlaceProfileFloatingActionVariant.option4.usesCompactButtons)
        XCTAssertTrue(PlaceProfileFloatingActionVariant.option5.usesCompactButtons)
        XCTAssertFalse(PlaceProfileFloatingActionVariant.option3.usesCharcoalRail)
        XCTAssertTrue(PlaceProfileFloatingActionVariant.option4.usesCharcoalRail)
        XCTAssertFalse(PlaceProfileFloatingActionVariant.option5.usesCharcoalRail)
        XCTAssertGreaterThanOrEqual(PlaceProfileFloatingActions.minimumActionHeight, 44)
        XCTAssertGreaterThanOrEqual(PlaceProfileFloatingActions.compactActionHeight, 44)
        XCTAssertEqual(PlaceProfileFloatingActions.compactActionHeight, 60)
        XCTAssertEqual(PlaceProfileFloatingActions.compactActionFrameWidth, 124)
        XCTAssertEqual(PlaceProfileFloatingActions.accessibilityCompactActionFrameWidth, 280)
        XCTAssertGreaterThan(
            PlaceProfileFloatingActions.accessibilityCompactActionFrameWidth,
            PlaceProfileFloatingActions.compactActionFrameWidth
        )
    }

    func testFloatingActionIntegerFlagPersistsPerAccount() throws {
        let suiteName = "PlaceProfilePresentationTests.placeActionVariant.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let flags = FeatureFlagOverrideStore(defaults: defaults)

        XCTAssertNil(flags.override(for: .placeProfileActionVariant, userID: "user_a"))
        flags.setOverride(.integer(5), for: .placeProfileActionVariant, userID: "user_a")
        flags.setOverride(.integer(2), for: .placeProfileActionVariant, userID: "user_b")
        XCTAssertEqual(flags.override(for: .placeProfileActionVariant, userID: "user_a"), .integer(5))
        XCTAssertEqual(flags.override(for: .placeProfileActionVariant, userID: "user_b"), .integer(2))
        XCTAssertNil(flags.override(for: .placeProfileActionVariant, userID: "user_c"))
        XCTAssertEqual(
            PlaceProfileFloatingActionVariant(
                rawValue: flags.override(
                    for: .placeProfileActionVariant,
                    userID: "user_b"
                )?.integerValue ?? 5
            ),
            .option2
        )
    }

    func testFloatingStatusSelectionStartsTheExistingSaveSheetOnDetails() {
        let candidate = PlaceCandidate(
            id: "candidate-floating-actions",
            name: "Maru Coffee",
            category: "coffee shop",
            address: "1936 Hillhurst Ave, Los Angeles, CA",
            latitude: 34.10662,
            longitude: -118.28762,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "mapkit-maru",
            confidence: 0.95
        )
        let base = MapPlaceSaveContext.addCandidate(
            candidate,
            sourceType: .manual,
            defaultVisibility: .followers
        )

        let checkIn = base.preselectingStatus(.been)
        XCTAssertEqual(checkIn.initialStatus, .been)
        XCTAssertFalse(checkIn.requiresStatusConfirmation)
        XCTAssertTrue(checkIn.startsOnDetails)

        let wanna = base.preselectingStatus(.wannaGo)
        XCTAssertEqual(wanna.initialStatus, .wannaGo)
        XCTAssertFalse(wanna.requiresStatusConfirmation)
        XCTAssertTrue(wanna.startsOnDetails)
    }

    func testFloatingStatusSelectionPreservesExistingWannaConversionSemantics() {
        let currentUser = profile(id: "user_current", handle: "current")
        let currentWanna = summary(
            owner: currentUser,
            place: place(id: "place_existing_wanna", category: "coffee"),
            status: .wannaGo,
            ratingScore: nil,
            tags: []
        ).visiblePlace
        let base = MapPlaceSaveContext.reselectCurrentUserSave(
            currentWanna,
            defaultVisibility: .followers,
            attributes: [],
            latestVisit: nil
        )

        let checkIn = base.preselectingStatus(.been)
        guard case .addVisit = checkIn.mode else {
            return XCTFail("A current Wanna should use the existing conversion-to-check-in path")
        }
        XCTAssertEqual(checkIn.initialStatus, .been)
        XCTAssertTrue(checkIn.startsOnDetails)

        let wanna = base.preselectingStatus(.wannaGo)
        guard case .editWant = wanna.mode else {
            return XCTFail("Selecting the active Wanna should reopen its existing editor")
        }
        XCTAssertEqual(wanna.initialStatus, .wannaGo)
        XCTAssertTrue(wanna.startsOnDetails)
    }

    func testUnifiedSaveModeDraftCacheRestoresBothSwitchDirections() {
        let checkInPhoto = MapPlaceSavePhotoAttachment(
            id: UUID(),
            image: UIImage(),
            contentType: "image/jpeg",
            localAssetRef: "check-in-photo",
            sourcePhotoID: "source-photo",
            byteSize: 42
        )
        let checkIn = MapPlaceSaveModeDraft(
            visibility: .followers,
            ratingScore: 4.5,
            selectedAnswers: ["occasion": ["date night"]],
            unifiedTags: ["cozy"],
            note: "check-in draft",
            visitedAt: Date(timeIntervalSince1970: 100),
            plannedDate: nil,
            photoAttachments: [checkInPhoto],
            selectedInviteeUserIDs: ["friend-1"],
            isShowingOptionalDetails: true,
            didLoadSharedVisitInvitees: true,
            sharedVisitInviteesError: "retry invitees"
        )
        let wanna = MapPlaceSaveModeDraft<MapPlaceSavePhotoAttachment>(
            visibility: .selfOnly,
            ratingScore: 2,
            selectedAnswers: ["occasion": ["solo"]],
            unifiedTags: ["patio"],
            note: "wanna draft",
            visitedAt: Date(timeIntervalSince1970: 200),
            plannedDate: Date(timeIntervalSince1970: 300),
            photoAttachments: [],
            selectedInviteeUserIDs: [],
            isShowingOptionalDetails: false,
            didLoadSharedVisitInvitees: false,
            sharedVisitInviteesError: nil
        )
        var cache = MapPlaceSaveModeDraftCache<MapPlaceSaveModeDraft<MapPlaceSavePhotoAttachment>>()
        cache.store(checkIn, for: .been)
        cache.store(wanna, for: .wannaGo)

        let restoredCheckIn = cache.draft(for: .been)
        XCTAssertEqual(restoredCheckIn?.visibility, checkIn.visibility)
        XCTAssertEqual(restoredCheckIn?.ratingScore, checkIn.ratingScore)
        XCTAssertEqual(restoredCheckIn?.selectedAnswers, checkIn.selectedAnswers)
        XCTAssertEqual(restoredCheckIn?.unifiedTags, checkIn.unifiedTags)
        XCTAssertEqual(restoredCheckIn?.note, checkIn.note)
        XCTAssertEqual(restoredCheckIn?.visitedAt, checkIn.visitedAt)
        XCTAssertEqual(restoredCheckIn?.plannedDate, checkIn.plannedDate)
        XCTAssertEqual(restoredCheckIn?.photoAttachments.map(\.id), [checkInPhoto.id])
        XCTAssertEqual(restoredCheckIn?.selectedInviteeUserIDs, checkIn.selectedInviteeUserIDs)
        XCTAssertEqual(restoredCheckIn?.isShowingOptionalDetails, checkIn.isShowingOptionalDetails)
        XCTAssertEqual(restoredCheckIn?.didLoadSharedVisitInvitees, checkIn.didLoadSharedVisitInvitees)
        XCTAssertEqual(restoredCheckIn?.sharedVisitInviteesError, checkIn.sharedVisitInviteesError)

        let restoredWanna = cache.draft(for: .wannaGo)
        XCTAssertEqual(restoredWanna?.visibility, wanna.visibility)
        XCTAssertEqual(restoredWanna?.ratingScore, wanna.ratingScore)
        XCTAssertEqual(restoredWanna?.selectedAnswers, wanna.selectedAnswers)
        XCTAssertEqual(restoredWanna?.unifiedTags, wanna.unifiedTags)
        XCTAssertEqual(restoredWanna?.note, wanna.note)
        XCTAssertEqual(restoredWanna?.visitedAt, wanna.visitedAt)
        XCTAssertEqual(restoredWanna?.plannedDate, wanna.plannedDate)
        XCTAssertTrue(restoredWanna?.photoAttachments.isEmpty == true)
        XCTAssertEqual(restoredWanna?.selectedInviteeUserIDs, wanna.selectedInviteeUserIDs)
        XCTAssertEqual(restoredWanna?.isShowingOptionalDetails, wanna.isShowingOptionalDetails)
        XCTAssertEqual(restoredWanna?.didLoadSharedVisitInvitees, wanna.didLoadSharedVisitInvitees)
        XCTAssertNil(restoredWanna?.sharedVisitInviteesError)
    }

    func testUnifiedSaveSubmissionPolicyExcludesHiddenModeValues() {
        XCTAssertEqual(MapPlaceSaveSubmissionPolicy.checkInValue(4.5, status: .been), 4.5)
        XCTAssertNil(MapPlaceSaveSubmissionPolicy.checkInValue(4.5, status: .wannaGo))
        XCTAssertEqual(
            MapPlaceSaveSubmissionPolicy.checkInValues(["photo", "friend"], status: .been),
            ["photo", "friend"]
        )
        XCTAssertEqual(
            MapPlaceSaveSubmissionPolicy.checkInValues(["photo", "friend"], status: .wannaGo),
            []
        )
        let plannedDate = Date(timeIntervalSince1970: 400)
        XCTAssertNil(MapPlaceSaveSubmissionPolicy.wannaGoValue(plannedDate, status: .been))
        XCTAssertEqual(
            MapPlaceSaveSubmissionPolicy.wannaGoValue(plannedDate, status: .wannaGo),
            plannedDate
        )
    }

    func testCandidateProfilePreservesProviderPhotoIdentityAndChooseAction() {
        let candidate = PlaceCandidate(
            id: "candidate-maru",
            name: "Maru Coffee",
            category: "coffee shop",
            address: "1936 Hillhurst Ave, Los Angeles, CA",
            latitude: 34.10662,
            longitude: -118.28762,
            sourceProvider: "google_maps",
            sourceProviderPlaceID: "google-maru-hillhurst",
            confidence: 0.95
        )

        let place = PlaceSheetPlace(candidate: candidate)

        XCTAssertEqual(place.photoRequest.name, candidate.name)
        XCTAssertEqual(place.photoRequest.sourceProvider, "google_maps")
        XCTAssertEqual(place.photoRequest.sourceProviderPlaceID, "google-maru-hillhurst")
        XCTAssertEqual(PlaceSheetAction.choose.systemImage, "checkmark")
        XCTAssertEqual(PlaceSheetAction.choose.accessibilityLabel, "Choose this place")
        XCTAssertEqual(PlaceSheetAction.add.systemImage, "plus")
        XCTAssertEqual(PlaceSheetAction.addVisit.systemImage, "plus")
        XCTAssertEqual(PlaceSheetAction.editWant.systemImage, "pencil")
        XCTAssertEqual(PlaceSheetAction.add.displayTitle, "Check in")
        XCTAssertEqual(PlaceSheetAction.addVisit.displayTitle, "Check in again")
        XCTAssertEqual(PlaceSheetAction.editWant.displayTitle, "Edit Wanna")
        XCTAssertEqual(
            PlaceSheetAction.addVisit.displayTitle(placeName: "Maru Coffee", hasPriorCheckIn: false),
            "Check in at Maru Coffee"
        )
        XCTAssertEqual(
            PlaceSheetAction.addVisit.displayTitle(placeName: "Maru Coffee", hasPriorCheckIn: true),
            "Check in again"
        )
        XCTAssertEqual(PlaceSheetAction.choose.displayTitle, "Choose this place")
        XCTAssertTrue(PlaceSheetAction.choose.isPrimaryAction)
        XCTAssertTrue(PlaceSheetAction.editWant.isPrimaryAction)
    }

    func testPlaceProfileSaveActionPolicyMapsEverySupportedState() {
        XCTAssertEqual(
            PlaceProfileSaveActionPolicy.resolve(state: .unsaved).actions,
            [
                PlaceProfileSaveAction(
                    kind: .checkIn,
                    title: "Check in",
                    isSelected: false,
                    destinationStatus: .been
                ),
                PlaceProfileSaveAction(
                    kind: .wanna,
                    title: "Wanna",
                    isSelected: false,
                    destinationStatus: .wannaGo
                )
            ]
        )
        XCTAssertEqual(
            PlaceProfileSaveActionPolicy.resolve(state: .wanna).actions,
            [
                PlaceProfileSaveAction(
                    kind: .checkIn,
                    title: "Check in",
                    isSelected: false,
                    destinationStatus: .been
                ),
                PlaceProfileSaveAction(
                    kind: .wanna,
                    title: "Wanna",
                    isSelected: true,
                    destinationStatus: .wannaGo
                )
            ]
        )
        XCTAssertEqual(
            PlaceProfileSaveActionPolicy.resolve(state: .checkInHistory).actions,
            [
                PlaceProfileSaveAction(
                    kind: .checkIn,
                    title: "Check in again",
                    isSelected: false,
                    destinationStatus: .been
                ),
                PlaceProfileSaveAction(
                    kind: .editHistory,
                    title: "Edit / history",
                    isSelected: false,
                    destinationStatus: nil
                )
            ]
        )
        XCTAssertEqual(
            PlaceProfileSaveActionPolicy.resolve(state: .sharedInvite).actions,
            [
                PlaceProfileSaveAction(
                    kind: .checkIn,
                    title: "Check in",
                    isSelected: false,
                    destinationStatus: .been
                )
            ]
        )
        XCTAssertEqual(PlaceProfileSaveActionPolicy.resolve(state: .readOnly), .empty)
    }

    func testPlaceProfileSaveActionPolicyUsesGroupedCurrentUserState() {
        let currentUser = profile(id: "user_current", handle: "current")
        let socialUser = profile(id: "user_social", handle: "social")
        let sharedPlace = place(id: "place_policy", category: "coffee")
        let socialCheckIn = summary(
            owner: socialUser,
            place: sharedPlace,
            status: .been,
            ratingScore: 5,
            tags: []
        )

        XCTAssertEqual(
            PlaceProfileSaveActionPolicy.state(
                saves: [socialCheckIn],
                currentUserID: currentUser.id,
                hasSharedVisitInvitation: false,
                isReadOnly: false
            ),
            .unsaved
        )

        let ownWanna = summary(
            owner: currentUser,
            place: sharedPlace,
            status: .wannaGo,
            ratingScore: nil,
            tags: []
        )
        XCTAssertEqual(
            PlaceProfileSaveActionPolicy.state(
                saves: [socialCheckIn, ownWanna],
                currentUserID: currentUser.id,
                hasSharedVisitInvitation: false,
                isReadOnly: false
            ),
            .wanna
        )

        let ownCheckIn = summary(
            owner: currentUser,
            place: sharedPlace,
            status: .been,
            ratingScore: 4,
            tags: []
        )
        XCTAssertEqual(
            PlaceProfileSaveActionPolicy.state(
                saves: [ownCheckIn, socialCheckIn],
                currentUserID: currentUser.id,
                hasSharedVisitInvitation: false,
                isReadOnly: false
            ),
            .checkInHistory
        )
    }

    func testPlaceProfileSaveActionPolicyPrioritizesNonMutatingAndInviteStates() {
        let currentUser = profile(id: "user_current", handle: "current")
        let ownCheckIn = summary(
            owner: currentUser,
            place: place(id: "place_policy", category: "coffee"),
            status: .been,
            ratingScore: 4,
            tags: []
        )

        XCTAssertEqual(
            PlaceProfileSaveActionPolicy.state(
                currentUserSave: ownCheckIn.visiblePlace,
                hasSharedVisitInvitation: true,
                isReadOnly: false
            ),
            .sharedInvite
        )
        XCTAssertEqual(
            PlaceProfileSaveActionPolicy.state(
                currentUserSave: ownCheckIn.visiblePlace,
                hasSharedVisitInvitation: true,
                isReadOnly: true
            ),
            .readOnly
        )
    }

    func testPlaceProfileSaveActionSnapshotFailsClosedWithoutResolvedSignedInFlag() {
        let unresolved = PlaceProfileSaveActionPolicy.snapshot(
            state: .unsaved,
            isSignedIn: true,
            resolvedFlagValue: nil,
            launchArguments: []
        )
        let disabled = PlaceProfileSaveActionPolicy.snapshot(
            state: .unsaved,
            isSignedIn: true,
            resolvedFlagValue: false,
            launchArguments: []
        )
        let signedOut = PlaceProfileSaveActionPolicy.snapshot(
            state: .unsaved,
            isSignedIn: false,
            resolvedFlagValue: true,
            launchArguments: []
        )

        for snapshot in [unresolved, disabled, signedOut] {
            XCTAssertEqual(snapshot.route, .legacy)
            XCTAssertFalse(snapshot.usesFloatingActions)
            XCTAssertEqual(snapshot.presentation, .empty)
        }
    }

    func testPlaceProfileSaveActionSnapshotCapturesEnabledRoute() {
        let openedProfile = PlaceProfileSaveActionPolicy.snapshot(
            state: .wanna,
            isSignedIn: true,
            resolvedFlagValue: true,
            launchArguments: []
        )
        let laterFlagRefresh = PlaceProfileSaveActionPolicy.snapshot(
            state: .wanna,
            isSignedIn: true,
            resolvedFlagValue: false,
            launchArguments: []
        )

        XCTAssertEqual(openedProfile.route, .floatingActions)
        XCTAssertTrue(openedProfile.usesFloatingActions)
        XCTAssertEqual(openedProfile.presentation.actions.map(\.kind), [.checkIn, .wanna])
        XCTAssertEqual(laterFlagRefresh.route, .legacy)
        XCTAssertEqual(openedProfile.route, .floatingActions)
    }

    func testSimulatorAndPhysicalDeviceBothFailClosedWithoutAResolvedFlag() {
        let simulator = PlaceProfileSaveActionPolicy.snapshot(
            state: .unsaved,
            isSignedIn: true,
            resolvedFlagValue: nil,
            launchArguments: [],
            isSimulator: true
        )
        let physicalDevice = PlaceProfileSaveActionPolicy.snapshot(
            state: .unsaved,
            isSignedIn: true,
            resolvedFlagValue: nil,
            launchArguments: [],
            isSimulator: false
        )

        XCTAssertEqual(simulator.route, .legacy)
        XCTAssertTrue(simulator.presentation.actions.isEmpty)
        XCTAssertEqual(physicalDevice.route, .legacy)
    }

    #if DEBUG
    func testPlaceProfileSaveActionDebugLaunchOverrideSupportsSignedOutSimulator() {
        let snapshot = PlaceProfileSaveActionPolicy.snapshot(
            state: .unsaved,
            isSignedIn: false,
            resolvedFlagValue: nil,
            launchArguments: [PlaceProfileSaveActionPolicy.debugEnableLaunchArgument]
        )

        XCTAssertTrue(snapshot.usesFloatingActions)
        XCTAssertEqual(snapshot.presentation.actions.map(\.kind), [.checkIn, .wanna])
    }
    #endif

    #if DEBUG
    @MainActor
    func testMapCaptureRepositoryProvidesDeterministicGoogleAndVisibleUserPhotos() async throws {
        let repository = MapCapturePlacePhotoRepository()
        let googleRequest = PlacePhotoRequest(
            placeID: "place-maru",
            name: "Maru Coffee",
            address: "1936 Hillhurst Ave, Los Angeles, CA",
            latitude: 34.10662,
            longitude: -118.28762,
            sourceProvider: "google_maps",
            sourceProviderPlaceID: "google-maru-hillhurst"
        )

        let googlePhoto = try await repository.photo(for: googleRequest)
        let googleImageData = try await repository.imageData(for: googlePhoto)

        XCTAssertEqual(googlePhoto.provider, "google_places")
        XCTAssertTrue(googlePhoto.providerPlaceID.hasPrefix("capture-google-"))
        XCTAssertEqual(URL(string: try XCTUnwrap(googlePhoto.sourcePhotoURLString))?.host, "www.google.com")
        XCTAssertNotNil(UIImage(data: googleImageData))

        let coordinateRequest = PlacePhotoRequest(
            placeID: "place-dropped-pin",
            name: "Dropped pin",
            address: "Yosemite National Park, CA",
            latitude: 37.73635,
            longitude: -119.57366,
            sourceProvider: "coordinate",
            sourceProviderPlaceID: "coordinate_37.73635_-119.57366"
        )
        let visibleUserPhoto = try await repository.photo(for: coordinateRequest)
        let visibleUserImageData = try await repository.imageData(for: visibleUserPhoto)

        XCTAssertEqual(visibleUserPhoto.provider, "visit_photo")
        XCTAssertTrue(visibleUserPhoto.providerPlaceID.hasPrefix("capture-visit-"))
        XCTAssertNil(visibleUserPhoto.sourcePhotoURLString)
        XCTAssertNotNil(UIImage(data: visibleUserImageData))
    }

    @MainActor
    func testCandidatePickerDoesNotRequestProviderPhotosBeforeOpeningProfile() async throws {
        let photo = PlacePhoto(
            provider: "google_places",
            providerPlaceID: "unused-google-place",
            photoURLString: "https://lh3.googleusercontent.com/unused-photo",
            width: 400,
            height: 300,
            authorName: "Unused Photographer",
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: "https://www.google.com/maps/unused-photo",
            flagContentURLString: nil,
            storageBucket: nil,
            storagePath: nil,
            localAssetRef: nil
        )
        let repository = CachingPlacePhotoRepository(photo: photo, data: Data([0x01]))
        let backend = WanderBackend(placePhotoRepository: repository)
        let host = UIHostingController(
            rootView: PlaceImportCandidateMockupRoot()
                .environmentObject(backend)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(repository.metadataRequestCount, 0)
        XCTAssertEqual(repository.imageRequestCount, 0)
        window.isHidden = true
    }
    #endif

    func testFitScoreExplanationCopyDescribesPersonalizationWithoutFallbackBehavior() {
        XCTAssertEqual(PlaceRatingExplanation.fitScore.title, "Fit score")
        XCTAssertEqual(
            PlaceRatingExplanation.fitScore.message,
            "Fit score predicts how well this place matches your taste. It uses your ratings, the categories and tags you like, and places saved by trusted people."
        )
        XCTAssertEqual(PlaceRatingExplanation.fitScore.accessibilityLabel, "About Fit score")
        XCTAssertFalse(PlaceRatingExplanation.fitScore.message.contains("If none"))
        XCTAssertFalse(PlaceRatingExplanation.fitScore.message.contains("rec.me rating"))
        XCTAssertFalse(PlaceRatingExplanation.fitScore.message.contains("Friends rating"))
    }

    func testPlacePhotoDecodesProviderTypesForCategoryEnrichment() throws {
        let data = Data(
            """
            {
              "provider": "google_places",
              "provider_place_id": "google-ugo",
              "provider_primary_type": "restaurant",
              "provider_types": ["food", "italian_restaurant", "point_of_interest"],
              "photo_url": "https://example.com/ugo.jpg"
            }
            """.utf8
        )

        let photo = try JSONDecoder().decode(PlacePhoto.self, from: data)

        XCTAssertEqual(photo.providerPrimaryType, "restaurant")
        XCTAssertEqual(photo.providerTypes, ["food", "italian_restaurant", "point_of_interest"])
    }

    func testMapTicketAllowsCurrentUserCheckInPhotoAtEveryVisibility() {
        let currentUser = profile(id: "user_current", handle: "current")
        let otherUser = profile(id: "user_other", handle: "other")
        let sharedPlace = place(id: "place_photo_policy", category: "coffee")
        let ownSave = summary(owner: currentUser, place: sharedPlace, ratingScore: 4, tags: [])
        let socialSave = summary(owner: otherUser, place: sharedPlace, ratingScore: 5, tags: [])

        for visibility in [PlaceVisibility.followers, .mutuals, .selfOnly] {
            ownSave.visiblePlace.userPlace.visibilityRaw = visibility.rawValue
            XCTAssertTrue(
                PlaceProfilePreviewPhotoPolicy.canUseCurrentUserLocalPhoto(
                    saves: [ownSave, socialSave],
                    currentUserID: currentUser.id
                ),
                "The owner should see their own \(visibility.rawValue) check-in photo"
            )
        }

        XCTAssertFalse(
            PlaceProfilePreviewPhotoPolicy.canUseCurrentUserLocalPhoto(
                saves: [socialSave],
                currentUserID: currentUser.id
            )
        )
    }

    @MainActor
    func testFeedResolvedPhotoFallsBackFromBrokenGoogleImageToVisibleCheckInPhoto() async throws {
        let checkInPhotoLoaded = expectation(description: "Visible check-in photo loaded")
        let renderedImage = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let repository = FeedPlacePhotoFallbackRepository(
            checkInImageData: try XCTUnwrap(renderedImage.pngData()),
            checkInPhotoLoaded: checkInPhotoLoaded
        )
        let backend = WanderBackend(placePhotoRepository: repository)
        let store = WanderStore(fixtures: .seed())
        let visiblePlace = try XCTUnwrap(store.visiblePlaces().first)
        let host = UIHostingController(
            rootView: FeedResolvedPlacePhoto(place: visiblePlace)
                .environmentObject(backend)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 184, height: 88))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        await fulfillment(of: [checkInPhotoLoaded], timeout: 2.0)

        XCTAssertEqual(repository.metadataRequestCount, 1)
        XCTAssertEqual(repository.visibleUserPhotoRequestCount, 1)
        XCTAssertEqual(repository.requestedImageProviders, ["google_places", "visit_photo"])
        window.isHidden = true
    }

    func testLegacyBeenActivityUsesVisitedDateThenSavedDateInsteadOfLastEdit() {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let place = place(id: "place_coffee", category: "coffee")
        let summary = summary(owner: currentUser, place: place, ratingScore: 4, tags: [])
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let visitedAt = Date(timeIntervalSince1970: 1_700_100_000)
        summary.visiblePlace.userPlace.savedAt = savedAt
        summary.visiblePlace.userPlace.updatedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let savedFallback = PlaceActivityEntry(
            summary: summary,
            visit: nil,
            kind: .legacyBeenSummary,
            currentUserID: currentUser.id
        )
        XCTAssertEqual(savedFallback.timestamp, savedAt)

        summary.visiblePlace.userPlace.visitedAt = visitedAt
        let explicitVisitDate = PlaceActivityEntry(
            summary: summary,
            visit: nil,
            kind: .legacyBeenSummary,
            currentUserID: currentUser.id
        )
        XCTAssertEqual(explicitVisitDate.timestamp, visitedAt)
    }

    @MainActor
    func testPlacePhotoImageStartsRemoteLoadFromEmptyState() async throws {
        let loadStarted = expectation(description: "Place photo load started")
        let renderedImage = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let repository = RecordingPlacePhotoRenderingRepository(
            imageData: try XCTUnwrap(renderedImage.pngData()),
            loadStarted: loadStarted
        )
        let backend = WanderBackend(placePhotoRepository: repository)
        let photo = PlacePhoto(
            provider: "google_places",
            providerPlaceID: "test-google-place",
            photoURLString: "https://lh3.googleusercontent.com/test-photo",
            width: 1600,
            height: 1200,
            authorName: "Test Photographer",
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: "https://www.google.com/maps/test-photo",
            flagContentURLString: nil,
            storageBucket: nil,
            storagePath: nil,
            localAssetRef: nil
        )
        let host = UIHostingController(
            rootView: PlaceProfilePhotoImage(
                photo: photo,
                canonicalPlaceKey: "place:test",
                placeName: "Test Place"
            )
                .environmentObject(backend)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        await fulfillment(of: [loadStarted], timeout: 1.0)

        XCTAssertEqual(repository.requestedPhotos, [photo])
        window.isHidden = true
    }

    @MainActor
    func testBackendCachesRepeatedPlacePhotoMetadataAndImageLoads() async throws {
        let photo = PlacePhoto(
            provider: "google_places",
            providerPlaceID: "cached-google-place",
            photoURLString: "https://lh3.googleusercontent.com/cached-photo",
            width: 400,
            height: 300,
            authorName: nil,
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: "https://www.google.com/maps/cached-photo",
            flagContentURLString: nil,
            storageBucket: nil,
            storagePath: nil,
            localAssetRef: nil
        )
        let repository = CachingPlacePhotoRepository(photo: photo, data: Data([0x01, 0x02]))
        let backend = WanderBackend(placePhotoRepository: repository)
        let request = PlacePhotoRequest(
            name: "One Cedar",
            address: "Los Angeles, CA",
            latitude: 34.05,
            longitude: -118.24,
            sourceProvider: "google_maps",
            sourceProviderPlaceID: "cached-google-place"
        )

        let firstPhoto = try await backend.placePhoto(for: request)
        let secondPhoto = try await backend.placePhoto(for: request)
        let firstData = try await backend.placePhotoImageData(
            for: photo,
            canonicalPlaceKey: "place:test"
        )
        let secondData = try await backend.placePhotoImageData(
            for: photo,
            canonicalPlaceKey: "place:test"
        )
        let otherPlaceData = try await backend.placePhotoImageData(
            for: photo,
            canonicalPlaceKey: "place:other"
        )

        XCTAssertEqual(firstPhoto, photo)
        XCTAssertEqual(secondPhoto, photo)
        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(firstData, otherPlaceData)
        XCTAssertEqual(repository.metadataRequestCount, 1)
        XCTAssertEqual(repository.imageRequestCount, 2)
    }

    @MainActor
    func testPlacePhotoImageReportsRemoteDecodeFailureForUserPhotoFallback() async throws {
        let failureReported = expectation(description: "Place photo failure reported")
        let repository = FailingPlacePhotoRenderingRepository()
        let backend = WanderBackend(placePhotoRepository: repository)
        let photo = PlacePhoto(
            provider: "google_places",
            providerPlaceID: "failed-google-place",
            photoURLString: "https://lh3.googleusercontent.com/failed-photo",
            width: 1600,
            height: 1200,
            authorName: nil,
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: "https://www.google.com/maps/failed-photo",
            flagContentURLString: nil,
            storageBucket: nil,
            storagePath: nil,
            localAssetRef: nil
        )
        let host = UIHostingController(
            rootView: PlaceProfilePhotoImage(
                photo: photo,
                canonicalPlaceKey: "place:failed-test",
                placeName: "Failed Test Place",
                onLoadFailure: { failedPhoto in
                    XCTAssertEqual(failedPhoto, photo)
                    failureReported.fulfill()
                }
            )
            .environmentObject(backend)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()

        await fulfillment(of: [failureReported], timeout: 1.0)
        window.isHidden = true
    }

    @MainActor
    func testWidePlacePhotoKeepsHeaderControlsInsidePhoneWidth() async throws {
        let loadStarted = expectation(description: "Wide place photo load started")
        let renderedImage = UIGraphicsImageRenderer(size: CGSize(width: 2_400, height: 600)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2_400, height: 600))
        }
        let repository = RecordingPlacePhotoRenderingRepository(
            imageData: try XCTUnwrap(renderedImage.jpegData(compressionQuality: 0.8)),
            loadStarted: loadStarted
        )
        let backend = WanderBackend(placePhotoRepository: repository)
        let photo = PlacePhoto(
            provider: "google_places",
            providerPlaceID: "wide-google-place",
            photoURLString: "https://lh3.googleusercontent.com/wide-photo",
            width: 2_400,
            height: 600,
            authorName: "Test Photographer",
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: "https://www.google.com/maps/wide-photo",
            flagContentURLString: nil,
            storageBucket: nil,
            storagePath: nil,
            localAssetRef: nil
        )
        let recorder = PlacePhotoControlFrameRecorder()
        let host = UIHostingController(
            rootView: PlacePhotoControlLayoutProbe(photo: photo, recorder: recorder)
                .environmentObject(backend)
        )
        let phoneWidth: CGFloat = 393
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: phoneWidth, height: 268))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        await fulfillment(of: [loadStarted], timeout: 1.0)
        try await Task.sleep(for: .milliseconds(350))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let trailingControlFrame = try XCTUnwrap(recorder.frames.last)
        XCTAssertGreaterThanOrEqual(trailingControlFrame.minX, 0)
        XCTAssertLessThanOrEqual(trailingControlFrame.maxX, phoneWidth)
        window.isHidden = true
    }

    func testCommonTagsRequireUserAndTrustedOrTwoTrustedSupports() {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let ryan = profile(id: "user_ryan", handle: "ryan")
        let place = place(id: "place_coffee", category: "coffee")

        let summaries = [
            summary(owner: currentUser, place: place, ratingScore: 4, tags: ["quiet", "laptop time"]),
            summary(owner: maya, place: place, ratingScore: 5, tags: ["quiet", "patio"]),
            summary(owner: ryan, place: place, ratingScore: 4, tags: ["patio"])
        ]

        let tags = PlaceProfilePresenter.commonTags(from: summaries, currentUserID: currentUser.id)

        XCTAssertEqual(tags.map(\.title), ["quiet", "patio"])
        XCTAssertEqual(tags.first?.hasOwnSupport, true)
        XCTAssertFalse(tags.contains { $0.title == "laptop time" })
    }

    func testCommonTagsIgnoreInterestSignals() {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let place = place(id: "place_noodles", category: "restaurant")

        let summaries = [
            summary(owner: currentUser, place: place, ratingScore: nil, interestSignal: "must go", tags: ["cozy"]),
            summary(owner: maya, place: place, ratingScore: nil, interestSignal: "must go", tags: ["cozy"])
        ]

        let tags = PlaceProfilePresenter.commonTags(from: summaries, currentUserID: currentUser.id)

        XCTAssertEqual(tags.map(\.title), ["cozy"])
        XCTAssertFalse(tags.contains { $0.title == "must go" })
    }

    func testRatingsSeparateCurrentUserRatingFromOverallRating() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let place = place(id: "place_bar", category: "bar")
        let summaries = [
            summary(owner: currentUser, place: place, ratingScore: 3, tags: []),
            summary(owner: maya, place: place, ratingScore: 5, tags: [])
        ]

        let overallRating = try XCTUnwrap(PlaceProfilePresenter.overallRating(from: summaries, currentUserID: currentUser.id))
        let ownRating = try XCTUnwrap(PlaceProfilePresenter.ownRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertEqual(overallRating.source, .friends)
        XCTAssertEqual(overallRating.score, 5)
        XCTAssertEqual(overallRating.count, 1)
        XCTAssertEqual(ownRating.source, .own)
        XCTAssertEqual(ownRating.score, 3)
        XCTAssertEqual(ownRating.count, 1)
    }

    func testOwnRatingUsesAggregatedRatedVisitCount() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let place = place(id: "place_alibi", category: "bar")
        let summaries = [
            summary(owner: currentUser, place: place, ratingScore: 4.7, recommendedCount: 3, tags: [])
        ]

        let ownRating = try XCTUnwrap(PlaceProfilePresenter.ownRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertEqual(ownRating.source, .own)
        XCTAssertEqual(ownRating.displayScore, "4.7")
        XCTAssertEqual(ownRating.count, 3)
        XCTAssertEqual(ownRating.subtitle, "3 check-ins")
    }

    func testOverallRatingAveragesTrustedRatingsWhenUnsaved() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let ryan = profile(id: "user_ryan", handle: "ryan")
        let place = place(id: "place_hike", category: "hike")
        let summaries = [
            summary(owner: maya, place: place, ratingScore: 4, tags: []),
            summary(owner: ryan, place: place, ratingScore: 5, tags: [])
        ]

        let rating = try XCTUnwrap(PlaceProfilePresenter.overallRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertEqual(rating.source, .friends)
        XCTAssertEqual(rating.score, 4.5)
        XCTAssertEqual(rating.count, 2)
    }

    func testFriendsRatingWeightsEachFollowedPersonOnce() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let ryan = profile(id: "user_ryan", handle: "ryan")
        let place = place(id: "place_tacos", category: "restaurant")
        let summaries = [
            summary(owner: maya, place: place, ratingScore: 4, recommendedCount: 2, tags: []),
            summary(owner: ryan, place: place, ratingScore: 5, recommendedCount: 1, tags: [])
        ]

        let rating = try XCTUnwrap(PlaceProfilePresenter.overallRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertEqual(rating.source, .friends)
        XCTAssertEqual(rating.score, 4.5, accuracy: 0.0001)
        XCTAssertEqual(rating.count, 2)
        XCTAssertEqual(rating.subtitle, "2 people you follow")
    }

    func testCurrentUserWannaSaveCanShowTrustedOverallButNoOwnRating() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let place = place(id: "place_want", category: "restaurant")
        let summaries = [
            summary(owner: currentUser, place: place, status: .wannaGo, ratingScore: 4, tags: []),
            summary(owner: maya, place: place, ratingScore: 5, tags: [])
        ]

        let overallRating = try XCTUnwrap(PlaceProfilePresenter.overallRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertNil(PlaceProfilePresenter.ownRating(from: summaries, currentUserID: currentUser.id))
        XCTAssertEqual(overallRating.source, .friends)
        XCTAssertEqual(overallRating.score, 5)
    }

    func testOverallRatingUsesCommunityFallbackWhenNoFollowedPersonHasRated() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let stranger = profile(id: "user_stranger", handle: "stranger")
        let place = place(id: "place_solo", category: "coffee")
        let summaries = [
            summary(
                owner: stranger,
                place: place,
                ratingScore: 2,
                recommendedScore: 4.2,
                recommendedCount: 12,
                viewerFollowsOwner: false,
                tags: []
            )
        ]

        let rating = try XCTUnwrap(PlaceProfilePresenter.overallRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertEqual(rating.source, .community)
        XCTAssertEqual(rating.title, "rec.me rating")
        XCTAssertEqual(rating.score, 4.2)
        XCTAssertEqual(rating.count, 12)
    }

    func testFriendsRatingExcludesNonFollowedPeopleEvenWhenTheirRatingIsLoaded() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let followed = profile(id: "user_maya", handle: "maya")
        let stranger = profile(id: "user_stranger", handle: "stranger")
        let place = place(id: "place_cafe", category: "coffee")
        let summaries = [
            summary(
                owner: followed,
                place: place,
                ratingScore: 5,
                recommendedScore: 2.5,
                recommendedCount: 20,
                viewerFollowsOwner: true,
                tags: []
            ),
            summary(
                owner: stranger,
                place: place,
                ratingScore: 1,
                recommendedScore: 2.5,
                recommendedCount: 20,
                viewerFollowsOwner: false,
                tags: []
            )
        ]

        let rating = try XCTUnwrap(PlaceProfilePresenter.overallRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertEqual(rating.source, .friends)
        XCTAssertEqual(rating.title, "Friends rating")
        XCTAssertEqual(rating.score, 5)
        XCTAssertEqual(rating.count, 1)
    }

    func testFitRatingIsNilWhenEvidenceIsThin() {
        let currentUser = profile(id: "user_joe", handle: "joe")

        let presentation = PlaceProfilePresenter.presentation(
            placeID: "place_unknown",
            category: "coffee",
            saves: [],
            tasteSaves: [],
            currentUserID: currentUser.id
        )

        XCTAssertNil(presentation.fitRating)
        XCTAssertNil(presentation.overallRating)
        XCTAssertNil(presentation.ownRating)
        XCTAssertTrue(presentation.commonTags.isEmpty)
    }

    func testFitRatingDisplayUsesFivePointScale() {
        XCTAssertEqual(PlaceFitRating(score: 8.6, reasons: []).displayScore, "4.3")
        XCTAssertEqual(PlaceFitRating(score: 10, reasons: []).displayScore, "5")
    }

    func testFitRatingUsesTrustedRatingsCategoryAndTagHistory() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let ryan = profile(id: "user_ryan", handle: "ryan")
        let selectedPlace = place(id: "place_selected", category: "coffee")
        let likedPlace = place(id: "place_liked", category: "coffee")

        let selectedSaves = [
            summary(owner: maya, place: selectedPlace, ratingScore: 5, tags: ["quiet", "wifi solid"]),
            summary(owner: ryan, place: selectedPlace, ratingScore: 4, tags: ["quiet"])
        ]
        let tasteSaves = [
            summary(owner: currentUser, place: likedPlace, ratingScore: 5, tags: ["quiet", "outlets"])
        ]

        let presentation = PlaceProfilePresenter.presentation(
            placeID: selectedPlace.id,
            category: selectedPlace.category,
            saves: selectedSaves,
            tasteSaves: tasteSaves,
            currentUserID: currentUser.id
        )

        let fit = try XCTUnwrap(presentation.fitRating)
        XCTAssertEqual(presentation.overallRating?.score, 4.5)
        XCTAssertNil(presentation.ownRating)
        XCTAssertGreaterThanOrEqual(fit.score, 8)
        XCTAssertEqual(presentation.commonTags.map(\.title), ["quiet"])
        XCTAssertTrue(fit.reasons.contains { $0.contains("coffee, tea, & sweets") })
        XCTAssertTrue(fit.reasons.contains { $0.contains("quiet") })
    }

    private func profile(id: String, handle: String) -> LocalProfile {
        LocalProfile(
            localID: "local_\(id)",
            serverID: id,
            handle: handle,
            displayName: handle.capitalized,
            syncState: .synced
        )
    }

    private func place(id: String, category: String) -> LocalPlace {
        LocalPlace(
            localID: "local_\(id)",
            serverID: id,
            canonicalName: id.replacingOccurrences(of: "_", with: " ").capitalized,
            category: category,
            locality: "Los Angeles",
            latitude: 34.05,
            longitude: -118.25,
            sourceProvider: "mapkit",
            syncState: .synced
        )
    }

    private func summary(
        owner: LocalProfile,
        place: LocalPlace,
        status: PlaceStatus? = nil,
        ratingScore: Double?,
        recommendedScore: Double? = nil,
        recommendedCount: Int? = nil,
        viewerFollowsOwner: Bool = true,
        interestSignal: String? = nil,
        tags: [String]
    ) -> PlaceSaveSummary {
        let resolvedStatus = status ?? (ratingScore == nil ? .wannaGo : .been)
        let userPlace = LocalUserPlace(
            localID: "local_up_\(owner.id)_\(place.id)",
            serverID: "up_\(owner.id)_\(place.id)",
            userID: owner.id,
            placeID: place.id,
            status: resolvedStatus,
            visibility: .followers,
            note: nil,
            ratingScore: ratingScore,
            recommendedScore: recommendedScore ?? ratingScore,
            recommendedCount: recommendedCount ?? (ratingScore == nil ? 0 : 1),
            sourceType: "test",
            syncState: .synced
        )
        userPlace.ratingScore = ratingScore
        userPlace.recommendedScore = recommendedScore ?? ratingScore
        let visiblePlace = VisiblePlace(id: userPlace.id, place: place, userPlace: userPlace, owner: owner)
        var attributes: [LocalPlaceAttribute] = []

        if let interestSignal {
            attributes.append(attribute(userPlaceID: userPlace.id, key: "interest_signal", valueType: "emoji_scale", value: interestSignal))
        }

        if !tags.isEmpty {
            attributes.append(attribute(userPlaceID: userPlace.id, key: "\(place.category)_tags", valueType: "multi_tag", values: tags))
        }

        return PlaceSaveSummary(
            visiblePlace: visiblePlace,
            attributes: attributes,
            viewerFollowsOwner: viewerFollowsOwner
        )
    }

    private func attribute(userPlaceID: String, key: String, valueType: String, value: String) -> LocalPlaceAttribute {
        LocalPlaceAttribute(
            localID: "local_attr_\(userPlaceID)_\(key)",
            serverID: nil,
            userPlaceID: userPlaceID,
            questionKey: key,
            valueType: valueType,
            valueJSON: json(value),
            syncState: .synced
        )
    }

    private func attribute(userPlaceID: String, key: String, valueType: String, values: [String]) -> LocalPlaceAttribute {
        LocalPlaceAttribute(
            localID: "local_attr_\(userPlaceID)_\(key)",
            serverID: nil,
            userPlaceID: userPlaceID,
            questionKey: key,
            valueType: valueType,
            valueJSON: json(values),
            syncState: .synced
        )
    }

    private func json<T: Encodable>(_ value: T) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!
    }
}

@MainActor
private final class RecordingPlacePhotoRenderingRepository: PlacePhotoRepository {
    let imageData: Data
    let loadStarted: XCTestExpectation
    private(set) var requestedPhotos: [PlacePhoto] = []

    init(imageData: Data, loadStarted: XCTestExpectation) {
        self.imageData = imageData
        self.loadStarted = loadStarted
    }

    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        throw WanderRemoteError.invalidResponse("Unexpected metadata request")
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        throw WanderRemoteError.invalidResponse("Unexpected fallback metadata request")
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        requestedPhotos.append(photo)
        loadStarted.fulfill()
        return imageData
    }
}

@MainActor
private final class FailingPlacePhotoRenderingRepository: PlacePhotoRepository {
    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        throw WanderRemoteError.invalidResponse("Unexpected metadata request")
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        throw WanderRemoteError.invalidResponse("Unexpected fallback metadata request")
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        Data([0x00, 0x01, 0x02])
    }
}

@MainActor
private final class CachingPlacePhotoRepository: PlacePhotoRepository {
    let resolvedPhoto: PlacePhoto
    let data: Data
    private(set) var metadataRequestCount = 0
    private(set) var imageRequestCount = 0

    init(photo: PlacePhoto, data: Data) {
        resolvedPhoto = photo
        self.data = data
    }

    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        metadataRequestCount += 1
        return resolvedPhoto
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        resolvedPhoto
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        imageRequestCount += 1
        return data
    }
}

@MainActor
private final class FeedPlacePhotoFallbackRepository: PlacePhotoRepository {
    let googlePhoto = PlacePhoto(
        provider: "google_places",
        providerPlaceID: "broken-google-photo",
        photoURLString: "https://lh3.googleusercontent.com/broken-photo",
        width: 400,
        height: 300,
        authorName: nil,
        authorProfileURLString: nil,
        authorAvatarURLString: nil,
        sourcePhotoURLString: "https://www.google.com/maps/broken-photo",
        flagContentURLString: nil,
        storageBucket: nil,
        storagePath: nil,
        localAssetRef: nil
    )
    let checkInPhoto = PlacePhoto(
        provider: "visit_photo",
        providerPlaceID: "visible-check-in-photo",
        photoURLString: "",
        width: 400,
        height: 300,
        authorName: "A person you follow",
        authorProfileURLString: nil,
        authorAvatarURLString: nil,
        sourcePhotoURLString: nil,
        flagContentURLString: nil,
        storageBucket: "visit-photos",
        storagePath: "visible/check-in/photo.jpg",
        localAssetRef: nil
    )
    let checkInImageData: Data
    let checkInPhotoLoaded: XCTestExpectation
    private(set) var metadataRequestCount = 0
    private(set) var visibleUserPhotoRequestCount = 0
    private(set) var requestedImageProviders: [String] = []

    init(checkInImageData: Data, checkInPhotoLoaded: XCTestExpectation) {
        self.checkInImageData = checkInImageData
        self.checkInPhotoLoaded = checkInPhotoLoaded
    }

    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        metadataRequestCount += 1
        return googlePhoto
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        visibleUserPhotoRequestCount += 1
        return checkInPhoto
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        requestedImageProviders.append(photo.provider)
        if photo.provider == "visit_photo" {
            checkInPhotoLoaded.fulfill()
            return checkInImageData
        }
        return Data([0x00, 0x01, 0x02])
    }
}

@MainActor
private final class PlacePhotoControlFrameRecorder {
    var frames: [CGRect] = []
}

private struct PlacePhotoControlLayoutProbe: View {
    let photo: PlacePhoto
    let recorder: PlacePhotoControlFrameRecorder

    var body: some View {
        ZStack {
            Color.clear

            PlaceProfilePhotoImage(
                photo: photo,
                canonicalPlaceKey: "place:wide-test",
                placeName: "Wide Test Place"
            )

            HStack {
                Color.blue
                    .frame(width: 42, height: 42)

                Spacer()

                Color.green
                    .frame(width: 42, height: 42)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: PlacePhotoTrailingControlFrameKey.self,
                                value: proxy.frame(in: .global)
                            )
                        }
                    }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 268)
        .clipped()
        .onPreferenceChange(PlacePhotoTrailingControlFrameKey.self) { frame in
            recorder.frames.append(frame)
        }
    }
}

private struct PlacePhotoTrailingControlFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
