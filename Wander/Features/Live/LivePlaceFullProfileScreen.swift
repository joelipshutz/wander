import SwiftUI

/// A Live preview enters the current full place page directly. Routing through
/// Map's notification destination would first display the legacy collapsed card.
struct LivePlaceFullProfileScreen: View {
    let place: VisiblePlace
    let activities: [FeedActivity]
    let onBack: () -> Void
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.astirBrandMode) private var brand
    @State private var saveContext: MapPlaceSaveContext?

    var body: some View {
        PlaceProfileFullScreen(
            place: PlaceSheetPlace(visiblePlace: place),
            saves: summaries,
            tasteSaves: store.currentUserVisiblePlaces.map {
                PlaceSaveSummary(visiblePlace: $0, attributes: store.attributes(for: $0.userPlace.id),
                                 viewerFollowsOwner: false)
            },
            currentUserID: store.currentUser.id,
            action: PlaceSheetAction.topLevelAction(currentUserSave: store.currentUserVisiblePlaces.first {
                VisiblePlaceGrouping.matches($0, place)
            }),
            onBack: onBack, onAction: openSave
        )
        .environment(\.colorScheme, brand.prefersDarkInterface ? .dark : .light)
        .sheet(item: $saveContext, onDismiss: { store.saveFlowDidDismiss(.saveSheet) }) { context in
            MapPlaceSaveFlowSheet(context: context,
                onSave: { submission in
                    await persistAddPlaceSaveSubmission(submission, store: store, backend: auth.isSignedIn ? backend : nil)
                }, onRemove: { context in
                    guard case .editWant(let own) = context.mode else { return false }
                    return await store.removeSave(userPlaceID: own.userPlace.id, backend: auth.isSignedIn ? backend : nil) != nil
                }, onClose: { saveContext = nil }, onSaveCompleted: { _ in saveContext = nil })
        }
        .onChange(of: store.currentUser.id) { _, _ in saveContext = nil; onBack() }
    }

    private func openSave() {
        let own = store.currentUserVisiblePlaces.first { VisiblePlaceGrouping.matches($0, place) }
        let wanna = own.flatMap { store.wannaSaves(for: $0.userPlace).first }
        if let own, own.userPlace.status == .wannaGo || wanna != nil {
            saveContext = .addFromExistingWanna(own, attributes: store.attributes(for: own.userPlace.id),
                latestVisit: store.visits(for: own.userPlace.id).first, wanna: wanna)
        } else if let own {
            saveContext = .existingCurrentUserSave(own, attributes: store.attributes(for: own.userPlace.id),
                latestVisit: store.visits(for: own.userPlace.id).first)
        } else {
            saveContext = .addVisiblePlace(place, defaultVisibility: store.effectiveDefaultVisibility)
        }
        store.saveFlowDidPresent(.saveSheet)
    }

    private var summaries: [PlaceSaveSummary] {
        let visible = (store.visiblePlaces() + activities.compactMap(\.place) + [place]).filter {
            $0.isCommunityAggregate || !store.isBlockedBetweenCurrentUser(and: $0.owner.id)
        }
        return LivePlaceFullProfilePresentation.matchingSaves(selected: place,
            authorizedPlaces: visible,
            viewerID: store.currentUser.id).map { visible in
                let attributes = store.attributes(for: visible.userPlace.id)
                return PlaceSaveSummary(visiblePlace: visible,
                    attributes: attributes.isEmpty ? visible.attributes : attributes,
                    viewerFollowsOwner: store.viewerFollows(visible.owner.id))
            }
    }
}

@MainActor
enum LivePlaceFullProfilePresentation {
    static func matchingSaves(selected: VisiblePlace, authorizedPlaces: [VisiblePlace], viewerID: String) -> [VisiblePlace] {
        var seen = Set<String>()
        return authorizedPlaces.filter {
            $0.owner.deletedAt == nil && $0.userPlace.deletedAt == nil
                && $0.owner.id == $0.userPlace.userID
                && ($0.isCommunityAggregate || $0.owner.id == viewerID || $0.userPlace.visibility != .selfOnly)
                && VisiblePlaceGrouping.matches($0, selected) && seen.insert($0.userPlace.id).inserted
        }.sorted {
            let left = $0.owner.id == viewerID ? 0 : ($0.id == selected.id ? 1 : 2)
            let right = $1.owner.id == viewerID ? 0 : ($1.id == selected.id ? 1 : 2)
            if left != right { return left < right }
            let names = $0.owner.displayName.localizedCaseInsensitiveCompare($1.owner.displayName)
            return names == .orderedSame ? $0.id < $1.id : names == .orderedAscending
        }
    }
}
