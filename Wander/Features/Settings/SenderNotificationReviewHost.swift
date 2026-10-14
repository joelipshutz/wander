#if DEBUG
import SwiftUI
import SwiftData

/// Native review routes reuse the shipping views, with an isolated sample store.
/// They never use the signed-in account, analytics, or a remote write repository.
enum SenderNotificationReviewRoute: String, CaseIterable, Identifiable {
    case gallery, checkIn, repeatCheckIn, historical, wanna, repeatWanna, sourceSave
    case edit, editWithLists, friends, sharedVisit, listPicker, multiListPicker
    case lists, discover, importOne, importTen, importConsumed, importDetails
    var id: String { rawValue }
    static func resolved() -> Self? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-WanderSenderReview"), args.indices.contains(index + 1) else { return ProcessInfo.processInfo.environment["WANDER_SENDER_REVIEW"].flatMap(Self.init(rawValue:)) }
        return Self(rawValue: args[index + 1])
    }
    var title: String {
        switch self {
        case .gallery: "Sender notification review"
        case .checkIn: "First check-in"
        case .repeatCheckIn: "Repeat check-in"
        case .historical: "Historical check-in"
        case .wanna: "First Wanna"
        case .repeatWanna: "Repeat Wanna"
        case .sourceSave: "Save from a person"
        case .edit: "Edit existing content"
        case .editWithLists: "Edit and add to lists"
        case .friends: "Check-in with invited friends"
        case .sharedVisit: "Accept a shared check-in"
        case .listPicker: "Add one place to lists"
        case .multiListPicker: "Add several places to lists"
        case .lists: "List suggestions and search"
        case .discover: "Discover quick Wanna"
        case .importOne: "One-place import"
        case .importTen: "Ten-place import: three now, seven later"
        case .importConsumed: "Import after its first save"
        case .importDetails: "Inline import details"
        }
    }
    var isImport: Bool { [.importOne, .importTen, .importConsumed, .importDetails].contains(self) }
}

@MainActor
struct SenderNotificationReviewHost: View {
    let route: SenderNotificationReviewRoute
    @StateObject private var store: WanderStore
    @StateObject private var importStore: PlaceImportStore
    @StateObject private var auth: AuthSessionStore
    @StateObject private var backend: WanderBackend
    @StateObject private var walkthroughs = FirstVisitWalkthroughCoordinator(isEnabled: false)
    @StateObject private var upsells = ProductUpsellCoordinator(analytics: NoopAnalyticsClient())
    @StateObject private var push = PushNotificationManager(analytics: NoopAnalyticsClient())
    @State private var showsForm = false
    @State private var selectedScenario: SenderNotificationReviewRoute?
    @State private var submittedPolicy: SenderNotificationPolicy?
    private let context: MapPlaceSaveContext
    private let draft: PlaceSaveDraft?
    private let initialUserPlaceIDs: Set<String>
    private let initialVisitIDs: Set<String>
    private let initialWannaIDs: Set<String>
    private let initialListItemIDs: Set<String>
    static let batchID = "sender-review-import"
    static let candidate = StorefrontPlaceResolver.candidates[0]

    init(route: SenderNotificationReviewRoute) {
        self.route = route
        let store = WanderStore(fixtures: .seed(), placeResolver: StorefrontPlaceResolver())
        _ = store.createPlaceList(name: "Weekend ideas", description: "Sample review list", visibility: .followers)
        _ = store.createPlaceList(name: "Coffee stops", description: "Sample review list", visibility: .followers)
        let own = store.currentUserVisiblePlaces.first { $0.userPlace.status == .been }!
        let prior = store.visits(for: own.userPlace.id).first!
        let context: MapPlaceSaveContext
        switch route {
        case .repeatCheckIn:
            context = .addVisitVisiblePlace(own, attributes: [], latestVisit: prior)
        case .historical:
            context = .calendarReservation(Self.candidate, reservationID: "sender-review-history",
                visitedAt: Calendar.current.date(byAdding: .month, value: -2, to: .now)!, defaultVisibility: .followers)
        case .edit, .editWithLists:
            context = .editVisit(prior, visiblePlace: own)
        case .repeatWanna:
            context = MapPlaceSaveContext.addWannaVisiblePlace(own, defaultVisibility: .followers).freshWannaContext()
        case .sourceSave:
            let source = store.visiblePlaces().first { $0.userPlace.userID != store.currentUser.id }!
            context = .addWannaVisiblePlace(source, defaultVisibility: .followers)
        case .sharedVisit:
            context = .sharedVisit(Self.invitation, defaultVisibility: .followers)
        default:
            context = .importCandidate(Self.candidate, sourceType: .manual,
                status: route == .wanna ? .wannaGo : .been, defaultVisibility: .followers)
        }
        self.context = context
        var draft = PlaceSaveDraft.restorableFlow(ownerUserID: store.currentUser.id, context: context)
        if route == .friends { draft?.form.selectedInviteeUserIDs = ["user_maya"] }
        self.draft = draft
        self.initialUserPlaceIDs = Set(store.userPlaces.map(\.id))
        self.initialVisitIDs = Set(store.placeVisits.map(\.id))
        self.initialWannaIDs = Set(store.placeWannaSaves.map(\.id))
        self.initialListItemIDs = Set(store.placeListItems.map(\.id))
        _store = StateObject(wrappedValue: store)
        _auth = StateObject(wrappedValue: AuthSessionStore(provider: PreviewAuthSessionProvider(
            state: .signedIn(AuthSession(userID: store.currentUser.id, displayName: "Joe", handle: "joe")))))
        _backend = StateObject(wrappedValue: WanderBackend(placeRepository: StorefrontPlaceResolver()))
        let count = route == .importOne ? 1 : 10
        let batch = PlaceImportBatch(id: Self.batchID, source: .textNotes, sourceName: "Saved places",
            state: .ready, totalCount: count, processedCount: count)
        let items = (0..<count).map { index in
            let candidate = PlaceCandidate(id: "sender-review-place-\(index)", name: Self.names[index],
                category: "coffee", address: "\(index + 1) Orchard Walk", locality: "Los Angeles", region: "CA",
                latitude: 34.07 + Double(index) * 0.002, longitude: -118.28, sourceProvider: "manual", confidence: 1)
            return PlaceImportItem(id: "sender-review-item-\(index)", batchID: batch.id, source: .textNotes,
                seed: PlaceImportSeed(rawText: candidate.name, nameHint: candidate.name, areaHint: "Los Angeles", sourceURLString: nil, sourceLine: index + 1),
                state: .ready, candidates: [candidate], selectedCandidateID: candidate.id)
        }
        let persistence = EphemeralPlaceImportPersistence()
        try? persistence.save(PlaceImportSnapshot(batches: [batch], items: items))
        _importStore = StateObject(wrappedValue: PlaceImportStore(persistence: persistence))
        if route == .importConsumed {
            let policy = store.beginImportNotificationCommit(batch, silent: true)
            store.completeImportNotificationCommit(policy)
        }
    }

    var body: some View {
        content
            .environmentObject(store).environmentObject(importStore)
            .environmentObject(auth).environmentObject(backend)
            .environmentObject(walkthroughs).environmentObject(upsells).environmentObject(push)
            .modelContainer(WanderModelContainer.preview)
            .astirAdaptiveBrandMode()
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-WanderSenderDark") ? .dark : .light)
            // The invisible, DEBUG-only probe exposes counts and choices, never
            // personal content. UI tests inspect actual store results after Save.
            .overlay(alignment: .topLeading) {
                Text("Review state").font(.system(size: 1)).opacity(0.01)
                    .accessibilityIdentifier("sender-review.state").accessibilityValue(stateSummary)
            }
    }

    @ViewBuilder private var content: some View {
        if route == .gallery {
            NavigationStack {
                List(SenderNotificationReviewRoute.allCases.filter { $0 != .gallery }) { route in
                    Button(route.title) { selectedScenario = route }
                }.navigationTitle("Silent controls")
            }
            .fullScreenCover(item: $selectedScenario) { scenario in
                SenderNotificationReviewHost(route: scenario)
                    .safeAreaInset(edge: .bottom) {
                        Button("Back to scenarios") { selectedScenario = nil }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(.regularMaterial)
                            .accessibilityIdentifier("sender-review.back")
                    }
            }
        } else if route.isImport {
            NavigationStack {
                PlaceImportCanonicalReviewScreen(importStore: importStore, batchIDs: [Self.batchID], onDone: {},
                    initiallyExpandedDetailItemID: route == .importDetails ? "sender-review-item-0" : nil)
            }
        } else if route == .lists {
            ListsScreen(scenario: .live)
        } else if route == .discover {
            DiscoverScreen(startsInPlaceSearch: true)
        } else {
            NavigationStack {
                VStack(spacing: 16) {
                    Text(route.title).font(AstirTypography.sheetTitle)
                    Text("Sample data · native app controls").font(AstirTypography.bodySmall)
                    Button("Open scenario") { showsForm = true }.buttonStyle(.borderedProminent)
                }.padding().navigationTitle("Silent review")
            }
            .onAppear { showsForm = true }
            .sheet(isPresented: $showsForm) {
                if route == .listPicker || route == .multiListPicker {
                    MapPlaceListPickerSheet(target: .candidate(Self.candidate),
                        additionalTargets: route == .multiListPicker ? [.candidate(StorefrontPlaceResolver.candidates[1])] : [],
                        onComplete: { _ in showsForm = false })
                } else {
                    MapPlaceSaveFlowSheet(context: context, draft: draft, onSave: { submission in
                        submittedPolicy = submission.senderNotificationPolicy
                        // Shared acceptance's server transaction has separate SQL
                        // coverage; this scenario inspects the native submission.
                        if route == .sharedVisit { showsForm = false; return nil }
                        return await persistAddPlaceSaveSubmission(submission, store: store, backend: nil)
                    }, onRemove: { _ in false }, onClose: { showsForm = false },
                    onSaveCompleted: { _ in showsForm = false })
                }
            }
        }
    }

    private var stateSummary: String {
        let visits = store.placeVisits.filter { !initialVisitIDs.contains($0.id) && !$0.backfilledFromUserPlace }
        let wannas = store.placeWannaSaves.filter { !initialWannaIDs.contains($0.id) }
        let items = store.placeListItems.filter { !initialListItemIDs.contains($0.id) }
        let saves = store.userPlaces.filter { !initialUserPlaceIDs.contains($0.id) && $0.userID == store.currentUser.id }
        let commit = store.importNotificationCommits.first
        return ["saves=\(saves.count)", "silentSaves=\(saves.filter { $0.senderNotificationPolicy.suppressesIndividualAlerts }.count)", "visits=\(visits.count)", "silentVisits=\(visits.filter { $0.senderNotificationPolicy.suppressesIndividualAlerts }.count)",
            "wannas=\(wannas.count)",
            "items=\(items.count)", "silentItems=\(items.filter { $0.senderNotificationPolicy.suppressesIndividualAlerts }.count)",
            "commits=\(store.importNotificationCommits.count)", "manifest=\(commit?.visitIDs.count ?? 0)",
            "importSilent=\(commit.map { String($0.silent) } ?? "unset")", "complete=\(commit?.locallyComplete ?? false)",
            "submitted=\(submittedPolicy.map { String($0.silent) } ?? "unset")",
            "manifestIDs=\(commit?.visitIDs.sorted().joined(separator: ",") ?? "")"].joined(separator: ";")
    }
    private static let names = ["Sparrow Bakery", "Clover & Pine", "Moonrise Books", "Honeycomb Cafe",
        "Orchard Kitchen", "Juniper Coffee", "Maple Table", "Fern Corner", "Garden Market", "Willow House"]
    private static var invitation: SharedVisitInvitation {
        SharedVisitInvitation(participantID: "sender-review-invitation", groupID: "sender-review-group",
            invitationGeneration: 1, snapshotRevision: 1, status: .pending, invitedAt: .now,
            sourceVisitID: "sender-review-source", sourceOwnerUserID: "user_maya", sourceOwnerHandle: "maya",
            sourceOwnerDisplayName: "Maya", sourceOwnerAvatarURL: nil, placeID: candidate.id, placeName: candidate.name,
            category: "coffee", primaryCategory: candidate.primaryCategory, subcategory: nil, address: candidate.address,
            locality: candidate.locality, region: candidate.region, country: "US", latitude: candidate.latitude!,
            longitude: candidate.longitude!, sourceProvider: "manual", sourceProviderPlaceID: candidate.id,
            visitedAt: .now, note: nil, ratingScore: nil, attributeAnswers: [], tags: [], photos: [])
    }
}
#endif
