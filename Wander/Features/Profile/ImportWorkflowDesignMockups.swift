#if DEBUG
import SwiftUI
import UIKit

/// Captures the production import views with deterministic data and the same
/// photo repository used by the map screenshot harness.
enum ImportImplementationCapturePage: String, CaseIterable {
    case review, details, history, processing, share, recovery, report

    static func resolved() -> Self? {
        allCases.first {
            ProcessInfo.processInfo.arguments.contains(
                "-WanderImportImplementation" + $0.rawValue.capitalized
            )
        }
    }
}

struct ImportImplementationCaptureRoot: View {
    let page: ImportImplementationCapturePage
    @StateObject private var store = WanderStore(fixtures: WanderFixtures.seed())
    @StateObject private var walkthroughs = FirstVisitWalkthroughCoordinator(isEnabled: false)
    @StateObject private var importStore: PlaceImportStore

    init(page: ImportImplementationCapturePage) {
        self.page = page
        let persistence = EphemeralPlaceImportPersistence()
        var snapshot = Self.snapshot
        if page == .report {
            let original = snapshot.items.filter { $0.batchID == "capture-instagram" }
            snapshot.items.removeAll { $0.batchID == "capture-instagram" }
            for index in 0..<10 {
                var item = original[index % original.count]
                item = PlaceImportItem(
                    id: "report-place-\(index)", batchID: "capture-instagram", source: .instagram,
                    seed: item.seed, state: index == 0 ? .saved : .ready,
                    candidates: Array(item.candidates.prefix(1)), selectedCandidateID: item.candidates.first?.id
                )
                snapshot.items.append(item)
            }
            snapshot.batches[0].receipt = PlaceImportReceipt(
                batchID: "capture-instagram", sourceName: nil,
                entries: [PlaceImportReceiptEntry(itemID: "report-place-0", displayName: "Maru Coffee", displayArea: "Los Angeles", status: .wannaGo, outcome: .added, userPlaceID: nil)],
                destinationListID: nil
            )
        }
        if page == .recovery {
            snapshot.items = snapshot.items.map { item in
                var item = item
                item.kind = .sourceRetry
                item.state = .failed
                item.candidates = []
                item.selectedCandidateID = nil
                item.helpMessage = "We couldn’t finish reading this post. Your link is safe."
                return item
            }
        }
        try? persistence.save(snapshot)
        _importStore = StateObject(wrappedValue: PlaceImportStore(persistence: persistence))
    }

    var body: some View {
        NavigationStack {
            if page == .share {
                ImportShareHostCaptureView()
            } else if page == .history {
                PlaceImportHistoryScreen(importStore: importStore)
            } else if page == .report || page == .recovery {
                PlaceImportHistoryDestination(importStore: importStore, batchID: "capture-instagram")
            } else {
                PlaceImportCanonicalReviewScreen(
                    importStore: importStore,
                    batchIDs: [page == .processing ? "capture-snapchat" : "capture-instagram"],
                    onDone: {},
                    initiallyExpandedDetailItemID: page == .details ? "capture-instagram-0" : nil
                )
            }
        }
        .environmentObject(store)
        .environmentObject(walkthroughs)
        .astirAdaptiveBrandMode()
    }

    private static var snapshot: PlaceImportSnapshot {
        let sources: [PlaceImportSource] = [.instagram, .googleMaps, .tiktok, .snapchat, .textNotes]
        let batches = sources.enumerated().map { index, source in
            PlaceImportBatch(
                id: "capture-\(source.rawValue)",
                source: source,
                sourceName: nil,
                createdAt: Date(timeIntervalSince1970: 1_788_450_000 - Double(index * 86_400)),
                state: source == .snapchat ? .processing : .ready,
                totalCount: 2,
                processedCount: source == .snapchat ? 0 : 2
            )
        }
        let items = sources.flatMap { source in
            (0..<2).map { index in
                let name = index == 0 ? "Maru Coffee" : "Jade Rabbit"
                let candidates = (0..<(index == 0 ? 1 : 3)).map { candidateIndex in
                    PlaceCandidate(
                        id: "capture-\(source.rawValue)-\(index)-\(candidateIndex)",
                        name: name,
                        category: index == 0 ? "coffee shop" : "restaurant",
                        address: candidateIndex == 0 ? "1936 Hillhurst Avenue" : "\(200 + candidateIndex) Main Street",
                        locality: "Los Angeles",
                        region: "CA",
                        latitude: 34.104 + Double(candidateIndex) * 0.01,
                        longitude: -118.287,
                        sourceProvider: "mapkit",
                        confidence: 0.96 - Double(candidateIndex) * 0.1
                    )
                }
                return PlaceImportItem(
                    id: "capture-\(source.rawValue)-\(index)",
                    batchID: "capture-\(source.rawValue)",
                    source: source,
                    seed: PlaceImportSeed(
                        rawText: name,
                        nameHint: name,
                        areaHint: "Los Angeles",
                        sourceURLString: "https://example.com/recme-import-ui-fixture",
                        sourceLine: index + 1
                    ),
                    state: source == .snapchat ? .queued : (index == 0 ? .ready : .ambiguous),
                    candidates: source == .snapchat ? [] : candidates,
                    selectedCandidateID: source == .snapchat ? nil : candidates.first?.id,
                    stagedStatus: index == 0 ? .been : .wannaGo
                )
            }
        }
        return PlaceImportSnapshot(batches: batches, items: items)
    }
}

/// Real system share host for extension integration tests. It never starts
/// the app's extractor, and reads/removes only its own reserved test envelopes.
private struct ImportShareHostCaptureView: View {
    static let fixtureURL = URL(string: "https://example.com/recme-import-ui-fixture")!
    @State private var isSharing = false
    @State private var captureCount = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("Share extension test")
            Button("Share test link") { isSharing = true }
            Text("Captured: \(captureCount)").accessibilityIdentifier("import.share.count")
            Button("Clear test captures") {
                guard let inbox = try? SharedPlaceImportInbox.live(),
                      let scan = try? inbox.scan() else { return }
                for entry in scan.entries where isFixture(entry) {
                    try? inbox.acknowledge(entry)
                }
                captureCount = 0
            }
        }
        .sheet(isPresented: $isSharing) { ImportSystemShareHost() }
        .task {
            while !Task.isCancelled {
                if let inbox = try? SharedPlaceImportInbox.live(), let scan = try? inbox.scan() {
                    captureCount = scan.entries.filter(isFixture).count
                }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }

    private func isFixture(_ entry: SharedPlaceImportInboxEntry) -> Bool {
        entry.envelope.items.allSatisfy { $0.sourceURLString == Self.fixtureURL.absoluteString }
    }
}

private struct ImportSystemShareHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [ImportShareHostCaptureView.fixtureURL], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

enum ImportWorkflowMockupPage: String, CaseIterable {
    case entry
    case ready
    case ambiguous
    case details
    case history
    case report
    case banner
    case complete
    case offline
    case failure

    static func resolved(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        let prefix = "-WanderImportWorkflowMockup"
        return allCases.first { page in
            arguments.contains(prefix + page.rawValue.capitalized)
        }
    }
}

struct ImportWorkflowMockupRoot: View {
    let page: ImportWorkflowMockupPage

    var body: some View {
        Group {
            switch page {
            case .entry:
                ImportEntryMockup()
            case .ready:
                ImportReviewMockup(mode: .ready)
            case .ambiguous:
                ImportReviewMockup(mode: .ambiguous)
            case .details:
                ImportReviewMockup(mode: .details)
            case .history:
                ImportHistoryMockup()
            case .report:
                ImportReportMockup()
            case .banner:
                ImportMapStateMockup(state: .ready)
            case .complete:
                ImportMapStateMockup(state: .complete)
            case .offline:
                ImportMapStateMockup(state: .offline)
            case .failure:
                ImportMapStateMockup(state: .failure)
            }
        }
        .tint(WanderTheme.terracotta.color)
        .preferredColorScheme(.light)
    }
}

private enum ImportReviewMockupMode {
    case ready
    case ambiguous
    case details
}

private enum ImportMockStatus: String {
    case none
    case wanna
    case checkIn
}

private enum ImportPostCrop: CaseIterable {
    case left
    case right
    case top
    case bottom
    case center
}

private enum ImportMockProvider {
    case instagram
    case googleMaps
    case tiktok
    case youtube

    var name: String {
        switch self {
        case .instagram: "Instagram"
        case .googleMaps: "Google Maps"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        }
    }
}

private struct ImportMockCandidate: Identifiable {
    let id: String
    let name: String
    let detail: String
    let isBest: Bool
}

private struct ImportMockPlace: Identifiable {
    let id: String
    let name: String
    let detail: String
    let crop: ImportPostCrop
    let candidates: [ImportMockCandidate]
    let listName: String?
}

private extension ImportMockPlace {
    static let all: [Self] = [
        ImportMockPlace(
            id: "bar-chelou",
            name: "Bar Chelou",
            detail: "Pasadena · French",
            crop: .right,
            candidates: [],
            listName: "Date night"
        ),
        ImportMockPlace(
            id: "gjusta",
            name: "Gjusta",
            detail: "Venice · Bakery",
            crop: .left,
            candidates: [],
            listName: nil
        ),
        ImportMockPlace(
            id: "mcdonalds",
            name: "McDonald’s",
            detail: "1320 E Colorado Blvd · 0.7 mi",
            crop: .bottom,
            candidates: [
                ImportMockCandidate(
                    id: "colorado",
                    name: "McDonald’s",
                    detail: "1320 E Colorado Blvd · 0.7 mi",
                    isBest: true
                ),
                ImportMockCandidate(
                    id: "arroyo",
                    name: "McDonald’s",
                    detail: "770 S Arroyo Pkwy · 1.4 mi",
                    isBest: false
                ),
                ImportMockCandidate(
                    id: "lincoln",
                    name: "McDonald’s",
                    detail: "2157 Lincoln Ave · 2.8 mi",
                    isBest: false
                ),
                ImportMockCandidate(
                    id: "lake",
                    name: "McDonald’s",
                    detail: "988 Lake Ave · 3.1 mi",
                    isBest: false
                ),
                ImportMockCandidate(
                    id: "east-colorado",
                    name: "McDonald’s",
                    detail: "1720 Colorado Blvd · 4.0 mi",
                    isBest: false
                )
            ],
            listName: nil
        ),
        ImportMockPlace(
            id: "mart-collective",
            name: "The Mart Collective",
            detail: "Venice · Vintage",
            crop: .center,
            candidates: [],
            listName: "Weekend"
        ),
        ImportMockPlace(
            id: "bavel",
            name: "Bavel",
            detail: "Arts District · Middle Eastern",
            crop: .top,
            candidates: [],
            listName: nil
        ),
        ImportMockPlace(
            id: "joy",
            name: "Joy",
            detail: "Highland Park · Taiwanese",
            crop: .left,
            candidates: [],
            listName: nil
        ),
        ImportMockPlace(
            id: "botanica",
            name: "Botanica",
            detail: "Silver Lake · California",
            crop: .right,
            candidates: [],
            listName: nil
        ),
        ImportMockPlace(
            id: "holbox",
            name: "Holbox",
            detail: "Historic South Central · Seafood",
            crop: .bottom,
            candidates: [],
            listName: "LA essentials"
        ),
        ImportMockPlace(
            id: "found-oyster",
            name: "Found Oyster",
            detail: "East Hollywood · Seafood",
            crop: .top,
            candidates: [],
            listName: nil
        ),
        ImportMockPlace(
            id: "quarter-sheets",
            name: "Quarter Sheets",
            detail: "Echo Park · Pizza",
            crop: .center,
            candidates: [],
            listName: nil
        ),
        ImportMockPlace(
            id: "night-market",
            name: "Night + Market Song",
            detail: "Silver Lake · Thai",
            crop: .left,
            candidates: [],
            listName: nil
        ),
        ImportMockPlace(
            id: "courage",
            name: "Courage Bagels",
            detail: "Virgil Village · Bagels",
            crop: .right,
            candidates: [],
            listName: nil
        ),
        ImportMockPlace(
            id: "nobu",
            name: "Nobu Malibu",
            detail: "Malibu · Japanese",
            crop: .top,
            candidates: [],
            listName: "Parents in town"
        )
    ]
}

// MARK: - Draggable import entry

private struct ImportEntryMockup: View {
    @State private var presentsSheet = false
    @State private var selectedDetent: PresentationDetent = .height(440)

    var body: some View {
        GeometryReader { _ in
            ImportMockMapBackground(asset: "OnboardingMapDiary")
                .overlay(alignment: .top) {
                    ImportMockMapChrome()
                        .padding(.top, 8)
                }
                .task {
                    presentsSheet = true
                }
                .sheet(isPresented: $presentsSheet) {
                    ImportEntrySheetContent()
                        .presentationDetents([.height(440), .large], selection: $selectedDetent)
                        .presentationDragIndicator(.visible)
                        .presentationCornerRadius(WanderTheme.radiusSheet)
                        .presentationBackground(.ultraThinMaterial)
                        .presentationBackgroundInteraction(.enabled(upThrough: .height(440)))
                        .presentationContentInteraction(.resizes)
                }
        }
    }
}

private struct ImportEntrySheetContent: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: WanderTheme.spacing2) {
                ImportMockGlassIconButton(
                    systemImage: "xmark",
                    accessibilityLabel: "Close import places"
                )

                Spacer(minLength: WanderTheme.spacing1)

                Text("Import places")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)

                Spacer(minLength: WanderTheme.spacing1)

                WanderGlassButtonCluster {
                    HStack(spacing: WanderTheme.spacing1) {
                        ImportMockGlassIconButton(
                            systemImage: "questionmark",
                            accessibilityLabel: "Import help"
                        )
                        ImportMockGlassIconButton(
                            systemImage: "clock.arrow.circlepath",
                            accessibilityLabel: "Import history"
                        )
                    }
                }
            }

            VStack(spacing: WanderTheme.spacing2) {
                ImportMockSourceIconStack(iconSize: 36)

                VStack(spacing: 2) {
                    Text("Bring your places with you")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Instagram, Google Maps, TikTok, and more")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: "link")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                Text("instagram.com/reel/…")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(WanderTheme.textFaint.color)
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
            }
            .padding(.leading, WanderTheme.spacing3)
            .padding(.trailing, 2)
            .frame(maxWidth: .infinity, minHeight: 56)
            .wanderGlassRoundedRectangle(
                tone: .lightAction,
                cornerRadius: WanderTheme.radiusLarge,
                material: .clear
            )

            ImportMockPrimaryGlassButton(
                title: "Start import",
                systemImage: "arrow.down.doc.fill",
                tone: .accent
            )

            ImportMockSecondaryGlassButton(
                title: "Paste from clipboard",
                systemImage: "doc.on.clipboard"
            )

            Button(action: {}) {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(WanderTheme.stateSuccess.color)
                    Text("13 places ready to review")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .black))
                }
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(maxWidth: .infinity, minHeight: 46)
                .wanderGlassCapsule(tone: .neutral)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("13 places ready to review")
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WanderTheme.canvasWarm.color.opacity(0.68))
    }
}

// MARK: - Canonical review

private struct ImportReviewMockup: View {
    let mode: ImportReviewMockupMode

    @State private var statuses: [String: ImportMockStatus]
    @State private var expandedMatches: Set<String>
    @State private var expandedDetails: Set<String>
    @State private var selectedCandidateIDs: Set<String> = ["colorado"]

    init(mode: ImportReviewMockupMode) {
        self.mode = mode
        var initialStatuses = Dictionary(
            uniqueKeysWithValues: ImportMockPlace.all.map { ($0.id, ImportMockStatus.wanna) }
        )
        if mode == .details {
            initialStatuses["bar-chelou"] = .checkIn
        }
        _statuses = State(initialValue: initialStatuses)
        _expandedMatches = State(
            initialValue: mode == .ambiguous ? ["mcdonalds"] : []
        )
        _expandedDetails = State(
            initialValue: mode == .details ? ["bar-chelou"] : []
        )
    }

    private var orderedPlaces: [ImportMockPlace] {
        switch mode {
        case .ready:
            ImportMockPlace.all
        case .ambiguous:
            ImportMockPlace.all.sorted { left, _ in left.id == "mcdonalds" }
        case .details:
            ImportMockPlace.all
        }
    }

    private var selectedCount: Int {
        orderedPlaces.reduce(into: 0) { count, place in
            guard statuses[place.id] != ImportMockStatus.none else { return }
            count += place.candidates.isEmpty ? 1 : selectedCandidateIDs.count
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                    Text("13 places matched and ready")
                        .font(.system(size: 27, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    reviewSourceLine

                    ImportReviewSectionHeader(
                        title: "Ready to add",
                        count: selectedCount,
                        wannaSelected: allSelected(.wanna),
                        checkInSelected: allSelected(.checkIn),
                        selectAllWanna: { selectAll(.wanna) },
                        selectAllCheckIn: { selectAll(.checkIn) }
                    )

                    ForEach(orderedPlaces) { place in
                        ImportPlaceCard(
                            place: place,
                            status: statusBinding(for: place),
                            showsMatches: matchesBinding(for: place),
                            showsDetails: detailsBinding(for: place),
                            selectedCandidateIDs: $selectedCandidateIDs,
                            showsListSummary: false
                        )
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing2)
                .padding(.bottom, 112)
            }
            .scrollIndicators(.hidden)
            .background(WanderTheme.canvasWarm.color)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ImportMockGlassIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: "Close import review"
                    )
                }
                ToolbarItem(placement: .principal) {
                    Text("Instagram import")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ImportMockPrimaryGlassButton(
                    title: selectedCount == 0
                        ? "Keep for later"
                        : "Add \(selectedCount) place\(selectedCount == 1 ? "" : "s")",
                    systemImage: selectedCount == 0 ? "clock" : "plus",
                    tone: .deepBlackAction
                )
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing2)
                .padding(.bottom, WanderTheme.spacing2)
            }
        }
    }

    private var reviewSourceLine: some View {
        HStack(spacing: WanderTheme.spacing2) {
            ImportMockSourceIcon(provider: .instagram, size: 26)
            Text("Instagram")
                .font(.system(size: 13, weight: .black))
            Text("·")
                .foregroundStyle(WanderTheme.textFaint.color)
            Text("11 new · 2 already saved")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .foregroundStyle(WanderTheme.textInk.color)
        .accessibilityElement(children: .combine)
    }

    private func allSelected(_ status: ImportMockStatus) -> Bool {
        !statuses.isEmpty && statuses.values.allSatisfy { $0 == status }
    }

    private func selectAll(_ status: ImportMockStatus) {
        let next: ImportMockStatus = allSelected(status) ? .none : status
        withAnimation(.easeInOut(duration: 0.2)) {
            statuses = Dictionary(
                uniqueKeysWithValues: ImportMockPlace.all.map { ($0.id, next) }
            )
        }
    }

    private func statusBinding(for place: ImportMockPlace) -> Binding<ImportMockStatus> {
        Binding(
            get: { statuses[place.id] ?? .none },
            set: { statuses[place.id] = $0 }
        )
    }

    private func matchesBinding(for place: ImportMockPlace) -> Binding<Bool> {
        Binding(
            get: { expandedMatches.contains(place.id) },
            set: { isExpanded in
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedMatches.insert(place.id)
                        expandedDetails.remove(place.id)
                    } else {
                        expandedMatches.remove(place.id)
                    }
                }
            }
        )
    }

    private func detailsBinding(for place: ImportMockPlace) -> Binding<Bool> {
        Binding(
            get: { expandedDetails.contains(place.id) },
            set: { isExpanded in
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedDetails = [place.id]
                        expandedMatches.remove(place.id)
                    } else {
                        expandedDetails.remove(place.id)
                    }
                }
            }
        )
    }
}

private struct ImportReviewSectionHeader: View {
    let title: String
    let count: Int
    let wannaSelected: Bool
    let checkInSelected: Bool
    let selectAllWanna: () -> Void
    let selectAllCheckIn: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: WanderTheme.spacing2) {
            HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing1) {
                Text(title)
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .accessibilityAddTraits(.isHeader)
                Text("\(count)")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text("Apply to all")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(WanderTheme.textFaint.color)
                    .frame(maxWidth: .infinity, alignment: .center)

                ImportStatusControls(
                    status: .constant(wannaSelected ? .wanna : checkInSelected ? .checkIn : .none),
                    actionOverride: { choice in
                        switch choice {
                        case .wanna: selectAllWanna()
                        case .checkIn: selectAllCheckIn()
                        case .none: break
                        }
                    },
                    accessibilityPrefix: "Apply to all"
                )

                HStack(spacing: 6) {
                    Text("Wanna")
                        .frame(width: 42)
                    Text("Check In")
                        .frame(width: 42)
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            }
            .padding(.trailing, WanderTheme.spacing3)
        }
    }
}

private struct ImportPlaceCard: View {
    let place: ImportMockPlace
    @Binding var status: ImportMockStatus
    @Binding var showsMatches: Bool
    @Binding var showsDetails: Bool
    @Binding var selectedCandidateIDs: Set<String>
    let showsListSummary: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: WanderTheme.spacing3) {
                ImportPostArtwork(crop: place.crop, cornerRadius: WanderTheme.radiusMedium)
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(2)
                    Text(place.detail)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(2)
                    if showsListSummary, let listName = place.listName {
                        Label(listName, systemImage: "square.stack.3d.up.fill")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ImportStatusControls(
                    status: $status,
                    actionOverride: nil,
                    accessibilityPrefix: place.name
                )
            }
            .padding(WanderTheme.spacing3)

            if !place.candidates.isEmpty {
                Divider()
                    .overlay(WanderTheme.borderHairline.color)
                    .padding(.leading, 80)

                Button {
                    showsMatches.toggle()
                } label: {
                    HStack(spacing: WanderTheme.spacing2) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                            .frame(width: 24)
                        Text("Possible matches")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(WanderTheme.textInk.color)
                        Spacer()
                        Text("\(place.candidates.count)")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .monospacedDigit()
                        Image(systemName: showsMatches ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(WanderTheme.textFaint.color)
                    }
                    .padding(.horizontal, WanderTheme.spacing3)
                    .frame(minHeight: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsMatches ? "Expanded" : "Collapsed")

                if showsMatches {
                    Divider()
                        .overlay(WanderTheme.borderHairline.color)
                    ImportCandidateList(
                        candidates: place.candidates,
                        selectedCandidateIDs: $selectedCandidateIDs
                    )
                }
            }

            Divider()
                .overlay(WanderTheme.borderHairline.color)
                .padding(.leading, 80)

            Button {
                showsDetails.toggle()
            } label: {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .frame(width: 24)
                    Text(showsDetails ? "Hide details" : "Add details")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Spacer()
                    Image(systemName: showsDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(WanderTheme.textFaint.color)
                }
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsDetails ? "Expanded" : "Collapsed")

            if showsDetails {
                Divider()
                    .overlay(WanderTheme.borderHairline.color)
                ImportDetailsEditorMockup(isCheckIn: status == .checkIn)
            }
        }
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }
}

private struct ImportStatusControls: View {
    @Binding var status: ImportMockStatus
    let actionOverride: ((ImportMockStatus) -> Void)?
    let accessibilityPrefix: String

    var body: some View {
        WanderGlassButtonCluster(mergeSpacing: 4) {
            HStack(spacing: 6) {
                statusButton(
                    choice: .wanna,
                    systemImage: "bookmark.fill",
                    label: "\(accessibilityPrefix), Wanna"
                )
                statusButton(
                    choice: .checkIn,
                    systemImage: "checkmark.circle.fill",
                    label: "\(accessibilityPrefix), Check In"
                )
            }
        }
    }

    private func statusButton(
        choice: ImportMockStatus,
        systemImage: String,
        label: String
    ) -> some View {
        Button {
            if let actionOverride {
                actionOverride(choice)
            } else {
                status = status == choice ? .none : choice
            }
        } label: {
            Image(systemName: resolvedSystemImage(for: choice, selectedImage: systemImage))
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(
                    status == choice
                        ? (choice == .checkIn
                            ? WanderTheme.stateSuccess.color
                            : WanderTheme.terracottaDark.color)
                        : WanderTheme.textMuted.color
                )
                .frame(width: 42, height: 42)
                .wanderGlassCapsule(
                    tone: choice == .checkIn
                        ? .neutral
                        : (status == choice ? .selected : .neutral)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(status == choice ? .isSelected : [])
        .accessibilityHint(status == choice ? "Double tap to clear" : "Double tap to select")
    }

    private func resolvedSystemImage(
        for choice: ImportMockStatus,
        selectedImage: String
    ) -> String {
        guard status != choice else { return selectedImage }
        return choice == .wanna ? "bookmark" : "checkmark.circle"
    }
}

private struct ImportCandidateList: View {
    let candidates: [ImportMockCandidate]
    @Binding var selectedCandidateIDs: Set<String>

    var body: some View {
        VStack(spacing: 0) {
            ForEach(candidates) { candidate in
                Button {
                    if selectedCandidateIDs.contains(candidate.id) {
                        selectedCandidateIDs.remove(candidate.id)
                    } else {
                        selectedCandidateIDs.insert(candidate.id)
                    }
                } label: {
                    HStack(spacing: WanderTheme.spacing2) {
                        Image(systemName: selectedCandidateIDs.contains(candidate.id)
                            ? "checkmark.circle.fill"
                            : "circle")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(
                                selectedCandidateIDs.contains(candidate.id)
                                    ? WanderTheme.terracotta.color
                                    : WanderTheme.borderStrong.color
                            )
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(candidate.name)
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundStyle(WanderTheme.textInk.color)
                                if candidate.isBest {
                                    Text("BEST MATCH")
                                        .font(.system(size: 9, weight: .black))
                                        .tracking(0.5)
                                        .foregroundStyle(WanderTheme.stateSuccess.color)
                                }
                            }
                            Text(candidate.detail)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, WanderTheme.spacing3)
                    .frame(minHeight: 54)
                    .background(
                        selectedCandidateIDs.contains(candidate.id)
                            ? WanderTheme.terracottaTint.color.opacity(0.5)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(
                    selectedCandidateIDs.contains(candidate.id) ? "Selected" : "Not selected"
                )

                if candidate.id != candidates.last?.id {
                    Divider()
                        .overlay(WanderTheme.borderHairline.color)
                        .padding(.leading, 52)
                }
            }
        }
        .background(WanderTheme.surfaceBone.color.opacity(0.7))
    }
}

private struct ImportDetailsEditorMockup: View {
    let isCheckIn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            ImportUnratedPicker()

            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text("Note")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("Why did you save this?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textFaint.color)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                    .padding(WanderTheme.spacing2)
                    .background(WanderTheme.surfaceRaised.color.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                    .overlay {
                        RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                            .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                    }
            }

            HStack(spacing: WanderTheme.spacing2) {
                ImportDetailChip(
                    title: "When",
                    value: isCheckIn ? "Today" : "Not set",
                    systemImage: "calendar"
                )
                ImportDetailChip(
                    title: "Category",
                    value: "French",
                    systemImage: "fork.knife"
                )
            }

            HStack(spacing: WanderTheme.spacing2) {
                ImportDetailChip(
                    title: "Friends",
                    value: "Add",
                    systemImage: "person.2"
                )
                ImportDetailChip(
                    title: "Photos",
                    value: "Add",
                    systemImage: "photo.on.rectangle"
                )
            }

            HStack(spacing: WanderTheme.spacing2) {
                ImportDetailChip(
                    title: "Lists",
                    value: "Date night",
                    systemImage: "square.stack.3d.up"
                )
                ImportDetailChip(
                    title: "Place type",
                    value: "Restaurant",
                    systemImage: "mappin"
                )
            }

            Button(action: {}) {
                HStack {
                    Label("More options", systemImage: "ellipsis.circle")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .black))
                }
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
                .frame(minHeight: WanderTheme.tapMinimum)
            }
            .buttonStyle(.plain)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color.opacity(0.78))
    }
}

private struct ImportUnratedPicker: View {
    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack {
                Text("Rating")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Spacer()
                Text("Not rated")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .padding(.horizontal, WanderTheme.spacing2)
                    .frame(minHeight: 28)
                    .wanderGlassCapsule(tone: .neutral, interactive: false)
            }

            ZStack {
                Capsule()
                    .fill(WanderTheme.surfaceSand.color)
                    .frame(height: 7)
                HStack {
                    ForEach(1...5, id: \.self) { value in
                        VStack(spacing: 5) {
                            Circle()
                                .fill(WanderTheme.surfaceRaised.color)
                                .overlay {
                                    Circle()
                                        .stroke(WanderTheme.borderStrong.color, lineWidth: 1.5)
                                }
                                .frame(width: 13, height: 13)
                            Text("\(value)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(WanderTheme.textFaint.color)
                        }
                        if value != 5 {
                            Spacer()
                        }
                    }
                }
            }
            .frame(height: 36)

            Text("Tap the scale to rate · 5 is best")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rating, not rated")
        .accessibilityHint("Adjustable from one to five after the first touch")
    }
}

private struct ImportDetailChip: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        Button(action: {}) {
            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Text(value)
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WanderTheme.spacing2)
            .frame(maxWidth: .infinity, minHeight: 48)
            .wanderGlassRoundedRectangle(
                tone: .neutral,
                cornerRadius: WanderTheme.radiusMedium,
                material: .clear
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History and editable report

private struct ImportHistoryMockup: View {
    private let tiles: [(ImportPostCrop, ImportMockProvider, String, Bool)] = [
        (.left, .instagram, "10 L.A. spots worth the drive", false),
        (.center, .googleMaps, "Joe’s saved restaurants", true),
        (.top, .tiktok, "The perfect Sunday in Silver Lake", false),
        (.bottom, .youtube, "Pasadena places nobody talks about", false),
        (.right, .googleMaps, "Ryan’s weekend map", false),
        (.center, .instagram, "Date-night places that actually hit", false)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: WanderTheme.spacing3),
                        GridItem(.flexible(), spacing: WanderTheme.spacing3)
                    ],
                    spacing: WanderTheme.spacing3
                ) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                        Button(action: {}) {
                            ImportHistoryTile(
                                crop: tile.0,
                                provider: tile.1,
                                postText: tile.2,
                                attentionCount: tile.3 ? 2 : nil
                            )
                            .aspectRatio(0.82, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(tile.1.name) import from August \(29 - index), \(index + 3) places"
                        )
                    }
                }
                .padding(WanderTheme.spacing4)
            }
            .background(WanderTheme.canvasWarm.color)
            .navigationTitle("Import history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ImportMockGlassIconButton(
                        systemImage: "chevron.left",
                        accessibilityLabel: "Back to import places"
                    )
                }
            }
        }
    }
}

private struct ImportHistoryTile: View {
    let crop: ImportPostCrop
    let provider: ImportMockProvider
    let postText: String
    let attentionCount: Int?

    var body: some View {
        ZStack {
            Group {
                if provider == .googleMaps {
                    Image("OnboardingMapDiary")
                        .resizable()
                        .scaledToFill()
                } else {
                    ImportPostArtwork(crop: crop, cornerRadius: 0)
                }
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.08), .black.opacity(0.76)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading) {
                HStack {
                    ImportMockSourceIcon(provider: provider, size: 30)
                    Spacer()
                    if let attentionCount {
                        Text("\(attentionCount)")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.white)
                            .frame(minWidth: 30, minHeight: 30)
                            .background(WanderTheme.stateWarning.color)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Text(postText)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            }
            .padding(WanderTheme.spacing3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.7), lineWidth: 1)
        }
        .clipped()
    }
}

private struct ImportReportMockup: View {
    @State private var statuses: [String: ImportMockStatus] = [
        "bar-chelou": .checkIn,
        "gjusta": .wanna,
        "mart-collective": .wanna
    ]
    @State private var expandedDetails: Set<String> = []
    @State private var selectedCandidateIDs: Set<String> = ["colorado"]

    private let reportPlaces = Array(ImportMockPlace.all.prefix(4))

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                    ImportHistoryTile(
                        crop: .center,
                        provider: .instagram,
                        postText: "10 L.A. spots worth the drive",
                        attentionCount: nil
                    )
                    .frame(height: 190)

                    HStack(spacing: WanderTheme.spacing2) {
                        Image(systemName: "link")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                        Text("instagram.com/reel/C9…")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button(action: {}) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(WanderTheme.textInk.color)
                                .frame(width: 40, height: 40)
                                .wanderGlassCapsule(tone: .neutral)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy original import link")
                    }
                    .padding(.leading, WanderTheme.spacing3)
                    .padding(.trailing, 4)
                    .frame(minHeight: 48)
                    .wanderGlassRoundedRectangle(
                        tone: .lightAction,
                        cornerRadius: WanderTheme.radiusLarge,
                        material: .clear
                    )

                    Text("13 places imported")
                        .font(.system(size: 27, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .accessibilityAddTraits(.isHeader)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Imported places")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text("Edits save instantly")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }

                    ForEach(reportPlaces) { place in
                        ImportPlaceCard(
                            place: place,
                            status: reportStatusBinding(for: place),
                            showsMatches: .constant(false),
                            showsDetails: reportDetailsBinding(for: place),
                            selectedCandidateIDs: $selectedCandidateIDs,
                            showsListSummary: true
                        )
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing6)
            }
            .scrollIndicators(.hidden)
            .background(WanderTheme.canvasWarm.color)
            .navigationTitle("Import report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ImportMockGlassIconButton(
                        systemImage: "chevron.left",
                        accessibilityLabel: "Back to import history"
                    )
                }
            }
        }
    }

    private func reportStatusBinding(for place: ImportMockPlace) -> Binding<ImportMockStatus> {
        Binding(
            get: { statuses[place.id] ?? .none },
            set: { statuses[place.id] = $0 }
        )
    }

    private func reportDetailsBinding(for place: ImportMockPlace) -> Binding<Bool> {
        Binding(
            get: { expandedDetails.contains(place.id) },
            set: { isExpanded in
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedDetails = [place.id]
                    } else {
                        expandedDetails.remove(place.id)
                    }
                }
            }
        )
    }
}

// MARK: - Completion and recovery in map context

private enum ImportMapState {
    case ready
    case complete
    case offline
    case failure
}

private struct ImportMapStateMockup: View {
    let state: ImportMapState

    var body: some View {
        ZStack {
            ImportMockMapBackground(
                asset: state == .ready ? "OnboardingMapTrusted" : "OnboardingMapDiary"
            )

            if state == .complete {
                VStack(spacing: 4) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 19, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(WanderTheme.terracotta.color)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(color: .black.opacity(0.2), radius: 7, y: 4)
                    Text("Bar Chelou")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .padding(.horizontal, WanderTheme.spacing2)
                        .frame(minHeight: 26)
                        .wanderGlassCapsule(tone: .lightAction, interactive: false)
                }
                .offset(y: -22)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Bar Chelou added to your map")
            }

            VStack(spacing: WanderTheme.spacing2) {
                ImportMockMapChrome()

                switch state {
                case .ready:
                    ImportMapBanner(
                        icon: "checkmark",
                        color: WanderTheme.stateSuccess.color,
                        title: "Your import is ready",
                        detail: "13 places matched",
                        actionTitle: "Review",
                        isError: false
                    )
                case .complete:
                    EmptyView()
                case .offline:
                    ImportMapBanner(
                        icon: "wifi.slash",
                        color: WanderTheme.stateInfo.color,
                        title: "Saved on this phone",
                        detail: "13 places will sync when you’re back online",
                        actionTitle: nil,
                        isError: false
                    )
                case .failure:
                    ImportMapBanner(
                        icon: "exclamationmark.triangle.fill",
                        color: WanderTheme.stateError.color,
                        title: "3 places still need saving",
                        detail: "Your link and choices are safe",
                        actionTitle: "Retry",
                        isError: true
                    )
                }

                Spacer()

                ImportMockBottomBar()
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .padding(.top, WanderTheme.spacing2)
            .padding(.bottom, WanderTheme.spacing2)
        }
    }
}

private struct ImportMockMapChrome: View {
    var body: some View {
        WanderGlassButtonCluster(mergeSpacing: WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing2) {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Text("Search your map")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Spacer()
                }
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(maxWidth: .infinity, minHeight: 46)
                .wanderGlassCapsule(tone: .lightAction)

                ImportMockGlassIconButton(
                    systemImage: "line.3.horizontal.decrease",
                    accessibilityLabel: "Map filters"
                )
                ImportMockGlassIconButton(
                    systemImage: "person.crop.circle.fill",
                    accessibilityLabel: "Profile"
                )
            }
        }
    }
}

private struct ImportMapBanner: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let actionTitle: String?
    let isError: Bool

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(detail)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle {
                Button(action: {}) {
                    Text(actionTitle)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(isError ? WanderTheme.stateError.color : WanderTheme.textInk.color)
                        .padding(.horizontal, WanderTheme.spacing2)
                        .frame(minHeight: 40)
                        .wanderGlassCapsule(tone: .lightAction)
                }
                .buttonStyle(.plain)
            }

            Button(action: {}) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, WanderTheme.spacing2)
        .padding(.trailing, 2)
        .frame(minHeight: 66)
        .wanderGlassPanel(
            cornerRadius: WanderTheme.radiusLarge,
            tone: isError ? .accent : .lightAction,
            interactive: true
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ImportMockBottomBar: View {
    var body: some View {
        WanderGlassButtonCluster(mergeSpacing: WanderTheme.spacing3) {
            HStack(spacing: WanderTheme.spacing4) {
                bottomButton("map.fill", selected: true)
                bottomButton("plus", selected: false)
                bottomButton("safari", selected: false)
                bottomButton("person", selected: false)
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .frame(minHeight: 56)
            .wanderGlassCapsule(tone: .darkOverlay, interactive: false)
        }
        .frame(maxWidth: .infinity)
    }

    private func bottomButton(_ image: String, selected: Bool) -> some View {
        Image(systemName: image)
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(selected ? WanderTheme.terracotta.color : .white)
            .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
    }
}

// MARK: - Shared mock presentation

private struct ImportMockPrimaryGlassButton: View {
    let title: String
    let systemImage: String
    let tone: WanderGlassTone

    var body: some View {
        Button(action: {}) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(tone.foregroundStyle)
                .frame(maxWidth: .infinity, minHeight: 54)
                .wanderGlassRoundedRectangle(
                    tone: tone,
                    cornerRadius: WanderTheme.radiusLarge,
                    interactive: true,
                    showsBorder: false
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ImportMockSecondaryGlassButton: View {
    let title: String
    let systemImage: String

    var body: some View {
        Button(action: {}) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(maxWidth: .infinity, minHeight: 48)
                .wanderGlassCapsule(tone: .neutral)
        }
        .buttonStyle(.plain)
    }
}

private struct ImportMockGlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String

    var body: some View {
        Button(action: {}) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .frame(width: 42, height: 42)
                .wanderGlassCapsule(tone: .neutral)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ImportMockSourceIconStack: View {
    let iconSize: CGFloat

    var body: some View {
        HStack(spacing: -8) {
            ImportMockSourceIcon(provider: .googleMaps, size: iconSize)
            ImportMockSourceIcon(provider: .instagram, size: iconSize)
            ImportMockSourceIcon(provider: .tiktok, size: iconSize)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Google Maps, Instagram, and TikTok")
    }
}

private struct ImportMockSourceIcon: View {
    let provider: ImportMockProvider
    let size: CGFloat

    var body: some View {
        ZStack {
            background

            switch provider {
            case .instagram:
                Image("BrandInstagram")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .padding(size * 0.22)
            case .googleMaps:
                Image("BrandGoogleMaps")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.92))
                    .padding(size * 0.2)
            case .tiktok:
                Image("BrandTikTok")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .padding(size * 0.22)
            case .youtube:
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: size * 0.42, weight: .black))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.86), lineWidth: 2))
        .shadow(color: .black.opacity(0.14), radius: 3, y: 2)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var background: some View {
        switch provider {
        case .instagram:
            Circle().fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.51, green: 0.18, blue: 0.78),
                        Color(red: 0.95, green: 0.19, blue: 0.42),
                        Color(red: 1, green: 0.72, blue: 0.24)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .googleMaps:
            Circle().fill(.white)
        case .tiktok:
            Circle().fill(.black)
        case .youtube:
            Circle().fill(Color(red: 0.88, green: 0.1, blue: 0.1))
        }
    }
}

private struct ImportMockMapBackground: View {
    let asset: String

    var body: some View {
        GeometryReader { proxy in
            Image(asset)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .ignoresSafeArea()
    }
}

private struct ImportPostArtwork: View {
    let crop: ImportPostCrop
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Image("PlaceCarouselPhotos")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(scale)
                .offset(offset(in: proxy.size))
        }
        .clipped()
        .background(WanderTheme.surfaceSand.color)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.62), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var scale: CGFloat {
        switch crop {
        case .left, .right, .top, .bottom: 1.9
        case .center: 1.25
        }
    }

    private func offset(in size: CGSize) -> CGSize {
        switch crop {
        case .left: CGSize(width: size.width * 0.36, height: 0)
        case .right: CGSize(width: -size.width * 0.36, height: 0)
        case .top: CGSize(width: 0, height: size.height * 0.34)
        case .bottom: CGSize(width: 0, height: -size.height * 0.34)
        case .center: .zero
        }
    }
}
#endif
