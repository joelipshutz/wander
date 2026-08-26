#if DEBUG
import SwiftUI

enum MapListEntryMockupPage: String, CaseIterable {
    case cardEntry
    case listPicker
    case profileEntry

    static func resolved(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> MapListEntryMockupPage? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderMapListEntryMockup") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .cardEntry
        }

        return MapListEntryMockupPage(rawValue: arguments[valueIndex]) ?? .cardEntry
    }
}

struct MapListEntryMockupRoot: View {
    let page: MapListEntryMockupPage

    var body: some View {
        Group {
            switch page {
            case .cardEntry:
                MapListCardEntryMockup()
            case .listPicker:
                MapListPickerMockup()
            case .profileEntry:
                MapListProfileEntryMockup()
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct MapListCardEntryMockup: View {
    var body: some View {
        ZStack {
            MapListMockMapBackground()

            VStack(spacing: WanderTheme.spacing3) {
                MapListMockSearchBar()
                Spacer(minLength: 0)
                MapListMockPlaceCard(highlightListAction: true)
                MapListMockTabBar()
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .padding(.top, WanderTheme.spacing2)
            .padding(.bottom, WanderTheme.spacing1)
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("map-list-mockup.card-entry")
    }
}

private struct MapListPickerMockup: View {
    @State private var selectedIDs: Set<String> = ["weekend", "austin"]

    private let yourLists = [
        MapListMockList(
            id: "weekend",
            name: "LA weekend",
            detail: "Only yours · 8 places",
            systemImage: "lock.fill",
            tint: WanderTheme.terracotta.color
        ),
        MapListMockList(
            id: "date-night",
            name: "Date night",
            detail: "Only yours · 14 places",
            systemImage: "lock.fill",
            tint: WanderTheme.categoryMoss.color
        )
    ]

    private let collabLists = [
        MapListMockList(
            id: "austin",
            name: "Austin wedding trip",
            detail: "You + 3 · 11 places",
            systemImage: "person.2.fill",
            tint: WanderTheme.pinSocial.color
        ),
        MapListMockList(
            id: "joe-recs",
            name: "Joe recs",
            detail: "You + Joe · 22 places",
            systemImage: "person.2.fill",
            tint: WanderTheme.categorySun.color
        )
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            MapListMockMapBackground()
                .overlay(Color.black.opacity(0.24))

            VStack(spacing: WanderTheme.spacing3) {
                Capsule()
                    .fill(WanderTheme.borderStrong.color)
                    .frame(width: 42, height: 5)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("add to lists")
                            .font(WanderTypography.actionScreenTitle)
                            .foregroundStyle(WanderTheme.textInk.color)
                        Text("Bestia")
                            .font(WanderTypography.metadata)
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }

                    Spacer()

                    Button("Cancel") {}
                        .font(WanderTypography.label)
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .frame(minHeight: WanderTheme.tapMinimum)
                }

                Button {} label: {
                    HStack(spacing: WanderTheme.spacing3) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .black))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(WanderTheme.textOnAction.color)
                            .background(WanderTheme.terracotta.color)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text("new list")
                                .font(WanderTypography.control)
                            Text("Create it and add this place")
                                .font(WanderTypography.metadata)
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WanderTheme.textFaint.color)
                    }
                    .foregroundStyle(WanderTheme.textInk.color)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .frame(minHeight: 60)
                    .background(WanderTheme.terracottaTint.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                }
                .buttonStyle(.plain)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                        listSection(title: "your lists", lists: yourLists)
                        listSection(title: "collabs", lists: collabLists)
                    }
                }

                HStack(alignment: .top, spacing: WanderTheme.spacing2) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .frame(width: 18, height: 18)

                    Text("This place isn’t on your map yet, so we’ll also save it to Wanna Go. You can edit that after.")
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {} label: {
                    Text(doneButtonTitle)
                        .font(WanderTypography.control)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(WanderTheme.textOnAction.color)
                        .background(WanderTheme.terracotta.color)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing2)
            .padding(.bottom, WanderTheme.spacing3)
            .frame(maxHeight: 700)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: WanderTheme.radiusSheet,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: WanderTheme.radiusSheet
                )
            )
            .shadow(color: Color.black.opacity(0.18), radius: 24, y: -8)
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("map-list-mockup.list-picker")
    }

    private var doneButtonTitle: String {
        switch selectedIDs.count {
        case 0:
            "Done"
        case 1:
            "Add to 1 list"
        default:
            "Add to \(selectedIDs.count) lists"
        }
    }

    private func listSection(title: String, lists: [MapListMockList]) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 11, weight: .black))
                .textCase(.uppercase)
                .foregroundStyle(WanderTheme.textMuted.color)

            VStack(spacing: 0) {
                ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
                    Button {
                        if selectedIDs.contains(list.id) {
                            selectedIDs.remove(list.id)
                        } else {
                            selectedIDs.insert(list.id)
                        }
                    } label: {
                        MapListMockListRow(
                            list: list,
                            isSelected: selectedIDs.contains(list.id)
                        )
                    }
                    .buttonStyle(.plain)

                    if index < lists.count - 1 {
                        Divider()
                            .overlay(WanderTheme.borderHairline.color)
                            .padding(.leading, 52)
                    }
                }
            }
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            }
        }
    }
}

private struct MapListProfileEntryMockup: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        LinearGradient(
                            colors: [
                                WanderTheme.terracottaDark.color,
                                Color(red: 0.18, green: 0.10, blue: 0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: 320)

                        Image(systemName: "fork.knife")
                            .font(.system(size: 128, weight: .thin))
                            .foregroundStyle(Color.white.opacity(0.12))
                            .padding(.top, 104)

                        HStack(spacing: WanderTheme.spacing2) {
                            MapListProfileCircleButton(systemName: "chevron.left")
                            Spacer()
                            MapListProfileCircleButton(systemName: "square.and.arrow.up")
                        }
                        .padding(.horizontal, WanderTheme.spacing3)
                        .padding(.top, WanderTheme.spacing3)
                    }

                    VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                            Text("Bestia")
                                .font(WanderTypography.editorialDisplay)
                                .foregroundStyle(WanderTheme.textInk.color)
                            Text("Italian restaurant · Arts District")
                                .font(WanderTypography.label)
                                .foregroundStyle(WanderTheme.textMuted.color)

                            HStack(spacing: WanderTheme.spacing2) {
                                Label("4.7 rec.me", systemImage: "star.fill")
                                Text("·")
                                Text("1.2 mi")
                            }
                            .font(WanderTypography.label)
                            .foregroundStyle(WanderTheme.textInk.color)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: WanderTheme.spacing2) {
                                MapListProfileAction(
                                    title: "Add to list",
                                    systemImage: "rectangle.stack.badge.plus",
                                    isListAction: true
                                )
                                MapListProfileAction(title: "Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                                MapListProfileAction(title: "Call", systemImage: "phone.fill")
                            }
                        }

                        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                            Text("best for")
                                .font(WanderTypography.editorialSectionTitle)
                            HStack(spacing: WanderTheme.spacing2) {
                                MapListMockChip(title: "date night")
                                MapListMockChip(title: "share plates")
                                MapListMockChip(title: "lively")
                            }
                        }

                        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                            Text("friends’ notes")
                                .font(WanderTypography.editorialSectionTitle)

                            Text("“Order more than you think. The patio is the move before 7.”")
                                .font(WanderTypography.body)
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .padding(WanderTheme.spacing4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(WanderTheme.surfaceRaised.color)
                                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                                .overlay {
                                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                                        .stroke(WanderTheme.borderHairline.color)
                                }
                        }
                    }
                    .padding(WanderTheme.spacing4)
                    .padding(.bottom, 108)
                }
            }
            .background(WanderTheme.surfaceBone.color)

            HStack(spacing: WanderTheme.spacing2) {
                MapListProfileSaveButton(title: "Check in", systemImage: "checkmark.circle", isPrimary: true)
                MapListProfileSaveButton(title: "Wanna", systemImage: "bookmark", isPrimary: false)
            }
            .padding(.horizontal, WanderTheme.spacing6)
            .padding(.vertical, WanderTheme.spacing2)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityIdentifier("map-list-mockup.profile-entry")
    }
}

private struct MapListMockList: Identifiable {
    let id: String
    let name: String
    let detail: String
    let systemImage: String
    let tint: Color
}

private struct MapListMockListRow: View {
    let list: MapListMockList
    let isSelected: Bool

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: list.systemImage)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 36, height: 36)
                .foregroundStyle(list.tint)
                .background(list.tint.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(WanderTypography.label)
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(list.detail)
                    .font(WanderTypography.metadata)
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isSelected ? WanderTheme.terracotta.color : WanderTheme.borderStrong.color)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

private struct MapListMockMapBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.93, green: 0.90, blue: 0.83)

                RoundedRectangle(cornerRadius: 42)
                    .fill(WanderTheme.categorySage.color.opacity(0.46))
                    .frame(width: proxy.size.width * 0.72, height: proxy.size.height * 0.26)
                    .rotationEffect(.degrees(-11))
                    .offset(x: proxy.size.width * 0.24, y: -proxy.size.height * 0.24)

                RoundedRectangle(cornerRadius: 30)
                    .fill(WanderTheme.skyTint.color.opacity(0.82))
                    .frame(width: proxy.size.width * 0.46, height: proxy.size.height * 0.58)
                    .rotationEffect(.degrees(9))
                    .offset(x: -proxy.size.width * 0.46, y: proxy.size.height * 0.28)

                MapListMockRoads()
                    .stroke(Color.white.opacity(0.88), style: StrokeStyle(lineWidth: 15, lineCap: .round, lineJoin: .round))
                MapListMockRoads()
                    .stroke(WanderTheme.borderStrong.color.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                VStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                    Text("Bestia")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(WanderTheme.surfaceRaised.color)
                        .clipShape(Capsule())
                }
                .offset(x: 42, y: -40)
            }
        }
    }
}

private struct MapListMockRoads: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -30, y: rect.height * 0.30))
        path.addCurve(
            to: CGPoint(x: rect.width + 40, y: rect.height * 0.48),
            control1: CGPoint(x: rect.width * 0.28, y: rect.height * 0.12),
            control2: CGPoint(x: rect.width * 0.66, y: rect.height * 0.68)
        )
        path.move(to: CGPoint(x: rect.width * 0.22, y: -20))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.78, y: rect.height + 40),
            control1: CGPoint(x: rect.width * 0.10, y: rect.height * 0.38),
            control2: CGPoint(x: rect.width * 0.94, y: rect.height * 0.62)
        )
        return path
    }
}

private struct MapListMockSearchBar: View {
    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .bold))
            Text("search places, people, or vibes")
                .font(WanderTypography.label)
                .foregroundStyle(WanderTheme.textMuted.color)
            Spacer()
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .bold))
        }
        .foregroundStyle(WanderTheme.textInk.color)
        .padding(.horizontal, WanderTheme.spacing4)
        .frame(height: 50)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 5)
    }
}

private struct MapListMockPlaceCard: View {
    let highlightListAction: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.07, blue: 0.05),
                    WanderTheme.terracottaDark.color
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 118, weight: .thin))
                    .foregroundStyle(Color.white.opacity(0.12))
                    .padding(.trailing, 74)
                    .padding(.bottom, 12)
            }
            .overlay {
                LinearGradient(
                    colors: [Color.black.opacity(0.08), Color.black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Bestia")
                        .font(WanderTypography.editorialTitle)
                    Text("Italian restaurant")
                        .font(WanderTypography.metadata)
                        .foregroundStyle(Color.white.opacity(0.86))
                    HStack(spacing: 6) {
                        Text("4.7")
                            .fontWeight(.bold)
                        Image(systemName: "star.fill")
                            .foregroundStyle(Color.yellow)
                        Text("· 1.2 mi")
                    }
                    .font(WanderTypography.label)

                    Spacer()

                    Label("2 lists", systemImage: "rectangle.stack.fill")
                        .font(WanderTypography.metadata)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.32))
                        .clipShape(Capsule())
                }
                .foregroundStyle(Color.white)
                .padding(18)
                .padding(.trailing, 64)
            }

            VStack(spacing: 4) {
                MapListCardActionButton(systemName: "bookmark.fill")
                MapListCardActionButton(
                    systemName: "rectangle.stack.badge.plus",
                    badge: "2",
                    isHighlighted: highlightListAction
                )
                MapListCardActionButton(systemName: "square.and.arrow.up")
            }
            .padding(14)
        }
        .frame(height: 232)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 18, y: 10)
    }
}

private struct MapListCardActionButton: View {
    let systemName: String
    var badge: String? = nil
    var isHighlighted = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .black))
                .frame(width: 44, height: 44)
                .foregroundStyle(Color.white)
                .background(isHighlighted ? WanderTheme.terracotta.color.opacity(0.84) : Color.black.opacity(0.34))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.white.opacity(isHighlighted ? 0.72 : 0.30), lineWidth: 1)
                }

            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(minWidth: 17, minHeight: 17)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Circle())
                    .offset(x: 5, y: -5)
            }
        }
        .frame(width: 44, height: 44)
    }
}

private struct MapListMockTabBar: View {
    var body: some View {
        HStack {
            tab(title: "Map", systemImage: "map.fill", isSelected: true)
            tab(title: "Lists", systemImage: "rectangle.stack", isSelected: false)
            tab(title: "Feed", systemImage: "bubble.left.and.bubble.right", isSelected: false)
            tab(title: "Profile", systemImage: "person.crop.circle", isSelected: false)
        }
        .padding(.horizontal, WanderTheme.spacing2)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, 22)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func tab(title: String, systemImage: String, isSelected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
            Text(title)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(isSelected ? WanderTheme.terracotta.color : WanderTheme.textMuted.color)
        .frame(maxWidth: .infinity, minHeight: 42)
    }
}

private struct MapListProfileCircleButton: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .bold))
            .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
            .foregroundStyle(WanderTheme.terracotta.color)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }
}

private struct MapListProfileAction: View {
    let title: String
    let systemImage: String
    var isListAction = false

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
            Text(title)
                .font(WanderTypography.label)
        }
        .frame(minHeight: WanderTheme.tapMinimum)
        .padding(.horizontal, WanderTheme.spacing3)
        .foregroundStyle(isListAction ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
        .background(isListAction ? WanderTheme.terracotta.color : WanderTheme.surfaceRaised.color)
        .clipShape(Capsule())
        .overlay {
            if !isListAction {
                Capsule().stroke(WanderTheme.borderHairline.color)
            }
        }
    }
}

private struct MapListMockChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(WanderTypography.metadata)
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 36)
            .foregroundStyle(WanderTheme.textInk.color)
            .background(WanderTheme.terracottaTint.color)
            .clipShape(Capsule())
    }
}

private struct MapListProfileSaveButton: View {
    let title: String
    let systemImage: String
    let isPrimary: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(size: 15, weight: .bold))
        .frame(maxWidth: .infinity, minHeight: 60)
        .foregroundStyle(isPrimary ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
        .background(isPrimary ? WanderTheme.textInk.color : WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isPrimary ? Color.clear : WanderTheme.borderHairline.color)
        }
    }
}
#endif
