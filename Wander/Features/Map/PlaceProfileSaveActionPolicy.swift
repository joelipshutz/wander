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

    func refreshingPresentation(
        for state: PlaceProfileSaveActionState
    ) -> PlaceProfileSaveActionSnapshot {
        guard usesFloatingActions else { return self }
        return PlaceProfileSaveActionSnapshot(
            route: route,
            presentation: PlaceProfileSaveActionPolicy.resolve(state: state)
        )
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
        launchArguments: [String] = ProcessInfo.processInfo.arguments,
        isSimulator: Bool = false
    ) -> PlaceProfileSaveActionSnapshot {
        let usesFloatingActions = isFloatingActionsEnabled(
            isSignedIn: isSignedIn,
            resolvedFlagValue: resolvedFlagValue,
            launchArguments: launchArguments,
            isSimulator: isSimulator
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
        launchArguments: [String] = ProcessInfo.processInfo.arguments,
        isSimulator: Bool = false
    ) -> Bool {
        if isSimulator {
            return true
        }

        #if DEBUG
        if launchArguments.contains(debugEnableLaunchArgument) {
            return true
        }
        #endif

        guard isSignedIn else { return false }
        return resolvedFlagValue == true
    }

    static func attachedFirstSaveContext(
        route: PlaceProfileSaveExperienceRoute,
        state: PlaceProfileSaveActionState,
        action: PlaceProfileSaveAction,
        baseContext: MapPlaceSaveContext
    ) -> MapPlaceSaveContext? {
        guard route == .floatingActions,
              state == .unsaved,
              let destinationStatus = action.destinationStatus,
              isSupportedFirstSaveAction(action.kind, status: destinationStatus),
              baseContext.existingCurrentUserSave == nil,
              !baseContext.hasPriorCheckIn,
              case .add = baseContext.mode
        else { return nil }

        return baseContext.preselectingStatus(destinationStatus)
    }

    static func attachedSaveContext(
        route: PlaceProfileSaveExperienceRoute,
        state: PlaceProfileSaveActionState,
        action: PlaceProfileSaveAction,
        baseContext: MapPlaceSaveContext
    ) -> MapPlaceSaveContext? {
        if let firstSave = attachedFirstSaveContext(
            route: route,
            state: state,
            action: action,
            baseContext: baseContext
        ) {
            return firstSave
        }

        return attachedExistingWannaContext(
            route: route,
            state: state,
            action: action,
            baseContext: baseContext
        )
    }

    static func attachedExistingWannaContext(
        route: PlaceProfileSaveExperienceRoute,
        state: PlaceProfileSaveActionState,
        action: PlaceProfileSaveAction,
        baseContext: MapPlaceSaveContext
    ) -> MapPlaceSaveContext? {
        guard route == .floatingActions,
              state == .wanna,
              baseContext.existingCurrentUserSave?.userPlace.status == .wannaGo,
              case .add = baseContext.mode
        else { return nil }

        switch (action.kind, action.isSelected, action.destinationStatus) {
        case (.wanna, true, .wannaGo):
            return baseContext.preselectingStatus(.wannaGo)
        case (.checkIn, false, .been):
            return baseContext.preselectingStatus(.been)
        default:
            return nil
        }
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

    private static func isSupportedFirstSaveAction(
        _ kind: PlaceProfileSaveActionKind,
        status: PlaceStatus
    ) -> Bool {
        switch (kind, status) {
        case (.checkIn, .been), (.wanna, .wannaGo):
            true
        case (.checkIn, .wannaGo), (.wanna, .been), (.editHistory, _):
            false
        }
    }
}
