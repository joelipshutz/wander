import Foundation

enum PlaceProfileSaveActionState: Equatable {
    case unsaved
    case wanna
    case checkInHistory
    case sharedInvite
    case readOnly
}

enum PlaceProfileSaveActionKind: String, Identifiable, Equatable {
    case checkIn
    case wanna
    case editHistory

    var id: String { rawValue }
}

struct PlaceProfileSaveAction: Identifiable, Equatable {
    let kind: PlaceProfileSaveActionKind
    let title: String
    let isSelected: Bool
    let destinationStatus: PlaceStatus?

    var id: String { kind.id }
}

struct PlaceProfileSaveActionPresentation: Equatable {
    let actions: [PlaceProfileSaveAction]

    static let empty = PlaceProfileSaveActionPresentation(actions: [])
}

enum PlaceProfileSaveExperienceRoute: Equatable {
    case legacy
    case floatingActions
}

/// An immutable routing decision for one opened place profile. Callers create
/// this once when the profile is presented so a foreground flag refresh cannot
/// replace an editor that is already on screen.
struct PlaceProfileSaveActionSnapshot: Equatable {
    let route: PlaceProfileSaveExperienceRoute
    let presentation: PlaceProfileSaveActionPresentation

    var usesFloatingActions: Bool {
        route == .floatingActions
    }
}

enum PlaceProfileSaveActionPolicy {
    #if DEBUG
    static let debugEnableLaunchArgument = "-WanderPlaceProfileSaveTrayV1"
    #endif

    static func snapshot(
        state: PlaceProfileSaveActionState,
        isSignedIn: Bool,
        resolvedFlagValue: Bool?,
        launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) -> PlaceProfileSaveActionSnapshot {
        let usesFloatingActions = isFloatingActionsEnabled(
            isSignedIn: isSignedIn,
            resolvedFlagValue: resolvedFlagValue,
            launchArguments: launchArguments
        )

        guard usesFloatingActions else {
            return PlaceProfileSaveActionSnapshot(
                route: .legacy,
                presentation: .empty
            )
        }

        return PlaceProfileSaveActionSnapshot(
            route: .floatingActions,
            presentation: resolve(state: state)
        )
    }

    static func isFloatingActionsEnabled(
        isSignedIn: Bool,
        resolvedFlagValue: Bool?,
        launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        #if DEBUG
        if launchArguments.contains(debugEnableLaunchArgument) {
            return true
        }
        #endif

        guard isSignedIn else { return false }
        return resolvedFlagValue == true
    }

    static func state(
        currentUserSave: VisiblePlace?,
        hasSharedVisitInvitation: Bool,
        isReadOnly: Bool
    ) -> PlaceProfileSaveActionState {
        if isReadOnly {
            return .readOnly
        }
        if hasSharedVisitInvitation {
            return .sharedInvite
        }
        guard let currentUserSave else {
            return .unsaved
        }
        return currentUserSave.userPlace.status == .wannaGo ? .wanna : .checkInHistory
    }

    static func state(
        saves: [PlaceSaveSummary],
        currentUserID: String,
        hasSharedVisitInvitation: Bool,
        isReadOnly: Bool
    ) -> PlaceProfileSaveActionState {
        state(
            currentUserSave: saves.first {
                $0.visiblePlace.owner.id == currentUserID
            }?.visiblePlace,
            hasSharedVisitInvitation: hasSharedVisitInvitation,
            isReadOnly: isReadOnly
        )
    }

    static func resolve(state: PlaceProfileSaveActionState) -> PlaceProfileSaveActionPresentation {
        switch state {
        case .unsaved:
            PlaceProfileSaveActionPresentation(actions: [
                action(.checkIn, title: "Check in", destinationStatus: .been),
                action(.wanna, title: "Wanna", destinationStatus: .wannaGo)
            ])
        case .wanna:
            PlaceProfileSaveActionPresentation(actions: [
                action(.checkIn, title: "Check in", destinationStatus: .been),
                action(.wanna, title: "Wanna", isSelected: true, destinationStatus: .wannaGo)
            ])
        case .checkInHistory:
            PlaceProfileSaveActionPresentation(actions: [
                action(.checkIn, title: "Check in again", destinationStatus: .been),
                action(.editHistory, title: "Edit / history", destinationStatus: nil)
            ])
        case .sharedInvite:
            PlaceProfileSaveActionPresentation(actions: [
                action(.checkIn, title: "Check in", destinationStatus: .been)
            ])
        case .readOnly:
            .empty
        }
    }

    private static func action(
        _ kind: PlaceProfileSaveActionKind,
        title: String,
        isSelected: Bool = false,
        destinationStatus: PlaceStatus?
    ) -> PlaceProfileSaveAction {
        PlaceProfileSaveAction(
            kind: kind,
            title: title,
            isSelected: isSelected,
            destinationStatus: destinationStatus
        )
    }
}
