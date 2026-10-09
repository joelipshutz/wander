import SwiftUI

private struct ReviewReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var reviewReduceMotion: Bool {
        get { self[ReviewReduceMotionKey.self] }
        set { self[ReviewReduceMotionKey.self] = newValue }
    }
}

@main
struct AstirLiveReviewApp: App {
    @StateObject private var store = ReviewStore()
    var body: some Scene { WindowGroup { ReviewRoot().environmentObject(store).modifier(ReviewLaunchOverrides()) } }
}

private struct ReviewLaunchOverrides: ViewModifier {
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    func body(content: Content) -> some View {
        let arguments = ProcessInfo.processInfo.arguments
        content.environment(\.dynamicTypeSize, arguments.contains("--large-text") ? .accessibility2 : systemTypeSize)
            .environment(\.reviewReduceMotion, arguments.contains("--reduce-motion"))
            .preferredColorScheme(arguments.contains("--dark") ? .dark : arguments.contains("--light") ? .light : nil)
    }
}

struct ReviewRoot: View {
    @EnvironmentObject private var store: ReviewStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reviewReduceMotion) private var reviewReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || reviewReduceMotion }
    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()
            switch store.tab {
            case .live: LiveView()
            case .lists: ListsView()
            case .profile: ProfileView()
            }
        }
        .font(Ink.body()).foregroundStyle(Ink.text).tint(Ink.accentText)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !(store.tab == .live && store.drawer == .peek) && !(store.tab == .profile && store.showYourMap) { navigation }
        }
        .sheet(item: $store.sheet) { sheet in
            switch sheet {
            case .filters: FiltersView()
            case .detail(let activity): ActivityDetail(activity: activity)
            case .plan(let activity): PlanComposer(activity: activity)
            case .reply(let activity): ReplyComposer(activity: activity)
            case .add: AddComposer()
            case .inbox: InboxView()
            case .guide: GuideView()
            case .events: EventsView()
            }
        }
        .overlay(alignment: .top) {
            if let banner = store.banner {
                HStack(alignment: .top) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Ink.accentText)
                    Text(banner).font(Ink.body(14, weight: "Medium"))
                    Button { store.banner = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Dismiss confirmation")
                }.padding(.leading, 16).padding(.vertical, 8).background(Ink.surface, in: RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.15), radius: 18, y: 5).padding(12)
                    .onTapGesture { store.banner = nil }
                    .accessibilityElement(children: .contain)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: store.drawer)
    }
    private var navigation: some View {
        HStack(spacing: 2) {
            ForEach(ReviewTab.allCases, id: \.self) { tab in
                Button { store.selectTab(tab) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab == .live ? "map" : tab == .lists ? "rectangle.stack" : "person.crop.circle")
                            .font(.system(size: 20, weight: store.tab == tab ? .semibold : .regular))
                        Text(tab.rawValue).font(Ink.body(12, weight: store.tab == tab ? "DemiBold" : "Regular", relativeTo: .caption))
                        Capsule().fill(store.tab == tab ? Ink.coral : .clear).frame(width: 24, height: 2)
                    }.frame(maxWidth: .infinity).frame(minHeight: 58)
                        .foregroundStyle(store.tab == tab ? Ink.text : Ink.text.opacity(0.6))
                }.accessibilityAddTraits(store.tab == tab ? .isSelected : [])
                    .accessibilityIdentifier("tab.\(tab.rawValue.lowercased())")
            }
        }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 4)
            .background(Ink.canvas.shadow(color: .black.opacity(0.06), radius: 12, y: -3))
    }
}
