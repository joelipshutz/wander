#if DEBUG
import SwiftUI

enum DiscoverPeopleModulesMockupPage: String, CaseIterable {
    case populated
    case following

    static func resolved(from arguments: [String] = ProcessInfo.processInfo.arguments) -> DiscoverPeopleModulesMockupPage? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderDiscoverPeopleModulesMockup") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .populated
        }

        return DiscoverPeopleModulesMockupPage(rawValue: arguments[valueIndex]) ?? .populated
    }
}

struct DiscoverPeopleModulesMockupRoot: View {
    let page: DiscoverPeopleModulesMockupPage
    @State private var selectedTab = WanderTab.discover

    var body: some View {
        TabView(selection: $selectedTab) {
            mockTab(systemImage: WanderTab.map.systemImage, title: WanderTab.map.title)
                .tag(WanderTab.map)

            DiscoverPeopleModulesMockup(page: page)
                .tabItem { Label(WanderTab.discover.title, systemImage: WanderTab.discover.systemImage) }
                .tag(WanderTab.discover)

            mockTab(systemImage: WanderTab.add.systemImage, title: WanderTab.add.title)
                .tag(WanderTab.add)

            mockTab(systemImage: WanderTab.lists.systemImage, title: WanderTab.lists.title)
                .tag(WanderTab.lists)

            mockTab(systemImage: WanderTab.profile.systemImage, title: WanderTab.profile.title)
                .tag(WanderTab.profile)
        }
        .tint(WanderTheme.terracotta.color)
        .preferredColorScheme(.light)
    }

    private func mockTab(systemImage: String, title: String) -> some View {
        WanderTheme.canvasWarm.color
            .ignoresSafeArea()
            .tabItem { Label(title, systemImage: systemImage) }
    }
}

private struct DiscoverPeopleModulesMockup: View {
    let page: DiscoverPeopleModulesMockupPage
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                modeTabs
                searchField

                DiscoverPeopleMockupShelf(
                    title: "People you may know",
                    subtitle: "From contacts and people you follow",
                    people: DiscoverPeopleMockupData.network,
                    followingIDs: page == .following ? Set(["maya"]) : []
                )

                DiscoverPeopleMockupShelf(
                    title: "People worth following",
                    subtitle: "Popular public accounts in your city",
                    location: "Los Angeles",
                    people: DiscoverPeopleMockupData.local,
                    followingIDs: []
                )
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing1)
            .padding(.bottom, WanderTheme.spacing8)
        }
        .scrollIndicators(.hidden)
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
        .foregroundStyle(WanderTheme.textInk.color)
    }

    private var modeTabs: some View {
        HStack(spacing: 0) {
            DiscoverPeopleMockupModeTab(title: "Places", systemImage: "storefront", isSelected: false)
            DiscoverPeopleMockupModeTab(title: "People", systemImage: "person.2", isSelected: true)
        }
        .padding(.top, WanderTheme.spacing1)
    }

    private var searchField: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            TextField("Search name or @handle", text: $query)
                .font(.system(size: 17, weight: .bold))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .frame(minHeight: 54)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
        .accessibilityLabel("Search people")
    }
}

private struct DiscoverPeopleMockupModeTab: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        Button(action: {}) {
            VStack(spacing: WanderTheme.spacing2) {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .black))
                    Text(title)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                }
                .foregroundStyle(isSelected ? WanderTheme.textInk.color : WanderTheme.textMuted.color)
                .frame(maxWidth: .infinity, minHeight: 42)

                Rectangle()
                    .fill(isSelected ? WanderTheme.textInk.color : Color.clear)
                    .frame(height: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct DiscoverPeopleMockupShelf: View {
    let title: String
    let subtitle: String
    var location: String?
    let people: [DiscoverPeopleMockupPerson]
    let followingIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .top, spacing: WanderTheme.spacing2) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(title)
                        .font(.system(size: 18, weight: .black, design: .rounded))

                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: WanderTheme.spacing2)

                if let location {
                    Label(location, systemImage: "location.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .padding(.horizontal, WanderTheme.spacing2)
                        .frame(minHeight: 28)
                        .background(WanderTheme.terracottaTint.color)
                        .clipShape(Capsule())
                        .lineLimit(1)
                } else {
                    Button("See all", action: {})
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .frame(minHeight: WanderTheme.tapMinimum)
                        .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: WanderTheme.spacing3) {
                    ForEach(people) { person in
                        DiscoverPeopleMockupCard(
                            person: person,
                            isFollowing: followingIDs.contains(person.id)
                        )
                    }
                }
                .padding(.vertical, WanderTheme.spacing1)
            }
        }
    }
}

private struct DiscoverPeopleMockupCard: View {
    let person: DiscoverPeopleMockupPerson
    let isFollowing: Bool

    var body: some View {
        VStack(spacing: 6) {
            Button(action: {}) {
                VStack(spacing: 5) {
                    WanderAvatar(
                        initials: person.initials,
                        size: 48,
                        color: person.color
                    )

                    Text(person.name)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)

                    Text("@\(person.handle)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Label(person.reason, systemImage: person.reasonIcon)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(person.reasonColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, WanderTheme.spacing2)
                .frame(minHeight: 23)
                .background(person.reasonBackground)
                .clipShape(Capsule())

            Text(person.bio)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 28, alignment: .top)

            Spacer(minLength: 0)

            Button(action: {}) {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.system(size: 13, weight: .black))
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isFollowing ? WanderTheme.textInk.color : WanderTheme.textOnAction.color)
            .background(isFollowing ? WanderTheme.surfaceSand.color : WanderTheme.terracotta.color)
            .clipShape(Capsule())
            .accessibilityLabel(isFollowing ? "Following \(person.name)" : "Follow \(person.name)")
        }
        .padding(10)
        .frame(width: 166, height: 220)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct DiscoverPeopleMockupPerson: Identifiable {
    enum Source {
        case network
        case local
    }

    let id: String
    let name: String
    let handle: String
    let initials: String
    let reason: String
    let bio: String
    let color: Color
    let source: Source

    var reasonIcon: String {
        switch source {
        case .network: "person.2.fill"
        case .local: "sparkles"
        }
    }

    var reasonColor: Color {
        switch source {
        case .network: WanderTheme.stateInfo.color
        case .local: WanderTheme.terracottaDark.color
        }
    }

    var reasonBackground: Color {
        switch source {
        case .network: WanderTheme.skyTint.color
        case .local: WanderTheme.terracottaTint.color
        }
    }
}

private enum DiscoverPeopleMockupData {
    static let network = [
        DiscoverPeopleMockupPerson(
            id: "maya",
            name: "Maya Chen",
            handle: "mayachen",
            initials: "MC",
            reason: "Follows you",
            bio: "Coffee, noodles, and low-key corners.",
            color: WanderTheme.avatarAndrew.color,
            source: .network
        ),
        DiscoverPeopleMockupPerson(
            id: "marcus",
            name: "Marcus Reed",
            handle: "marcusreed",
            initials: "MR",
            reason: "3 mutual follows",
            bio: "Hikes, neighborhood bars, great sandwiches.",
            color: WanderTheme.avatarRyan.color,
            source: .network
        ),
        DiscoverPeopleMockupPerson(
            id: "priya",
            name: "Priya Shah",
            handle: "priyapicks",
            initials: "PS",
            reason: "In your contacts",
            bio: "Design-friendly cafes and vegetarian spots.",
            color: WanderTheme.avatarSofia.color,
            source: .network
        )
    ]

    static let local = [
        DiscoverPeopleMockupPerson(
            id: "elena",
            name: "Elena Torres",
            handle: "elenaeatsla",
            initials: "ET",
            reason: "Popular in Silver Lake",
            bio: "Eastside dinners, bakeries, and patios.",
            color: WanderTheme.avatarJames.color,
            source: .local
        ),
        DiscoverPeopleMockupPerson(
            id: "theo",
            name: "Theo Brooks",
            handle: "theobrooks",
            initials: "TB",
            reason: "Popular in Mar Vista",
            bio: "Tacos, pizza, sake, and late-night spots.",
            color: WanderTheme.categoryMoss.color,
            source: .local
        ),
        DiscoverPeopleMockupPerson(
            id: "samira",
            name: "Samira Patel",
            handle: "samirapatel",
            initials: "SP",
            reason: "Popular in West Hollywood",
            bio: "Dessert, celebrations, and worth-the-drive picks.",
            color: WanderTheme.pinSocial.color,
            source: .local
        )
    ]
}
#endif
