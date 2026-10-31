import SwiftUI

/// A Live preview enters the current full place page directly. Routing through
/// Map's notification destination would first display the legacy collapsed card.
struct LivePlaceFullProfileScreen: View {
    private let visiblePlace: VisiblePlace?
    private let candidate: PlaceCandidate
    private let sheetPlace: PlaceSheetPlace
    private let identity: LivePlaceIdentity?
    let activities: [FeedActivity]
    let onBack: () -> Void
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.astirBrandMode) private var brand
    @State private var saveContext: MapPlaceSaveContext?

    init(place: VisiblePlace, activities: [FeedActivity], identity: LivePlaceIdentity? = nil,
         onBack: @escaping () -> Void) {
        let sheetPlace = PlaceSheetPlace(visiblePlace: place)
        visiblePlace = place
        self.sheetPlace = sheetPlace
        self.identity = identity
        candidate = sheetPlace.saveCandidate
        self.activities = activities
        self.onBack = onBack
    }

    init(candidate: PlaceCandidate, onBack: @escaping () -> Void) {
        visiblePlace = nil
        identity = nil
        sheetPlace = PlaceSheetPlace(candidate: candidate)
        self.candidate = candidate
        activities = []
        self.onBack = onBack
    }

    private var currentUserSave: VisiblePlace? {
        LivePlaceSaveContinuation.matchingOwnPlaces(candidate: candidate, identity: identity, store: store).first
    }

    var body: some View {
        PlaceProfileFullScreen(
            place: sheetPlace,
            saves: summaries,
            tasteSaves: tasteSummaries,
            currentUserID: store.currentUser.id,
            action: PlaceSheetAction.topLevelAction(currentUserSave: currentUserSave),
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
        saveContext = LivePlaceSaveContinuation.context(candidate: candidate,
            visiblePlace: visiblePlace, identity: identity, store: store)
        store.saveFlowDidPresent(.saveSheet)
    }

    private var tasteSummaries: [PlaceSaveSummary] {
        let visiblePlaces = store.currentUserVisiblePlaces
        let attributesByID = store.attributesByUserPlaceID(for: visiblePlaces.map { $0.userPlace.id })
        return visiblePlaces.map {
            PlaceSaveSummary(visiblePlace: $0, attributes: attributesByID[$0.userPlace.id] ?? [],
                             viewerFollowsOwner: false)
        }
    }

    private var summaries: [PlaceSaveSummary] {
        let visible = (store.visiblePlaces() + activities.compactMap(\.place)
            + [visiblePlace].compactMap { $0 }).filter {
            $0.isCommunityAggregate || !store.isBlockedBetweenCurrentUser(and: $0.owner.id)
        }
        let matching: [VisiblePlace]
        if let visiblePlace {
            matching = LivePlaceFullProfilePresentation.matchingSaves(selected: visiblePlace, identity: identity,
                authorizedPlaces: visible, viewerID: store.currentUser.id)
        } else {
            matching = LivePlaceFullProfilePresentation.matchingSaves(candidate: candidate,
                authorizedPlaces: visible, viewerID: store.currentUser.id)
        }
        let attributesByID = store.attributesByUserPlaceID(for: matching.map { $0.userPlace.id })
        return matching.map { visible in
            let attributes = attributesByID[visible.userPlace.id] ?? []
            return PlaceSaveSummary(visiblePlace: visible,
                attributes: attributes.isEmpty ? visible.attributes : attributes,
                viewerFollowsOwner: store.viewerFollows(visible.owner.id))
        }
    }
}

@MainActor
enum LivePlaceFullProfilePresentation {
    static func matchingSaves(selected: VisiblePlace, identity: LivePlaceIdentity? = nil,
                              authorizedPlaces: [VisiblePlace], viewerID: String) -> [VisiblePlace] {
        matchingSaves(authorizedPlaces: authorizedPlaces, viewerID: viewerID, selectedID: selected.id) {
            identity?.matches($0.place) ?? VisiblePlaceGrouping.matches($0, selected)
        }
    }

    static func matchingSaves(candidate: PlaceCandidate, authorizedPlaces: [VisiblePlace], viewerID: String) -> [VisiblePlace] {
        matchingSaves(authorizedPlaces: authorizedPlaces, viewerID: viewerID, selectedID: nil) {
            VisiblePlaceGrouping.matches($0, candidate: candidate)
        }
    }

    private static func matchingSaves(authorizedPlaces: [VisiblePlace], viewerID: String,
                                      selectedID: String?, matches: (VisiblePlace) -> Bool) -> [VisiblePlace] {
        var seen = Set<String>()
        return authorizedPlaces.filter {
            $0.owner.deletedAt == nil && $0.userPlace.deletedAt == nil
                && $0.owner.id == $0.userPlace.userID
                && ($0.isCommunityAggregate || $0.owner.id == viewerID || $0.userPlace.visibility != .selfOnly)
                && matches($0) && seen.insert($0.userPlace.id).inserted
        }.sorted {
            let left = $0.owner.id == viewerID ? 0 : ($0.id == selectedID ? 1 : 2)
            let right = $1.owner.id == viewerID ? 0 : ($1.id == selectedID ? 1 : 2)
            if left != right { return left < right }
            let names = $0.owner.displayName.localizedCaseInsensitiveCompare($1.owner.displayName)
            return names == .orderedSame ? $0.id < $1.id : names == .orderedAscending
        }
    }
}
