import SwiftUI

enum PlaceRatingExplanation: String, CaseIterable, Identifiable {
    case ratings

    var id: String { rawValue }

    var title: String {
        "Ratings"
    }

    var message: String {
        paragraphs.joined(separator: " ")
    }

    var paragraphs: [String] {
        [
            "Your rating averages your rated check-ins here.",
            "Friends rating averages each followed person's visible ratings; activity hidden from you does not count.",
            "Astir rating averages all rated check-ins, including private activity, without showing who contributed.",
            "A dash means there are no ratings yet."
        ]
    }

    var accessibilityLabel: String {
        "About the \(title)"
    }
}

/// Only rating-bearing data and authorization changes restart the rail. Photo,
/// note, category and general persistence revisions are deliberately absent.
/// These are invalidation inputs, not a replacement for server aggregates.
struct PlaceRatingsRequestKey: Hashable {
    struct RatingRow: Hashable {
        let id: String
        let serverID: String?
        let ownerID: String
        let score: Double?
        let aggregateScore: Double?
        let count: Int
        let syncState: String
        let deleted: Bool
    }

    let viewerID: String
    let placeID: String
    let lookup: PlaceRatingLookup
    let sessionRevision: Int
    let backendViewerID: String?
    let accessRevision: Int
    let active: Bool
    let retry: Int
    let relationships: Set<[String]>
    let privateProfiles: Set<[String]>
    let permissions: Set<[String]>
    let ratings: Set<RatingRow>
    let ownScore: Double?
    let ownCount: Int

    @MainActor
    init(store: WanderStore, place: PlaceSheetPlace, backend: WanderBackend,
         active: Bool, retry: Int, ownRating: PlaceActualRating?) {
        viewerID = store.currentUser.id
        placeID = place.id
        lookup = PlaceRatingLookup(candidate: place.saveCandidate, knownPlaces: store.places)
        sessionRevision = backend.photoSessionRevision
        backendViewerID = backend.photoViewerID
        accessRevision = backend.photoAccessRevision
        self.active = active
        self.retry = retry
        ownScore = ownRating?.score
        ownCount = ownRating?.count ?? 0
        let viewer = store.currentUser.id
        let follows = store.follows.filter { $0.followerUserID == viewer || $0.followedUserID == viewer }
        let blocks = store.blocks.filter { $0.blockerUserID == viewer || $0.blockedUserID == viewer }
        relationships = Set(follows.map { ["follow", $0.followerUserID, $0.followedUserID] }
            + blocks.map { ["block", $0.blockerUserID, $0.blockedUserID] })

        let matches = store.places.filter { VisiblePlaceGrouping.matches($0, candidate: place.saveCandidate) }
        let placeIDs = Set(matches.flatMap { [$0.localID, $0.id] } + [place.id])
        let saves = store.userPlaces.filter { placeIDs.contains($0.placeID) }
            + store.remoteVisiblePlaceCache.filter {
                VisiblePlaceGrouping.matches($0.place, candidate: place.saveCandidate)
            }.map(\.userPlace)
        let owners = Set(saves.map(\.userID) + follows.flatMap { [$0.followerUserID, $0.followedUserID] } + [viewer])
        privateProfiles = Set((store.profiles + [store.currentUser])
            .filter { owners.contains($0.id) && ($0.isPrivateProfile || $0.deletedAt != nil) }
            .map { [$0.id, String($0.isPrivateProfile), String($0.deletedAt != nil)] })
        let saveIDs = Set(saves.flatMap { [$0.localID, $0.id] })
        let visits = store.placeVisits.filter { saveIDs.contains($0.userPlaceID) }
        permissions = Set(saves.map {
            [$0.localID, $0.userID, $0.visibilityRaw, $0.statusRaw, String($0.deletedAt != nil)]
        } + visits.map { ["visit", $0.localID, String($0.deletedAt != nil)] })
        ratings = Set(saves.map {
            RatingRow(id: $0.localID, serverID: $0.serverID, ownerID: $0.userID,
                score: $0.ratingScore, aggregateScore: $0.recommendedScore, count: $0.recommendedCount,
                syncState: $0.syncStateRaw, deleted: $0.deletedAt != nil)
        } + visits.map {
            RatingRow(id: $0.localID, serverID: $0.serverID, ownerID: $0.userPlaceID,
                score: $0.ratingScore, aggregateScore: nil, count: 1, syncState: $0.syncStateRaw, deleted: $0.deletedAt != nil)
        })
    }

    func canRetainValues(for next: Self) -> Bool {
        // Additive history hydration may refresh in place. A removed/restricted
        // row, relationship change, session change or backgrounding hides the
        // previous values immediately, before the new task gets scheduled.
        active && next.active && viewerID == next.viewerID && placeID == next.placeID
            && lookup == next.lookup && sessionRevision == next.sessionRevision
            && backendViewerID == next.backendViewerID && accessRevision == next.accessRevision
            && relationships == next.relationships && privateProfiles == next.privateProfiles
            && permissions.isSubset(of: next.permissions)
    }
}

@MainActor
final class PlaceRatingsLoader: ObservableObject {
    @Published private var state: PlaceRatingsState = .loading
    private var loadedKey: PlaceRatingsRequestKey?
    private var generation = 0

    func state(for key: PlaceRatingsRequestKey) -> PlaceRatingsState {
        loadedKey?.canRetainValues(for: key) == true ? state : .loading
    }

    func refresh(key: PlaceRatingsRequestKey,
                 load: () async throws -> PlaceRatingSummaries) async {
        generation += 1
        let requestGeneration = generation
        if loadedKey?.canRetainValues(for: key) != true { state = .loading }
        loadedKey = key
        guard key.active else { return }
        do {
            let summaries = try await load()
            guard !Task.isCancelled, generation == requestGeneration else { return }
            state = .loaded(summaries)
        } catch {
            guard !Task.isCancelled, generation == requestGeneration else { return }
            state = .unavailable
        }
    }

    func clear() {
        generation += 1
        loadedKey = nil
        state = .loading
    }
}

struct PlaceProfileRatingsRail: View {
    let presentation: PlaceProfilePresentation
    let place: PlaceSheetPlace
    var compact = false

    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var loader = PlaceRatingsLoader()
    @State private var retryGeneration = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.placeProfileVisualStyle) private var visualStyle
    @Environment(\.astirBrandMode) private var astirBrandMode

    private var requestKey: PlaceRatingsRequestKey {
        PlaceRatingsRequestKey(store: store, place: place, backend: backend,
            active: scenePhase == .active, retry: retryGeneration,
            ownRating: presentation.ownRating)
    }

    private var currentState: PlaceRatingsState {
        loader.state(for: requestKey)
    }

    private var metrics: [PlaceRatingMetric] {
        currentState.metrics
    }

    @MainActor
    private func refreshRatings() async {
        let key = requestKey
        await loader.refresh(key: key) {
            if !key.lookup.canQuery {
                // Unsynced owner-only fallback; never synthesize an Astir score.
                let own = try PlaceRatingAggregate(score: presentation.ownRating?.score,
                                                   count: presentation.ownRating?.count ?? 0)
                return PlaceRatingSummaries(own: own, friends: .empty, astir: .empty)
            }
            return try await backend.placeRatingSummaries(for: key.lookup)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? WanderTheme.spacing1 : WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing1) {
                Text("Ratings")
                    .font(
                        visualStyle == .astir
                            ? (compact ? AstirTypography.cardTitle : AstirTypography.sectionTitle)
                            : (compact ? WanderTypography.editorialCompactTitle : WanderTypography.editorialSectionTitle)
                    )
                    .foregroundStyle(primaryText)

                Spacer(minLength: WanderTheme.spacing2)

                PlaceRatingInfoButton(
                    explanation: .ratings,
                    tint: secondaryText
                )
            }
            .frame(minHeight: WanderTheme.tapMinimum)

            if dynamicTypeSize.isAccessibilitySize {
                accessibilityMetrics
            } else {
                horizontalMetrics
            }

            if currentState == .unavailable {
                Button("Retry ratings") { retryGeneration += 1 }
                    .font(AstirTypography.label)
                    .frame(minHeight: WanderTheme.tapMinimum)
            }
        }
        .accessibilityElement(children: .contain)
        .task(id: requestKey) { await refreshRatings() }
        .onDisappear { loader.clear() }
    }

    private var horizontalMetrics: some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                metricCell(metric)

                if index < metrics.count - 1 {
                    Rectangle()
                        .fill(borderColor)
                        .frame(width: 1, height: compact ? 64 : 76)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, compact ? WanderTheme.spacing2 : WanderTheme.spacing3)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)
        }
    }

    private var accessibilityMetrics: some View {
        VStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing3) {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text(metric.title)
                            .font(
                                visualStyle == .astir
                                    ? AstirTypography.label
                                    : WanderTypography.label
                            )
                            .foregroundStyle(primaryText)
                        Text(metric.subtitle)
                            .font(
                                visualStyle == .astir
                                    ? AstirTypography.metadata
                                    : WanderTypography.metadata
                            )
                            .foregroundStyle(secondaryText)
                    }

                    Spacer(minLength: WanderTheme.spacing2)

                    metricValue(metric)
                }
                .padding(.vertical, WanderTheme.spacing3)

                if index < metrics.count - 1 {
                    Rectangle()
                        .fill(borderColor)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
        }
        .overlay(
            Rectangle()
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private func metricCell(_ metric: PlaceRatingMetric) -> some View {
        VStack(spacing: WanderTheme.spacing1) {
            metricValue(metric)

            Text(metric.title)
                .font(
                    visualStyle == .astir
                        ? AstirTypography.label
                        : .system(size: compact ? 11 : 12, weight: .bold)
                )
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(metric.subtitle)
                .font(
                    visualStyle == .astir
                        ? AstirTypography.caption
                        : .system(size: compact ? 9.5 : 10.5, weight: .medium)
                )
                .foregroundStyle(secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .frame(minHeight: compact ? 22 : 26, alignment: .top)
        }
        .padding(.horizontal, compact ? WanderTheme.spacing1 : WanderTheme.spacing2)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title), \(metric.value)\(metric.suffix), \(metric.subtitle)")
    }

    private func metricValue(_ metric: PlaceRatingMetric) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(metric.value)
                .font(
                    visualStyle == .astir
                        ? AstirTypography.metricDisplay
                        : WanderTypography.editorialRatingDisplay
                )
                .foregroundStyle(visualStyle == .astir ? astirBrandMode.accentText : WanderTheme.textInk.color)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text(metric.suffix)
                .font(
                    visualStyle == .astir
                        ? AstirTypography.metricSuffix
                        : WanderTypography.editorialRatingSuffix
                )
                .foregroundStyle(secondaryText)
        }
    }

    private var primaryText: Color {
        visualStyle == .astir ? astirBrandMode.primaryText : WanderTheme.textInk.color
    }

    private var secondaryText: Color {
        visualStyle == .astir ? astirBrandMode.secondaryText : WanderTheme.textMuted.color
    }

    private var borderColor: Color {
        visualStyle == .astir ? astirBrandMode.border : WanderTheme.borderHairline.color
    }

}

struct PlaceRatingInfoButton: View {
    let explanation: PlaceRatingExplanation
    let tint: Color

    @Environment(\.astirBrandMode) private var astirBrandMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isPresented = false
    @State private var isAccessibleExplanationPresented = false

    var body: some View {
        Button {
            if dynamicTypeSize.isAccessibilitySize {
                isAccessibleExplanationPresented = true
            } else {
                isPresented = true
            }
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(explanation.accessibilityLabel)
        .accessibilityIdentifier("ratings.explanation.open")
        .accessibilityHint("Shows how this score is calculated")
        .popover(
            isPresented: $isPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tint)

                    Text(explanation.title)
                        .font(AstirTypography.cardTitle)
                        .foregroundStyle(astirBrandMode.primaryText)
                }

                Text(explanation.message)
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(astirBrandMode.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(WanderTheme.spacing3)
            .frame(idealWidth: 270, maxWidth: 290, alignment: .leading)
            .background(astirBrandMode.raisedBackground)
            .presentationCompactAdaptation(.popover)
        }
        .sheet(isPresented: $isAccessibleExplanationPresented) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                        ForEach(explanation.paragraphs, id: \.self) { paragraph in
                            Text(paragraph)
                                .font(AstirTypography.bodySmall)
                                .foregroundStyle(astirBrandMode.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(WanderTheme.spacing4)
                }
                .accessibilityIdentifier("ratings.explanation.scroll")
                .background(astirBrandMode.raisedBackground)
                .navigationTitle(explanation.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isAccessibleExplanationPresented = false }
                            .accessibilityIdentifier("ratings.explanation.done")
                    }
                }
            }
            .presentationDetents([.large])
        }
    }
}
