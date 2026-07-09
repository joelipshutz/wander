#if DEBUG
import SwiftUI

enum PlaceActivityMockupPage: String, CaseIterable {
    case quickSearch
    case compactCard
    case latestActivity
    case myVisits
    case addVisit
    case photoMenu
    case photoViewer
    case friendView

    static func resolved(from arguments: [String] = ProcessInfo.processInfo.arguments) -> PlaceActivityMockupPage? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderPlaceActivityMockup") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .latestActivity
        }

        return PlaceActivityMockupPage(rawValue: arguments[valueIndex]) ?? .latestActivity
    }
}

struct PlaceActivityMockupRoot: View {
    let page: PlaceActivityMockupPage

    var body: some View {
        Group {
            switch page {
            case .quickSearch:
                ClassicQuickSearchMockup()
            case .compactCard:
                ClassicCompactCardMockup()
            case .latestActivity:
                ClassicPlaceDetailMockup(selectedSegment: "ALL", entries: ClassicActivityData.all, mode: .owner)
            case .myVisits:
                ClassicPlaceDetailMockup(selectedSegment: "MY VISITS", entries: ClassicActivityData.mine, mode: .owner)
            case .addVisit:
                ClassicAddVisitMockup(showsMenu: false)
            case .photoMenu:
                ClassicAddVisitMockup(showsMenu: true)
            case .photoViewer:
                ClassicPhotoViewerMockup()
            case .friendView:
                ClassicPlaceDetailMockup(selectedSegment: "ALL", entries: ClassicActivityData.friendVisible, mode: .friend)
            }
        }
        .preferredColorScheme(.light)
    }
}

private enum ClassicPlaceMode {
    case owner
    case friend
}

private enum ClassicSaveBadgeState {
    case none
    case wanna
    case been
}

private struct ClassicActivityEntry: Identifiable {
    let id = UUID()
    let name: String
    let handle: String
    let initials: String
    let avatarColor: Color
    let date: String
    let status: String
    let visibility: String
    let rating: Double?
    let tags: [String]
    let note: String
    let photos: Int
    let isMine: Bool
}

private enum ClassicActivityData {
    static let latest = ClassicActivityEntry(
        name: "You",
        handle: "ryan",
        initials: "RL",
        avatarColor: WanderTheme.terracotta.color,
        date: "Jun 30, 11:21 PM",
        status: "been",
        visibility: "friends",
        rating: 5,
        tags: ["quick bite", "date night", "looks cozy"],
        note: "Sat at the bar after Venice. Fast enough for a weeknight, still feels like a real plan.",
        photos: 3,
        isMine: true
    )

    static let privateVisit = ClassicActivityEntry(
        name: "You",
        handle: "ryan",
        initials: "RL",
        avatarColor: WanderTheme.terracotta.color,
        date: "May 18, 7:44 PM",
        status: "been",
        visibility: "only me",
        rating: 4,
        tags: ["solo dinner", "bar seats"],
        note: "Good solo save. Keep this private because it is more about timing than the place.",
        photos: 1,
        isMine: true
    )

    static let roughVisit = ClassicActivityEntry(
        name: "You",
        handle: "ryan",
        initials: "RL",
        avatarColor: WanderTheme.terracotta.color,
        date: "Apr 6, 9:36 PM",
        status: "been",
        visibility: "friends",
        rating: 1.5,
        tags: ["late night", "crowded"],
        note: "Useful in a pinch, but not the night I would plan around.",
        photos: 1,
        isMine: true
    )

    static let joe = ClassicActivityEntry(
        name: "Joe Lipshutz",
        handle: "jolipshutz",
        initials: "JL",
        avatarColor: WanderTheme.pinSocial.color,
        date: "Jun 29, 8:14 PM",
        status: "wanna",
        visibility: "friends",
        rating: nil,
        tags: ["wanna go", "excited", "quick bite", "date night", "looks cozy"],
        note: "Looks cozy. Save this for an easy Venice dinner.",
        photos: 0,
        isMine: false
    )

    static let maya = ClassicActivityEntry(
        name: "Maya Chen",
        handle: "mayac",
        initials: "MC",
        avatarColor: WanderTheme.avatarAndrew.color,
        date: "Jun 11, 9:02 PM",
        status: "been",
        visibility: "friends",
        rating: 4.5,
        tags: ["walk-in", "good counter", "share plates"],
        note: "Tiny wait, good counter seats, better as a two-person dinner than a big group.",
        photos: 2,
        isMine: false
    )

    static let all = [latest, joe, maya]
    static let mine = [latest, privateVisit, roughVisit]
    static let friendVisible = [maya, joe]
}

private struct ClassicPlacePhoto: Identifiable {
    let id = UUID()
    let ownerName: String
    let initials: String
    let avatarColor: Color
    let date: String
    let visibility: String
    let rating: Double?
    let note: String
    let imageSystemName: String
    let colors: [Color]
    let isMine: Bool
}

private enum ClassicPlacePhotoData {
    static let photos = [
        ClassicPlacePhoto(
            ownerName: "Ryan",
            initials: "RL",
            avatarColor: WanderTheme.terracotta.color,
            date: "Jun 30, 11:21 PM",
            visibility: "friends",
            rating: 5,
            note: "Sat at the bar after Venice. Fast enough for a weeknight, still feels like a real plan.",
            imageSystemName: "fork.knife",
            colors: [WanderTheme.terracottaTint.color, WanderTheme.sunTint.color],
            isMine: true
        ),
        ClassicPlacePhoto(
            ownerName: "Maya",
            initials: "MC",
            avatarColor: WanderTheme.avatarAndrew.color,
            date: "Jun 11, 9:02 PM",
            visibility: "friends",
            rating: 4.5,
            note: "Tiny wait, good counter seats, better as a two-person dinner than a big group.",
            imageSystemName: "wineglass.fill",
            colors: [WanderTheme.skyTint.color, WanderTheme.surfaceBone.color],
            isMine: false
        ),
        ClassicPlacePhoto(
            ownerName: "Ryan",
            initials: "RL",
            avatarColor: WanderTheme.terracotta.color,
            date: "May 18, 7:44 PM",
            visibility: "only me",
            rating: 4,
            note: "Good solo save. Keep this private because it is more about timing than the place.",
            imageSystemName: "chair.lounge.fill",
            colors: [WanderTheme.categorySage.color.opacity(0.5), WanderTheme.surfaceBone.color],
            isMine: true
        )
    ]
}

private struct ClassicQuickSearchMockup: View {
    var body: some View {
        ZStack(alignment: .top) {
            ClassicMapBackground()
                .ignoresSafeArea()

            VStack(spacing: WanderTheme.spacing3) {
                ClassicSearchBar()
                    .padding(.top, 12)

                ClassicSearchResultRow()

                Spacer()
            }
            .padding(.horizontal, WanderTheme.spacing4)
        }
    }
}

private struct ClassicCompactCardMockup: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            ClassicMapBackground()
                .ignoresSafeArea()

            VStack {
                ClassicMapControls()
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.top, 12)
                Spacer()
            }

            ClassicMapPin(badge: .been)
                .offset(y: -235)

            ClassicCompactCard()
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing4)
        }
    }
}

private struct ClassicPlaceDetailMockup: View {
    let selectedSegment: String
    let entries: [ClassicActivityEntry]
    let mode: ClassicPlaceMode

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ClassicMapHeader(badge: mode == .owner ? .been : .none)

                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    ClassicDashedPrompt(text: mode == .owner ? "Add a new visit when this place belongs on your map." : "Add your own visit to save this place to your map.")

                    ClassicDirectionsButton()

                    ClassicActivitySection(selectedSegment: selectedSegment, entries: entries, mode: mode)

                    ClassicPlaceDetails()
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing1)
                .padding(.bottom, WanderTheme.spacing8)
                .background(WanderTheme.canvasWarm.color)
            }
        }
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
    }
}

private struct ClassicAddVisitMockup: View {
    let showsMenu: Bool
    @State private var showsPhotoOptions = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                ClassicEditorNav(title: "add a visit")
                ClassicEditorPlaceHeader()

                ClassicEditorSection(title: "VISIT") {
                    ClassicSegmented(options: ["BEEN", "WANNA"], selected: "BEEN")
                    ClassicRatingPicker()
                }

                ClassicEditorSection(title: "TAGS") {
                    ClassicTagWrap(tags: ["quick bite", "date night", "bar seats", "looks cozy", "walk-in"])
                }

                ClassicEditorSection(title: "PHOTOS") {
                    HStack(spacing: WanderTheme.spacing2) {
                        ClassicPhotoAddTile()
                        ClassicPhotoTile(index: 0)
                        ClassicPhotoTile(index: 1)
                        Spacer()
                    }
                }

                ClassicEditorSection(title: "NOTE") {
                    ClassicNoteEditor()
                }

                ClassicEditorSection(title: "VISIBILITY") {
                    ClassicSegmented(options: ["FRIENDS", "MUTUALS", "ONLY ME"], selected: "FRIENDS")
                }

                ClassicPrimaryButton(title: "save visit", systemImage: "checkmark")
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, 14)
            .padding(.bottom, WanderTheme.spacing8)
        }
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
        .confirmationDialog("Add photos to your visit", isPresented: $showsPhotoOptions, titleVisibility: .visible) {
            Button("Take Photo") {}
            Button("Choose from Library") {}
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            if showsMenu {
                showsPhotoOptions = true
            }
        }
    }
}

private struct ClassicPhotoViewerMockup: View {
    @State private var selectedPhotoIndex = 0

    var body: some View {
        let activePhoto = ClassicPlacePhotoData.photos[selectedPhotoIndex]

        ZStack {
            Color(red: 0.07, green: 0.055, blue: 0.045)
                .ignoresSafeArea()

            VStack {
                HStack {
                    ClassicViewerButton(systemImage: "xmark")
                    Spacer()
                    ClassicViewerButton(systemImage: "square.and.arrow.up")
                    if activePhoto.isMine {
                        ClassicViewerButton(systemImage: "trash", tint: WanderTheme.stateError.color)
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, 14)

                Spacer(minLength: WanderTheme.spacing6)

                TabView(selection: $selectedPhotoIndex) {
                    ForEach(Array(ClassicPlacePhotoData.photos.enumerated()), id: \.element.id) { index, photo in
                        RoundedRectangle(cornerRadius: WanderTheme.radiusSheet)
                            .fill(
                                LinearGradient(
                                    colors: photo.colors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                VStack(spacing: WanderTheme.spacing2) {
                                    Image(systemName: photo.imageSystemName)
                                        .font(.system(size: 54, weight: .bold))
                                    Text("visit photo")
                                        .font(.system(size: 20, weight: .black))
                                }
                                .foregroundStyle(WanderTheme.textMuted.color.opacity(0.75))
                            }
                            .padding(.horizontal, WanderTheme.spacing4)
                            .tag(index)
                        }
                    }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 540)

                Spacer(minLength: WanderTheme.spacing6)

                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    HStack(spacing: WanderTheme.spacing2) {
                        ClassicAvatar(initials: activePhoto.initials, color: activePhoto.avatarColor, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RVR")
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(.white)
                            Text("\(activePhoto.ownerName) - \(activePhoto.date) - \(activePhoto.visibility)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.65))
                        }

                        Spacer()

                        if let rating = activePhoto.rating {
                            Text("\(ClassicRatingDisplay.string(rating))/5")
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(.white.opacity(0.84))
                        }
                    }

                    Text(activePhoto.note)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(WanderTheme.spacing4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing3)
            }
        }
    }
}

private struct ClassicMapHeader: View {
    let badge: ClassicSaveBadgeState

    var body: some View {
        ZStack(alignment: .top) {
            ClassicMapBackground()

            ClassicMapControls()
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, 12)

            ClassicMapPin(badge: badge)
                .padding(.top, 108)
        }
        .frame(height: 335)
    }
}

private struct ClassicMapControls: View {
    var body: some View {
        HStack {
            ClassicCircleButton(systemImage: "chevron.left", fill: WanderTheme.surfaceBone.color, foreground: WanderTheme.textInk.color, size: 64)
            Spacer()
            ClassicCircleButton(systemImage: "plus", fill: WanderTheme.textInk.color, foreground: WanderTheme.textOnAction.color, size: 64)
            ClassicCircleButton(systemImage: "square.and.arrow.up", fill: WanderTheme.surfaceBone.color, foreground: WanderTheme.textInk.color, size: 64)
        }
    }
}

private struct ClassicMapPin: View {
    let badge: ClassicSaveBadgeState

    var body: some View {
        VStack(spacing: 5) {
            ClassicCategoryIcon(size: 94, badge: badge)
            Text("RVR")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .padding(.horizontal, WanderTheme.spacing2)
                .padding(.vertical, 3)
                .background(WanderTheme.surfaceBone.color.opacity(0.96))
                .clipShape(Capsule())
        }
    }
}

private struct ClassicActivitySection: View {
    let selectedSegment: String
    let entries: [ClassicActivityEntry]
    let mode: ClassicPlaceMode

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            ClassicSectionTitle("LATEST ACTIVITY")

            ClassicSegmented(options: ["ALL", "MY VISITS"], selected: selectedSegment)

            ClassicRatingSummary(mode: mode)

            VStack(spacing: WanderTheme.spacing3) {
                ForEach(entries) { entry in
                    ClassicActivityCard(entry: entry)
                }
            }
        }
    }
}

private struct ClassicRatingSummary: View {
    let mode: ClassicPlaceMode

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            ClassicMetricCard(
                title: "Your rating",
                value: mode == .owner ? "3.5" : "No visits yet",
                suffix: mode == .owner ? "/5" : "",
                subtitle: mode == .owner ? "3 visits" : "0 visits",
                systemImage: "star.fill",
                tint: WanderTheme.stateWarning.color
            )

            ClassicMetricCard(
                title: "Rec.me rating",
                value: "4.5",
                suffix: "/5",
                subtitle: "2 ratings",
                systemImage: "person.2.fill",
                tint: WanderTheme.pinSocial.color
            )

            ClassicMetricCard(
                title: "Fit",
                value: "8.1",
                suffix: "/10",
                subtitle: "for you",
                systemImage: "sparkles",
                tint: WanderTheme.terracotta.color
            )
        }
    }
}

private struct ClassicMetricCard: View {
    let title: String
    let value: String
    let suffix: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8.5, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: suffix.isEmpty ? 11 : 20, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(suffix.isEmpty ? 2 : 1)
                        .minimumScaleFactor(0.5)
                    if !suffix.isEmpty {
                        Text(suffix)
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                }

                Text(subtitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }
}

private struct ClassicActivityCard: View {
    let entry: ClassicActivityEntry

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .top, spacing: WanderTheme.spacing2) {
                ClassicAvatar(initials: entry.initials, color: entry.avatarColor, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("@\(entry.handle)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Text(entry.date)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.textFaint.color)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: WanderTheme.spacing2) {
                    HStack(spacing: WanderTheme.spacing1) {
                        ClassicStatusPill(title: entry.status, selected: true)
                        ClassicStatusPill(title: entry.visibility, selected: false)
                    }
                    if entry.isMine {
                        HStack(spacing: WanderTheme.spacing3) {
                            Image(systemName: "pencil")
                            Image(systemName: "trash")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    }
                }
            }

            if let rating = entry.rating {
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { value in
                        Image(systemName: ClassicRatingDisplay.starSymbol(for: Double(value), rating: rating))
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(WanderTheme.categorySun.color)
                    }
                    Text("\(ClassicRatingDisplay.string(rating))/5")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .padding(.leading, 3)
                }
            }

            ClassicTagWrap(tags: entry.tags)

            Text("\"\(entry.note)\"")
                .font(.system(size: 14, weight: .medium))
                .italic()
                .foregroundStyle(WanderTheme.textMuted.color)
                .fixedSize(horizontal: false, vertical: true)

            if entry.photos > 0 || entry.isMine {
                HStack(spacing: WanderTheme.spacing2) {
                    ForEach(0..<min(entry.photos, 3), id: \.self) { index in
                        ClassicPhotoTile(index: index)
                    }
                    if entry.isMine {
                        ClassicPhotoAddTile()
                    }
                    Spacer()
                }
            }
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(entry.isMine ? WanderTheme.surfaceSand.color : WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(entry.isMine ? WanderTheme.borderStrong.color.opacity(0.5) : WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }
}

private struct ClassicCompactCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                ClassicCategoryIcon(size: 58, badge: .been)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: WanderTheme.spacing2) {
                        Text("RVR")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(WanderTheme.textInk.color)
                        ClassicStatusPill(title: "been", selected: true)
                    }
                    Text("Your rating 3.5/5 - 3 visits")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(2)
                    Text("\"Sat at the bar after Venice.\"")
                        .font(.system(size: 13, weight: .medium))
                        .italic()
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(2)
                }
                Spacer()
            }

            ClassicTagWrap(tags: ["quick bite", "date night", "looks cozy"])
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSheet))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusSheet)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

private struct ClassicSearchBar: View {
    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
            Text("rvr")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(WanderTheme.textFaint.color)
        }
        .frame(minHeight: 56)
        .padding(.horizontal, WanderTheme.spacing4)
        .background(WanderTheme.surfaceRaised.color.opacity(0.96))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }
}

private struct ClassicSearchResultRow: View {
    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            ClassicCategoryIcon(size: 54, badge: .wanna)
            VStack(alignment: .leading, spacing: 4) {
                Text("RVR")
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("Saved as wanna - Restaurant")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
            ClassicCircleButton(systemImage: "plus", fill: WanderTheme.pinSocial.color, foreground: WanderTheme.textOnAction.color, size: 46)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 14, y: 6)
    }
}

private struct ClassicEditorNav: View {
    let title: String

    var body: some View {
        HStack {
            ClassicCircleButton(systemImage: "xmark", fill: WanderTheme.surfaceBone.color, foreground: WanderTheme.textInk.color, size: 52)
            Spacer()
            Text(title)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
            Spacer()
            ClassicCircleButton(systemImage: "checkmark", fill: WanderTheme.textInk.color, foreground: WanderTheme.textOnAction.color, size: 52)
        }
    }
}

private struct ClassicEditorPlaceHeader: View {
    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            ClassicCategoryIcon(size: 58, badge: .been)
            VStack(alignment: .leading, spacing: 3) {
                Text("RVR")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("Existing save - new visit")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }
}

private struct ClassicEditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            ClassicSectionTitle(title)
            content
        }
    }
}

private struct ClassicRatingPicker: View {
    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            ForEach(1...5, id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.system(size: 25, weight: .black))
                    .foregroundStyle(WanderTheme.categorySun.color)
                    .frame(width: 34, height: 38)
            }
            Spacer()
            Text("5/5")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }
}

private struct ClassicNoteEditor: View {
    var body: some View {
        Text("Sat at the bar after Venice. Fast enough for a weeknight, still feels like a real plan.")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(WanderTheme.textInk.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )
    }
}

private struct ClassicPlaceDetails: View {
    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            ClassicSectionTitle("PLACE DETAILS")
            VStack(spacing: WanderTheme.spacing2) {
                ClassicDetailRow(label: "Category", value: "Restaurant - Food & Drink")
                Divider().background(WanderTheme.borderHairline.color)
                ClassicDetailRow(label: "Source", value: "Saved place")
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )
        }
    }
}

private struct ClassicDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct ClassicDashedPrompt: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(WanderTheme.textMuted.color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, WanderTheme.spacing3)
            .padding(.horizontal, WanderTheme.spacing4)
            .background(WanderTheme.surfaceSand.color.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderStrong.color, style: StrokeStyle(lineWidth: 1.3, dash: [7, 5]))
            )
    }
}

private struct ClassicDirectionsButton: View {
    var body: some View {
        ClassicPrimaryButton(title: "Directions", systemImage: "location.fill")
    }
}

private struct ClassicPrimaryButton: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .black))
            Text(title)
                .font(.system(size: 20, weight: .black))
        }
        .foregroundStyle(WanderTheme.textOnAction.color)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(WanderTheme.terracotta.color)
        .clipShape(Capsule())
    }
}

private struct ClassicSegmented: View {
    let options: [String]
    let selected: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Text(option)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(option == selected ? WanderTheme.textInk.color : WanderTheme.textMuted.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(option == selected ? WanderTheme.surfaceRaised.color : Color.clear)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(option == selected ? WanderTheme.terracotta.color : Color.clear, lineWidth: 2)
                    )
            }
        }
        .padding(4)
        .background(WanderTheme.surfaceSand.color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(WanderTheme.borderHairline.color.opacity(0.75), lineWidth: 1))
    }
}

private struct ClassicTagWrap: View {
    let tags: [String]

    private let columns = [
        GridItem(.adaptive(minimum: 88), spacing: WanderTheme.spacing2, alignment: .leading)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: WanderTheme.spacing2) {
            ForEach(tags, id: \.self) { tag in
                ClassicTag(title: tag)
            }
        }
    }
}

private struct ClassicTag: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(WanderTheme.textInk.color)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 36)
            .background(WanderTheme.surfaceSand.color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
    }
}

private struct ClassicStatusPill: View {
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(selected ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
            .padding(.horizontal, WanderTheme.spacing2)
            .frame(height: 30)
            .background(selected ? WanderTheme.terracotta.color : WanderTheme.surfaceBone.color)
            .clipShape(Capsule())
    }
}

private struct ClassicSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .black))
            .foregroundStyle(WanderTheme.textMuted.color)
    }
}

private struct ClassicPhotoTile: View {
    let index: Int

    var body: some View {
        RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: index == 0 ? "fork.knife" : "wineglass.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color.opacity(0.52))
            }
            .frame(width: 68, height: 68)
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )
    }

    private var colors: [Color] {
        switch index % 3 {
        case 0:
            return [WanderTheme.terracottaTint.color, WanderTheme.sunTint.color]
        case 1:
            return [WanderTheme.skyTint.color, WanderTheme.surfaceBone.color]
        default:
            return [WanderTheme.categorySage.color.opacity(0.5), WanderTheme.surfaceBone.color]
        }
    }
}

private struct ClassicPhotoAddTile: View {
    var body: some View {
        VStack(spacing: WanderTheme.spacing1) {
            Image(systemName: "camera.fill")
                .font(.system(size: 18, weight: .black))
            Text("photo")
                .font(.system(size: 11, weight: .black))
        }
        .foregroundStyle(WanderTheme.textInk.color)
        .frame(width: 68, height: 68)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                .stroke(WanderTheme.borderStrong.color, style: StrokeStyle(lineWidth: 1.3, dash: [6, 4]))
        )
    }
}

private enum ClassicRatingDisplay {
    static func string(_ value: Double) -> String {
        if value == Double(Int(value)) {
            return "\(Int(value))"
        }

        return "\(value)"
    }

    static func starSymbol(for position: Double, rating: Double) -> String {
        if rating >= position {
            return "star.fill"
        }

        if rating >= position - 0.5 {
            return "star.leadinghalf.filled"
        }

        return "star"
    }
}

private struct ClassicCategoryIcon: View {
    let size: CGFloat
    let badge: ClassicSaveBadgeState

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(WanderTheme.terracottaTint.color)
                .overlay(Circle().stroke(WanderTheme.surfaceBone.color, lineWidth: 7))

            Image(systemName: "fork.knife")
                .font(.system(size: size * 0.36, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
                .frame(width: size, height: size)

            switch badge {
            case .none:
                EmptyView()
            case .been:
                ZStack {
                    Circle().fill(WanderTheme.stateSuccess.color)
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.18, weight: .black))
                        .foregroundStyle(WanderTheme.textOnAction.color)
                }
                .frame(width: size * 0.34, height: size * 0.34)
                .overlay(Circle().stroke(WanderTheme.surfaceRaised.color, lineWidth: 2))
                .offset(x: 1, y: -1)
            case .wanna:
                Circle()
                    .fill(WanderTheme.surfaceRaised.color.opacity(0.96))
                    .frame(width: size * 0.34, height: size * 0.34)
                    .overlay(
                        Circle()
                            .stroke(
                                WanderTheme.stateSuccess.color,
                                style: StrokeStyle(lineWidth: 2.8, lineCap: .round, dash: [2.8, 3.2])
                            )
                    )
                    .offset(x: 1, y: -1)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct ClassicCircleButton: View {
    let systemImage: String
    let fill: Color
    let foreground: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.34, weight: .black))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(fill.opacity(0.96))
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
    }
}

private struct ClassicAvatar: View {
    let initials: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .black))
            .foregroundStyle(WanderTheme.textOnAction.color)
            .frame(width: size, height: size)
            .background(color)
            .clipShape(Circle())
            .overlay(Circle().stroke(WanderTheme.surfaceRaised.color, lineWidth: 2))
    }
}

private struct ClassicViewerButton: View {
    let systemImage: String
    var tint: Color = .white

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .black))
            .foregroundStyle(tint)
            .frame(width: 54, height: 54)
            .background(Color.white.opacity(0.13))
            .clipShape(Circle())
    }
}

private struct ClassicMapBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                WanderTheme.surfaceBone.color

                Rectangle()
                    .fill(WanderTheme.skyTint.color.opacity(0.62))
                    .frame(width: proxy.size.width * 0.58, height: proxy.size.height * 1.35)
                    .rotationEffect(.degrees(25))
                    .offset(x: -proxy.size.width * 0.44, y: proxy.size.height * 0.14)

                ForEach(0..<8, id: \.self) { index in
                    Rectangle()
                        .fill(WanderTheme.borderHairline.color.opacity(0.56))
                        .frame(width: 2, height: proxy.size.height * 1.4)
                        .rotationEffect(.degrees(25))
                        .offset(x: CGFloat(index) * 58 - 190, y: -10)
                }

                ForEach(0..<7, id: \.self) { index in
                    Rectangle()
                        .fill(WanderTheme.borderHairline.color.opacity(0.46))
                        .frame(width: proxy.size.width * 1.5, height: 2)
                        .rotationEffect(.degrees(-20))
                        .offset(x: 0, y: CGFloat(index) * 54 - 150)
                }

                Rectangle()
                    .fill(WanderTheme.borderStrong.color.opacity(0.38))
                    .frame(width: proxy.size.width * 1.5, height: 7)
                    .rotationEffect(.degrees(-23))
                    .offset(x: 42, y: 38)

                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, WanderTheme.canvasWarm.color.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: proxy.size.height * 0.34)
                }
            }
        }
    }
}

#endif
