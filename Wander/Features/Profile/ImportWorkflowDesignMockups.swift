#if DEBUG
import SwiftUI

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
                ImportReadyBannerMockup()
            case .complete:
                ImportCompletionMockup()
            case .offline:
                ImportOfflineMockup()
            case .failure:
                ImportFailureMockup()
            }
        }
        .tint(ImportMockTheme.terracotta)
        .preferredColorScheme(.light)
    }
}

private enum ImportReviewMockupMode {
    case ready
    case ambiguous
    case details
}

private enum ImportMockTheme {
    static let canvas = Color(red: 0.953, green: 0.875, blue: 0.792)
    static let bone = Color(red: 1, green: 0.969, blue: 0.918)
    static let raised = Color.white
    static let sand = Color(red: 0.937, green: 0.890, blue: 0.816)
    static let ink = Color(red: 0.173, green: 0.129, blue: 0.094)
    static let muted = Color(red: 0.482, green: 0.396, blue: 0.333)
    static let faint = Color(red: 0.659, green: 0.584, blue: 0.498)
    static let border = Color(red: 0.859, green: 0.761, blue: 0.667)
    static let terracotta = Color(red: 0.831, green: 0.435, blue: 0.302)
    static let terracottaDark = Color(red: 0.663, green: 0.310, blue: 0.208)
    static let terracottaTint = Color(red: 0.965, green: 0.878, blue: 0.824)
    static let success = Color(red: 0.247, green: 0.561, blue: 0.392)
    static let warning = Color(red: 0.725, green: 0.522, blue: 0.157)
    static let error = Color(red: 0.722, green: 0.290, blue: 0.227)
    static let info = Color(red: 0.310, green: 0.557, blue: 0.678)
    static let skyTint = Color(red: 0.859, green: 0.918, blue: 0.945)
    static let espresso = Color(red: 0.120, green: 0.094, blue: 0.075)
}

private struct ImportEntryMockup: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            mockMap

            VStack(spacing: 0) {
                Capsule()
                    .fill(ImportMockTheme.muted.opacity(0.45))
                    .frame(width: 36, height: 5)
                    .padding(.top, 7)

                HStack {
                    Button("Cancel") {}
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ImportMockTheme.muted)
                        .frame(minHeight: 44)

                    Spacer()

                    Text("Import places")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ImportMockTheme.ink)

                    Spacer()

                    Button("History") {}
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ImportMockTheme.terracottaDark)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 16)

                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Text("Bring your places with you")
                            .font(.system(size: 24, weight: .bold, design: .serif))
                            .foregroundStyle(ImportMockTheme.ink)
                        Text("Paste a link from Instagram, Google Maps, or TikTok.")
                            .font(.subheadline)
                            .foregroundStyle(ImportMockTheme.muted)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .font(.body.weight(.bold))
                            .foregroundStyle(ImportMockTheme.terracottaDark)
                        Text("instagram.com/reel/…")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ImportMockTheme.ink)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(ImportMockTheme.faint)
                            .frame(width: 44, height: 44)
                    }
                    .padding(.leading, 14)
                    .frame(minHeight: 58)
                    .background(ImportMockTheme.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ImportMockTheme.border, lineWidth: 1)
                    )

                    Button(action: {}) {
                        Label("Start import", systemImage: "arrow.down.doc.fill")
                            .font(.body.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(ImportMockTheme.bone)
                            .background(ImportMockTheme.terracotta)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: {}) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Your latest import is ready to review")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ImportMockTheme.success)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(ImportMockTheme.canvas)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 24,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 24,
                    style: .continuous
                )
            )
        }
        .ignoresSafeArea()
    }

    private var mockMap: some View {
        GeometryReader { proxy in
            ZStack {
                ImportMockTheme.skyTint
                Image("OnboardingMapDiary")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .opacity(0.78)
                Color.black.opacity(0.08)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

private struct ImportReviewMockup: View {
    let mode: ImportReviewMockupMode

    private var showsException: Bool { mode == .ambiguous }
    private var showsDetails: Bool { mode == .details }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    reviewHeader

                    if showsException {
                        ambiguousMatch
                        readyReceipt
                    } else if showsDetails {
                        selectedPlaces
                        readyReceipt
                    } else {
                        readyReceipt
                        selectedPlaces
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .background(ImportMockTheme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {}) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close import review")
                }
                ToolbarItem(placement: .principal) {
                    Text("Instagram import")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ImportMockTheme.ink)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 5) {
                    Button(action: {}) {
                        Label("Add 13 places", systemImage: "plus")
                            .font(.body.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .foregroundStyle(ImportMockTheme.bone)
                            .background(ImportMockTheme.espresso)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)

                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(ImportMockTheme.canvas.opacity(0.98))
            }
        }
    }

    private var reviewHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill((showsException ? ImportMockTheme.warning : ImportMockTheme.success).opacity(0.14))
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: showsException ? "sparkles" : "checkmark")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(showsException ? ImportMockTheme.warning : ImportMockTheme.success)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(showsException ? "12 ready, 1 quick check" : "All 13 places are ready")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(ImportMockTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(showsException ? "We picked the most likely match. Change it only if it looks wrong." : "Everything matched. Add details only where you want them.")
                    .font(.subheadline)
                    .foregroundStyle(ImportMockTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var readyReceipt: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ImportPostArtwork(crop: .left, cornerRadius: 10)
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text(showsException ? "Ready now" : "Ready to add")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ImportMockTheme.ink)
                    Text(showsException ? "10 new · 2 already saved" : "11 new · 2 already saved")
                        .font(.subheadline)
                        .foregroundStyle(ImportMockTheme.muted)
                }
                Spacer()
                Text(showsException ? "12" : "13")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ImportMockTheme.success)
                    .monospacedDigit()
            }
            .padding(14)

            Divider().overlay(ImportMockTheme.border)

            Button(action: {}) {
                HStack {
                    Text("Review ready places")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(ImportMockTheme.muted)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(ImportMockTheme.bone)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ImportMockTheme.border, lineWidth: 1)
        )
    }

    private var selectedPlaces: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(showsDetails ? "Details for Bar Chelou" : "Selected places")
                .font(.system(size: 21, weight: .bold, design: .serif))
                .foregroundStyle(ImportMockTheme.ink)

            ImportSelectedPlaceCard(expanded: showsDetails)
        }
    }

    private var ambiguousMatch: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Possible matches")
                    .font(.system(size: 21, weight: .bold, design: .serif))
                    .foregroundStyle(ImportMockTheme.ink)
                Spacer()
                Text("1 of 1")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ImportMockTheme.muted)
            }

            HStack(spacing: 11) {
                ImportPostArtwork(crop: .bottom, cornerRadius: 11)
                    .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text("“McDonald’s after the game”")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ImportMockTheme.ink)
                    Text("Instagram · Pasadena")
                        .font(.caption)
                        .foregroundStyle(ImportMockTheme.muted)
                }
                Spacer()
            }
            .padding(12)
            .background(ImportMockTheme.sand.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(spacing: 0) {
                ImportCandidateRow(name: "McDonald’s", detail: "1320 E Colorado Blvd · 0.7 mi", selected: true, best: true)
                Divider().padding(.leading, 68)
                ImportCandidateRow(name: "McDonald’s", detail: "770 S Arroyo Pkwy · 1.4 mi", selected: false, best: false)
                Divider().padding(.leading, 68)
                ImportCandidateRow(name: "McDonald’s", detail: "2157 Lincoln Ave · 2.8 mi", selected: false, best: false)
                Divider().padding(.leading, 68)
                ImportCandidateRow(name: "McDonald’s", detail: "988 Lake Ave · 3.1 mi", selected: false, best: false)
                Divider().padding(.leading, 68)
                ImportCandidateRow(name: "McDonald’s", detail: "1720 Colorado Blvd · 4.0 mi", selected: false, best: false)
            }
            .background(ImportMockTheme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ImportMockTheme.border, lineWidth: 1)
            )

            Button(action: {}) {
                Label("Search for a different place", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ImportMockTheme.terracottaDark)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ImportSelectedPlaceCard: View {
    let expanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ImportPostArtwork(crop: .right, cornerRadius: 10)
                    .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Bar Chelou")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ImportMockTheme.ink)
                    Text("Pasadena · French")
                        .font(.caption)
                        .foregroundStyle(ImportMockTheme.muted)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(ImportMockTheme.success)
            }
            .padding(12)

            Divider().padding(.leading, 82)

            HStack(spacing: 8) {
                ImportStatusPill(title: "Wanna", systemImage: "bookmark.fill", selected: !expanded)
                ImportStatusPill(title: "Check In", systemImage: "checkmark.circle.fill", selected: expanded)
            }
            .padding(12)

            Divider()

            Button(action: {}) {
                HStack {
                    Label(expanded ? "Hide details" : "Add details", systemImage: "slider.horizontal.3")
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ImportMockTheme.terracottaDark)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                ImportDetailsEditorMockup()
            }
        }
        .background(ImportMockTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ImportMockTheme.border, lineWidth: 1)
        )
    }
}

private struct ImportStatusPill: View {
    let title: String
    let systemImage: String
    let selected: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? ImportMockTheme.terracottaTint : ImportMockTheme.bone)
            .foregroundStyle(selected ? ImportMockTheme.terracottaDark : ImportMockTheme.muted)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(selected ? ImportMockTheme.terracotta : ImportMockTheme.border, lineWidth: selected ? 2 : 1))
    }
}

private struct ImportDetailsEditorMockup: View {
    var body: some View {
        VStack(spacing: 0) {
            detailRow("Rating", value: "Not rated", image: "star")
            Divider().padding(.leading, 48)
            detailRow("Note", value: "Why did you save this?", image: "note.text")
            Divider().padding(.leading, 48)
            detailRow("When", value: "Today", image: "calendar")
            Divider().padding(.leading, 48)
            detailRow("Category", value: "French", image: "fork.knife")
            Divider().padding(.leading, 48)
            detailRow("Friends", value: "Add people", image: "person.2")
            Divider().padding(.leading, 48)
            detailRow("Photos", value: "Add photos", image: "photo.on.rectangle")
            Divider().padding(.leading, 48)
            detailRow("Lists", value: "Add to a list", image: "square.stack.3d.up")
            Divider().padding(.leading, 48)
            detailRow("More options", value: "Visibility, tags, place type", image: "ellipsis.circle")
        }
        .background(ImportMockTheme.bone.opacity(0.72))
    }

    private func detailRow(_ title: String, value: String, image: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: image)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ImportMockTheme.terracottaDark)
                .frame(width: 26)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ImportMockTheme.ink)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(ImportMockTheme.muted)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(ImportMockTheme.faint)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
    }
}

private struct ImportCandidateRow: View {
    let name: String
    let detail: String
    let selected: Bool
    let best: Bool

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(best ? ImportMockTheme.terracottaTint : ImportMockTheme.skyTint)
                .frame(width: 46, height: 46)
                .overlay(Image(systemName: "mappin.and.ellipse").foregroundStyle(ImportMockTheme.terracottaDark))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ImportMockTheme.ink)
                    if best {
                        Text("BEST MATCH")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ImportMockTheme.success)
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ImportMockTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? ImportMockTheme.terracotta : ImportMockTheme.faint)
                .frame(width: 44, height: 44)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(minHeight: 62)
        .opacity(selected ? 1 : 0.82)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

private struct ImportHistoryMockup: View {
    private let tiles: [(ImportPostCrop, Bool)] = [
        (.left, false), (.right, true), (.top, false), (.bottom, false), (.center, false), (.right, false)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                        Button(action: {}) {
                            ImportPostArtwork(crop: tile.0, cornerRadius: 15)
                                .aspectRatio(0.84, contentMode: .fit)
                                .overlay(alignment: .topLeading) {
                                    Image(systemName: index % 3 == 0 ? "play.rectangle.fill" : index % 3 == 1 ? "map.fill" : "music.note")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 30, height: 30)
                                        .background(.black.opacity(0.44))
                                        .clipShape(Circle())
                                        .padding(8)
                                }
                                .overlay(alignment: .topTrailing) {
                                    if tile.1 {
                                        Text("2")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(minWidth: 24, minHeight: 24)
                                            .background(ImportMockTheme.warning)
                                            .clipShape(Capsule())
                                            .padding(8)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Import from August \(29 - index), \(index + 3) places")
                    }
                }
                .padding(16)
            }
            .background(ImportMockTheme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {}) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Back to import places")
                }
                ToolbarItem(placement: .principal) {
                    Text("Import history")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ImportMockTheme.ink)
                }
            }
        }
    }
}

private struct ImportReportMockup: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ImportPostArtwork(crop: .center, cornerRadius: 18)
                        .frame(height: 176)
                        .overlay(alignment: .bottomLeading) {
                            Label("Instagram · Aug 28", systemImage: "play.rectangle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 32)
                                .background(.black.opacity(0.48))
                                .clipShape(Capsule())
                                .padding(12)
                        }

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("13 places imported")
                                .font(.system(size: 24, weight: .bold, design: .serif))
                                .foregroundStyle(ImportMockTheme.ink)
                            Text("Your original choices are preserved below.")
                                .font(.subheadline)
                                .foregroundStyle(ImportMockTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(ImportMockTheme.success)
                    }

                    VStack(spacing: 0) {
                        reportRow("Bar Chelou", "Check In · 8/10 · Pasadena", "checkmark.circle.fill")
                        Divider().padding(.leading, 66)
                        reportRow("Gjusta", "Wanna · Venice", "bookmark.fill")
                        Divider().padding(.leading, 66)
                        reportRow("The Mart Collective", "Wanna · Venice", "bookmark.fill")
                    }
                    .background(ImportMockTheme.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ImportMockTheme.border, lineWidth: 1))

                    Text("10 more places")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ImportMockTheme.terracottaDark)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(16)
            }
            .background(ImportMockTheme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {}) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Back to import history")
                }
                ToolbarItem(placement: .principal) {
                    Text("Import report")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ImportMockTheme.ink)
                }
            }
        }
    }

    private func reportRow(_ name: String, _ detail: String, _ icon: String) -> some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ImportMockTheme.terracottaTint)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: icon).foregroundStyle(ImportMockTheme.terracottaDark))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ImportMockTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ImportMockTheme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(ImportMockTheme.faint)
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 62)
    }
}

private struct ImportReadyBannerMockup: View {
    var body: some View {
        ZStack(alignment: .top) {
            ImportMockMapBackground(asset: "OnboardingMapTrusted")

            HStack(spacing: 12) {
                Circle()
                    .fill(ImportMockTheme.success.opacity(0.14))
                    .frame(width: 42, height: 42)
                    .overlay(Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(ImportMockTheme.success))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your import is ready")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ImportMockTheme.ink)
                    Text("12 ready · 1 quick check")
                        .font(.caption)
                        .foregroundStyle(ImportMockTheme.muted)
                }
                Spacer()
                Button("Review") {}
                    .font(.subheadline.weight(.bold))
                Button(action: {}) {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Dismiss import banner")
            }
            .padding(.leading, 12)
            .padding(.trailing, 2)
            .frame(minHeight: 70)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ImportMockTheme.border.opacity(0.8), lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }
}

private struct ImportCompletionMockup: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            ImportMockMapBackground(asset: "OnboardingMapTrusted")

            VStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(ImportMockTheme.success)
                Text("13 places added")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ImportMockTheme.ink)
                Text("We’ll finish syncing in the background.")
                    .font(.caption)
                    .foregroundStyle(ImportMockTheme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
            .padding(.bottom, 90)
        }
    }
}

private struct ImportOfflineMockup: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            ImportMockMapBackground(asset: "OnboardingMapDiary")

            HStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ImportMockTheme.info)
                    .frame(width: 42, height: 42)
                    .background(ImportMockTheme.skyTint)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved on this phone")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ImportMockTheme.ink)
                    Text("We’ll sync 13 places when you’re back online.")
                        .font(.caption)
                        .foregroundStyle(ImportMockTheme.muted)
                }
                Spacer()
            }
            .padding(12)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 84)
        }
    }
}

private struct ImportFailureMockup: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            ImportMockMapBackground(asset: "OnboardingMapDiary")

            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ImportMockTheme.error)
                    .frame(width: 42, height: 42)
                    .background(ImportMockTheme.error.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("3 places still need saving")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ImportMockTheme.ink)
                    Text("Your link and choices are safe.")
                        .font(.caption)
                        .foregroundStyle(ImportMockTheme.muted)
                }
                Spacer()
                Button("Retry") {}
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ImportMockTheme.error)
                    .frame(minWidth: 54, minHeight: 44)
            }
            .padding(12)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ImportMockTheme.error.opacity(0.35), lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.bottom, 84)
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

private enum ImportPostCrop {
    case left
    case right
    case top
    case bottom
    case center
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
        .background(ImportMockTheme.sand)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.62), lineWidth: 1)
        )
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
