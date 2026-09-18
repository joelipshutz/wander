import SwiftUI

@main struct FeedActivityMockApp: App {
    var body: some Scene { WindowGroup { ScenarioGallery() } }
}

struct ScenarioGallery: View {
    @State private var scenario: Scenario = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--scenario"), args.indices.contains(i + 1),
              let number = Int(args[i + 1]), let scenario = Scenario(rawValue: number) else { return .together }
        return scenario
    }()
    @State private var dark = !ProcessInfo.processInfo.arguments.contains("--light")
    @StateObject private var auth = AuthSessionStore()
    @StateObject private var navigation = ActivityNavigationCoordinator()
    @State private var selectedList: LocalPlaceList?
    private var brand: MockBrandMode { MockBrandMode(dark: dark) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("ASTIR").font(.system(size: 25, weight: .medium, design: .serif)).tracking(5)
                Spacer()
                Text("ACTIVITY PREVIEW").font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                Button { dark.toggle() } label: {
                    Image(systemName: dark ? "sun.max" : "moon").frame(width: 44, height: 44)
                }.accessibilityLabel("Toggle appearance")
            }.padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(Scenario.allCases) { item in
                        Button { scenario = item } label: {
                            VStack(spacing: 9) {
                                Text(item.title).font(AstirTypography.label)
                                Rectangle().fill(scenario == item ? brand.accentText : .clear).frame(height: 2)
                            }.frame(minHeight: 44)
                        }.foregroundStyle(scenario == item ? brand.accentText : brand.secondaryText)
                    }
                }.padding(.horizontal, 20)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(scenario.heading).font(.system(.title2, design: .serif).weight(.semibold))
                        Text(scenario.explanation).font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                    }.padding(.top, 16)
                    ForEach(scenario.groups) { group in
                        MockPostcard(group: group, compact: scenario.groups.count > 1, openList: { selectedList = $0 })
                    }
                    Text("Illustrative place artwork · sample activity\nTap View activity to expand; tap again to collapse.")
                        .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                        .padding(.bottom, 20)
                }.padding(.horizontal, 20).id(scenario)
            }
        }
        .background(brand.background.ignoresSafeArea())
        .foregroundStyle(brand.primaryText)
        .environment(\.astirBrandMode, brand)
        .environmentObject(auth)
        .environmentObject(navigation)
        .preferredColorScheme(dark ? .dark : .light)
        .sheet(item: $selectedList) { list in
            NavigationStack {
                VStack(spacing: 20) {
                    Image(systemName: "list.bullet").font(.largeTitle)
                    Text(list.name).font(.system(.title, design: .serif))
                    Text("Laurel Supply").font(AstirTypography.bodySmall)
                    Text("Sample list destination").font(AstirTypography.caption).foregroundStyle(.secondary)
                }.navigationTitle("List preview").toolbar { Button("Done") { selectedList = nil } }
            }.presentationDetents([.medium])
        }
        .sheet(item: $navigation.selectedEvent) { event in
            NavigationStack {
                VStack(spacing: 16) {
                    Text("\(event.actor) · \(event.label)").font(.system(.title2, design: .serif))
                    Text("Laurel Supply")
                    Text(event.occurredAt.formatted(date: .abbreviated, time: .standard))
                    Text("This row opens its original post and comments.\nExisting conversations remain separate.")
                        .font(AstirTypography.bodySmall).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding().navigationTitle("Original post")
                    .toolbar { Button("Done") { navigation.selectedEvent = nil } }
            }.presentationDetents([.medium])
        }
    }
}

private struct MockPostcard: View {
    @Environment(\.astirBrandMode) private var brand
    let group: FeedActivityGroup
    let compact: Bool
    let openList: (LocalPlaceList) -> Void
    private var event: FeedActivity { group.primaryActivity }
    private var actorLine: String {
        switch event.kind {
        case .placeBeen: "\(event.actor) checked in"
        case .placeWannaGo: "\(event.actor) added to Wanna"
        default: "\(event.actor) added this to a list"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StorefrontArtwork().frame(height: compact ? 85 : 125).clipped()
                .overlay(alignment: .topLeading) {
                    Label(event.label.uppercased(), systemImage: event.kind == .placeBeen ? "checkmark" : event.kind == .placeWannaGo ? "plus" : "list.bullet")
                        .font(AstirTypography.label).padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(Color(hex: 0x141714)).background(Color(hex: 0xF2E9DB), in: Capsule())
                        .padding(12)
                }
            VStack(alignment: .leading, spacing: compact ? 10 : 14) {
                Text("Laurel Supply").font(.system(size: compact ? 25 : 30, weight: .semibold, design: .serif))
                Text("Grocery store · West Hollywood · CA")
                    .font(AstirTypography.metadata).foregroundStyle(brand.secondaryText)
                HStack(spacing: 10) {
                    Text(String(event.actor.prefix(1))).font(AstirTypography.label)
                        .frame(width: 32, height: 32).background(brand.primaryText.opacity(0.10), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(actorLine).font(AstirTypography.bodySmall)
                        Text(event.occurredAt.formatted(date: .omitted, time: .shortened) + " · someone you follow")
                            .font(AstirTypography.metadata).foregroundStyle(brand.secondaryText)
                    }
                }
                if group.activities.count > 1 {
                    FeedActivityDisclosure(group: group, openList: openList)
                } else if let list = event.list {
                    Text(list.name).font(AstirTypography.bodySmall)
                }
                Divider().overlay(brand.primaryText.opacity(0.15))
                HStack(spacing: 19) {
                    Image(systemName: "heart")
                    Text("0").font(AstirTypography.caption)
                    Image(systemName: "bubble")
                    Text("0").font(AstirTypography.caption)
                    Image(systemName: "paperplane")
                    Spacer()
                    Image(systemName: "bookmark")
                }.font(.system(size: 21)).frame(height: 30).accessibilityHidden(true)
            }.padding(compact ? 16 : 18)
        }
        .background(brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(brand.primaryText.opacity(0.24), lineWidth: 1))
    }
}

// Native vector placeholder, deliberately not a photograph of the actual shop.
private struct StorefrontArtwork: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: 0xA6B5A7)
                HStack(spacing: 7) {
                    ForEach(0..<5) { _ in
                        Rectangle().fill(Color(hex: 0x294E4B)).overlay(alignment: .topLeading) {
                            Rectangle().fill(.white.opacity(0.12)).frame(width: 12).rotationEffect(.degrees(25))
                        }
                    }
                }.padding(.top, 33).padding(.horizontal, 16)
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Text("LAUREL SUPPLY").font(.system(size: 14, weight: .semibold, design: .serif)).tracking(2)
                        Spacer()
                    }.frame(height: 30).background(Color(hex: 0xD2B88F))
                    Spacer()
                    Rectangle().fill(Color(hex: 0xD2B88F)).frame(height: 9)
                }
                Image(systemName: "leaf.fill").font(.system(size: 68)).rotationEffect(.degrees(-24))
                    .foregroundStyle(Color(hex: 0x729077)).position(x: geo.size.width - 22, y: geo.size.height - 30)
            }
        }.accessibilityLabel("Illustrative storefront")
    }
}

#Preview { ScenarioGallery() }
