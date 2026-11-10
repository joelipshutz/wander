import SwiftUI

#if DEBUG
/// Explicit, local-only design routes inside the shipping app target.
enum QuickCaptureReviewRoute: String {
    case baselineMap, baselineEditor, quick, past, wanna, details, options, wannaDetails
    case edit, invitation, saved, history, placeHistory, reminders

    static func resolved(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        #if targetEnvironment(simulator)
        guard let index = arguments.firstIndex(of: "-WanderQuickCaptureReview"),
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
struct QuickCaptureReviewHost: View {
    let route: QuickCaptureReviewRoute
    private let brandMode = AstirBrandMode.editorialLight
    @StateObject private var store: WanderStore
    @StateObject private var auth: AuthSessionStore
    @StateObject private var backend: WanderBackend
    @StateObject private var walkthroughs = FirstVisitWalkthroughCoordinator(isEnabled: false)
    @StateObject private var upsells = ProductUpsellCoordinator(analytics: NoopAnalyticsClient())
    @StateObject private var push = PushNotificationManager(analytics: NoopAnalyticsClient())
    @StateObject private var calendar = CalendarReservationManager(analytics: NoopAnalyticsClient())
    @State private var editor: MapPlaceSaveContext?
    @State private var showsInvitation: Bool
    @State private var showsSettings = false
    @State private var saved = false
    @State private var initialContext: MapPlaceSaveContext
    private var visit: LocalPlaceVisit {
        store.placeVisits.first { $0.localID == "quick-review-recent" }!
    }
    private var own: VisiblePlace {
        store.currentUserVisiblePlaces.first { $0.userPlace.id == visit.userPlaceID }!
    }

    init(route: QuickCaptureReviewRoute) {
        self.route = route
        let seed = WanderFixtures.seed()
        var fixtures = WanderFixtures(currentUser: seed.currentUser, profiles: seed.profiles,
            places: seed.places, userPlaces: seed.userPlaces, placeAttributes: [],
            placeVisits: seed.placeVisits, follows: seed.follows, blocks: seed.blocks,
            placeLists: seed.placeLists, placeListMembers: seed.placeListMembers,
            placeListItems: seed.placeListItems, contactProvider: seed.contactProvider)
        let userPlace = fixtures.userPlaces.first { $0.userID == fixtures.currentUser.id && $0.status == .been }!
        let recent = LocalPlaceVisit(localID: "quick-review-recent", userPlaceID: userPlace.id,
            visitedAt: .now.addingTimeInterval(-3600), ratingScore: nil)
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
        _showsInvitation = State(initialValue: route == .invitation || route == .saved)
        _saved = State(initialValue: route == .saved)
    }

    var body: some View {
        WanderRootView(initialTab: [.history, .placeHistory, .reminders].contains(route) ? .profile : .map,
            initialSession: auth.state.session, storeFactory: { store }, fixtureMode: .demo)
            .overlay(alignment: .top) {
                if showsInvitation {
                    invitation
                        .padding(.horizontal, WanderTheme.spacing4)
                        .padding(.top, 110)
                }
            }
            .sheet(item: $editor) { context in
                MapPlaceSaveFlowSheet(context: context,
                    onSave: { submission in
                        // Review-only, in-memory exact-visit update. No production save/RPC.
                        visit.ratingScore = submission.ratingScore
                        visit.note = submission.note
                        visit.visitedAt = submission.visitedAt
                        store.objectWillChange.send()
                        return SaveResult(userPlaceID: own.userPlace.id, syncState: .localOnly, placeID: own.place.id)
                    }, onRemove: { _ in false }, onClose: { editor = nil },
                    onSaveCompleted: { _ in editor = nil; saved = true; showsInvitation = true })
            }
            .sheet(isPresented: $showsSettings) { NotificationSettingsSheet() }
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

    private var invitation: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            CategoryThumb(emoji: own.categoryEmoji, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(saved ? "Checked in" : "Your recent check-in")
                    .font(AstirTypography.caption).foregroundStyle(brandMode.secondaryText)
                Text(own.place.canonicalName).font(AstirTypography.cardTitle)
                    .foregroundStyle(brandMode.primaryText)
                Text(visit.visitedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(AstirTypography.caption).foregroundStyle(brandMode.secondaryText)
                Button("Add details") { editor = .editVisit(visit, visiblePlace: own) }
                    .font(AstirTypography.control).foregroundStyle(brandMode.accentText)
                    .frame(minHeight: 44).accessibilityIdentifier("quick-review.addDetails")
            }
            Spacer(minLength: 0)
            Button { showsInvitation = false } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                    .frame(width: 44, height: 44)
            }.foregroundStyle(brandMode.secondaryText)
                .accessibilityLabel("Dismiss check-in invitation")
        }
        .padding(WanderTheme.spacing3)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quick-review.invitation")
        .accessibilityValue(visit.ratingScore.map { String($0) } ?? "unrated")
    }
}
#endif
