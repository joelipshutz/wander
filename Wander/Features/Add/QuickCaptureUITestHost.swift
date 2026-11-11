import SwiftUI

#if DEBUG
/// Simulator-only fixtures exercise the production editor and store save paths.
enum QuickCaptureUITestRoute: String {
    case baselineMap, baselineEditor, quick, past, wanna, details, options, wannaDetails
    case edit, invitation, saved, history, placeHistory, reminders

    static func resolved(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        #if targetEnvironment(simulator)
        guard let index = arguments.firstIndex(of: "-WanderQuickCaptureUITest"),
              arguments.indices.contains(index + 1) else { return nil }
        return Self(rawValue: arguments[index + 1])
        #else
        return nil
        #endif
    }

    var proposesChanges: Bool { self != .baselineMap && self != .baselineEditor }
    var startsExpanded: Bool { [.details, .options, .wannaDetails, .edit].contains(self) }
    var presentsEditor: Bool {
        [.baselineEditor, .quick, .past, .wanna, .details, .options, .wannaDetails, .edit].contains(self)
    }
}

@MainActor
struct QuickCaptureUITestHost: View {
    let route: QuickCaptureUITestRoute
    private let brandMode = AstirBrandMode.editorialLight
    @StateObject private var store: WanderStore
    @StateObject private var auth: AuthSessionStore
    @StateObject private var backend: WanderBackend
    @StateObject private var walkthroughs = FirstVisitWalkthroughCoordinator(isEnabled: false)
    @StateObject private var upsells = ProductUpsellCoordinator(analytics: NoopAnalyticsClient())
    @StateObject private var push = PushNotificationManager(analytics: NoopAnalyticsClient())
    @StateObject private var calendar = CalendarReservationManager(analytics: NoopAnalyticsClient())
    @State private var editor: MapPlaceSaveContext?
    @State private var showsSettings = false
    @State private var initialContext: MapPlaceSaveContext
    private var visit: LocalPlaceVisit {
        store.placeVisits.first { $0.localID == "quick-review-recent" }!
    }
    private var own: VisiblePlace {
        store.currentUserVisiblePlaces.first { $0.userPlace.id == visit.userPlaceID }!
    }

    init(route: QuickCaptureUITestRoute) {
        self.route = route
        let seed = WanderFixtures.seed()
        var fixtures = WanderFixtures(currentUser: seed.currentUser, profiles: seed.profiles,
            places: seed.places, userPlaces: seed.userPlaces, placeAttributes: [],
            placeVisits: seed.placeVisits, follows: seed.follows, blocks: seed.blocks,
            placeLists: seed.placeLists, placeListMembers: seed.placeListMembers,
            placeListItems: seed.placeListItems, contactProvider: seed.contactProvider)
        let userPlace = fixtures.userPlaces.first { $0.userID == fixtures.currentUser.id && $0.status == .been }!
        let recent = LocalPlaceVisit(localID: "quick-review-recent", userPlaceID: userPlace.id,
            visitedAt: .now.addingTimeInterval(-3600), ratingScore: nil,
            detailsPending: [.invitation, .saved, .edit].contains(route))
        let older = LocalPlaceVisit(localID: "quick-review-older", userPlaceID: userPlace.id,
            visitedAt: .now.addingTimeInterval(-7 * 86400), note: "A good spot for a slow morning.", ratingScore: 4.5)
        fixtures.placeVisits.removeAll { $0.userPlaceID == userPlace.id }
        fixtures.placeVisits.append(contentsOf: [recent, older])
        let store = WanderStore(fixtures: fixtures, placeResolver: StorefrontPlaceResolver())
        let own = store.currentUserVisiblePlaces.first { $0.userPlace.id == userPlace.id }!
        _ = store.createPlaceList(name: "Weekend ideas", description: "", visibility: .followers)
        let candidate = PlaceCandidate(id: own.place.id, name: own.place.canonicalName,
            category: own.place.category, locality: "Los Angeles", region: "CA", latitude: own.place.latitude, longitude: own.place.longitude,
            sourceProvider: "manual", confidence: 1)
        let context: MapPlaceSaveContext
        if route == .edit {
            context = .editVisit(recent, visiblePlace: own)
        } else if route == .past {
            context = .calendarReservation(candidate,
                reservationID: "quick-review-past", visitedAt: recent.visitedAt, defaultVisibility: .followers)
        } else {
            context = .importCandidate(candidate, sourceType: .manual,
                status: [.wanna, .wannaDetails].contains(route) ? .wannaGo : .been, defaultVisibility: .followers)
        }
        _initialContext = State(initialValue: context)
        _store = StateObject(wrappedValue: store)
        _auth = StateObject(wrappedValue: AuthSessionStore(provider: PreviewAuthSessionProvider(
            state: .signedIn(AuthSession(userID: store.currentUser.id, displayName: "Joe", handle: "joe")))))
        _backend = StateObject(wrappedValue: WanderBackend(placeRepository: StorefrontPlaceResolver(),
            notificationRepository: SimulatorNotificationRepository()))
    }

    var body: some View {
        WanderRootView(initialTab: [.history, .placeHistory, .reminders].contains(route) ? .profile : .map,
            initialSession: auth.state.session, storeFactory: { store }, fixtureMode: .demo)
            .sheet(item: $editor) { context in
                MapPlaceSaveFlowSheet(context: context,
                    draft: editorDraft(for: context),
                    onSave: { submission in
                        if case .add = submission.context.mode {
                            return await persistNewPlaceSaveSubmission(submission, store: store, backend: nil)
                        }
                        let (result, target) = await persistScopedVisitOrWantSubmission(submission, store: store, backend: nil)
                        await persistVisitPhotoAttachments(submission.photoAttachments, to: target, store: store, backend: nil)
                        return result
                    }, onRemove: { _ in false }, onClose: { editor = nil },
                    onSaveCompleted: { _ in editor = nil })
            }
            .sheet(isPresented: $showsSettings) { NotificationSettingsSheet() }
            .overlay(alignment: .bottom) {
                Text(store.placeVisits.filter { $0.deletedAt == nil }.map {
                    "\($0.id):\($0.ratingScore.map(String.init(describing:)) ?? "unrated"):pending=\($0.detailsPending == true)"
                }.sorted().joined(separator: "|"))
                .font(.system(size: 1)).opacity(0.01).allowsHitTesting(false)
                .accessibilityIdentifier("quick-capture-test.state")
            }
            .environmentObject(store)
            .environmentObject(auth)
            .environmentObject(backend)
            .environmentObject(walkthroughs)
            .environmentObject(upsells)
            .environmentObject(push)
            .environmentObject(calendar)
            .environment(\.presentPlaceActivityEdit, { presentation in editor = presentation.context })
            .modelContainer(WanderModelContainer.preview)
            .astirAdaptiveBrandMode()
            .preferredColorScheme(.light)
            .task {
                try? await Task.sleep(for: .milliseconds(900))
                if route.presentsEditor { editor = initialContext }
                if route == .reminders { showsSettings = true }
            }
    }

    private func editorDraft(for context: MapPlaceSaveContext) -> PlaceSaveDraft? {
        guard route.startsExpanded, !context.isEditing else { return nil }
        var draft = PlaceSaveDraft.addFlow(ownerUserID: store.currentUser.id, context: context)
        draft?.form.detailsExpanded = true
        return draft
    }
}
#endif
