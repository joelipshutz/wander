import SwiftUI
import MapKit

struct LiveView: View {
    @EnvironmentObject private var store: ReviewStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reviewReduceMotion) private var reviewReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || reviewReduceMotion }
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draggingArea = false
    @State private var feedOffset: CGFloat = 0
    @State private var dragStartOffset: CGFloat?
    @FocusState private var searchFocused: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                map(topInset: store.drawer == .full ? 0 : min(store.drawing ? 240 : 190, max(0, geometry.size.height - drawerSize(in: geometry.size.height) - 100)), bottomInset: drawerSize(in: geometry.size.height)).ignoresSafeArea(edges: .top)
                if store.drawer != .full {
                    VStack(alignment: .leading, spacing: 12) {
                        masthead
                        if store.drawing { areaEditor }
                        else {
                            searchField
                            mapControls
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 20).padding(.top, 10)
                }
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    drawer(height: drawerSize(in: geometry.size.height))
                }
            }.clipped()
        }
    }

    private func map(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        MapReader { proxy in
            Map(position: $store.camera, interactionModes: store.drawing ? [] : .all) {
                ForEach(store.filtered) { activity in
                    Annotation(activity.place, coordinate: activity.coordinate, anchor: .bottom) {
                        Button { store.sheet = .detail(activity) } label: {
                            VStack(spacing: 0) {
                                HStack(spacing: 5) {
                                    Text(activity.initials).font(Ink.body(11, weight: "DemiBold"))
                                    Image(systemName: activity.kind.symbol).font(.system(size: 10, weight: .bold))
                                    Text(activity.timeLabel).font(Ink.body(9, weight: "Medium", relativeTo: .caption2)).lineLimit(1)
                                }.padding(.horizontal, 10).frame(minHeight: 38)
                                    .background(activity.isOwn ? Ink.coral : Ink.canvas, in: Capsule())
                                    .overlay(Capsule().stroke(Ink.text.opacity(0.2), lineWidth: 1))
                                Image(systemName: "triangle.fill").font(.system(size: 8)).rotationEffect(.degrees(180)).offset(y: -2)
                                    .foregroundStyle(activity.isOwn ? Ink.coral : Ink.canvas)
                            }.foregroundStyle(activity.isOwn ? Ink.black : Ink.text)
                                .frame(minWidth: 44, minHeight: 46)
                                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(activity.person) \(activity.kind.verb) \(activity.place), \(activity.timeLabel)")
                            .accessibilityIdentifier("map.activity.\(activity.place)")
                    }.annotationTitles(.hidden)
                }
                if let area = store.drawing ? store.draftArea : store.area {
                    MapCircle(center: area.center, radius: area.radius)
                        .foregroundStyle(Ink.coral.opacity(0.15)).stroke(Ink.coral, lineWidth: 2)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls { MapCompass() }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: topInset)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: bottomInset)
            }
            .onMapCameraChange { store.viewportCenter = $0.region.center }
            .overlay {
                if store.drawing {
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                guard let center = proxy.convert(value.startLocation, from: .local),
                                      let edge = proxy.convert(value.location, from: .local) else { return }
                                if !draggingArea { draggingArea = true; store.draftArea = GeographicArea(center: center, radius: 250) }
                                let radius = CLLocation(latitude: center.latitude, longitude: center.longitude)
                                    .distance(from: CLLocation(latitude: edge.latitude, longitude: edge.longitude))
                                store.draftArea = GeographicArea(center: center, radius: min(25_000, max(100, radius)))
                            }
                            .onEnded { _ in draggingArea = false })
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var masthead: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ASTIR").font(Ink.body(23, weight: "DemiBold")).tracking(3)
                Text("OCEAN PARK").font(Ink.body(9, weight: "Medium", relativeTo: .caption2)).tracking(2.4)
            }.padding(.horizontal, 15).padding(.vertical, 10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            Spacer()
            AddPlaceButton()
            Button { store.sheet = .inbox } label: {
                Image(systemName: store.replies.isEmpty ? "tray" : "tray.fill").font(.system(size: 19)).frame(width: 46, height: 46).background(.regularMaterial, in: Circle())
            }.accessibilityLabel("Demo inbox, \(store.replies.count) replies")
            ReviewMenu()
        }
    }
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Ink.muted)
            TextField("Places, people, a feeling…", text: $store.query).font(Ink.body(15))
                .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                .accessibilityIdentifier("live.search")
            if !store.query.isEmpty { Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }.accessibilityLabel("Clear search") }
        }.padding(.horizontal, 15).frame(minHeight: 52).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    private var mapControls: some View {
        HStack(spacing: 8) {
            Button {
                searchFocused = false; store.drawer = .peek; store.drawing = true
                store.draftArea = store.area ?? GeographicArea(center: store.viewportCenter, radius: 1000)
            } label: { Label(store.area?.label ?? "Draw area", systemImage: "pencil.and.outline") }
                .buttonStyle(GlassButton()).accessibilityIdentifier("area.open")
            Spacer(minLength: 0)
            Button { store.sheet = .filters } label: {
                Label(store.activeFilterCount == 0 ? "Filters" : "Filters · \(store.activeFilterCount)", systemImage: "slider.horizontal.3")
            }.buttonStyle(GlassButton()).accessibilityIdentifier("filters.open")
        }
    }
    private var areaEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A little closer to here").font(Ink.body(17, weight: "DemiBold"))
            Text("Drag on the map to draw a circle, or choose a radius around the map center.")
                .font(Ink.body(13)).fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach([500.0, 1000, 2500], id: \.self) { radius in
                        Button(radius < 1000 ? "500 m" : radius == 1000 ? "1 km" : "2.5 km") {
                            store.draftArea = GeographicArea(center: store.viewportCenter, radius: radius)
                        }.buttonStyle(QuietButton()).accessibilityLabel("Select \(Int(radius)) meter radius around map center")
                            .accessibilityIdentifier("area.radius.\(Int(radius))")
                    }
                }
            }
            HStack {
                Button("Cancel") { store.drawing = false; store.draftArea = nil }.frame(minHeight: 44)
                if store.area != nil {
                    Button("Clear") { store.area = nil; store.draftArea = nil; store.drawing = false }.frame(minHeight: 44)
                }
                Spacer()
                Button("Apply \(store.draftArea?.label ?? "area")") {
                    store.area = store.draftArea; store.drawing = false; store.drawer = .half
                }.font(Ink.body(14, weight: "DemiBold")).frame(minHeight: 44).disabled(store.draftArea == nil)
                    .accessibilityIdentifier("area.apply")
            }
        }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    private func drawerSize(in available: CGFloat) -> CGFloat {
        switch store.drawer {
        case .peek: typeSize.isAccessibilitySize ? min(available * 0.55, 320) : min(available * 0.35, store.fromProfile ? 215 : 170)
        case .half: available * (typeSize.isAccessibilitySize ? 0.77 : 0.54)
        case .full: available - 8
        }
    }
    private func drawer(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Capsule().fill(Ink.text.opacity(0.24)).frame(width: 34, height: 4).padding(.top, 9)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.scope == .yours ? "Your places" : "Live").font(Ink.title(27))
                        Text(store.scenario == .offline ? "Offline · saved activity" : "\(store.filtered.count) place \(store.filtered.count == 1 ? "memory" : "memories") · \(store.scope == .following ? "your people" : store.scope == .yours ? "all yours" : "near Ocean Park")")
                            .font(Ink.body(11, relativeTo: .caption)).foregroundStyle(Ink.muted)
                    }
                    Spacer(minLength: 5)
                    Menu {
                        ForEach(DrawerHeight.allCases, id: \.self) { height in
                            Button(height == .peek ? "Expand map" : height == .half ? "Map + activity" : "Expand activity") {
                                setDrawer(height)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.and.down").font(.system(size: 15, weight: .medium)).frame(width: 44, height: 44)
                            .background(Ink.text.opacity(0.05), in: Circle())
                    }.disabled(store.drawing)
                        .accessibilityLabel(store.drawing ? "Finish or cancel drawing before changing the activity view" : "Change map and activity view")
                        .accessibilityIdentifier("drawer.positions")
                    if store.drawer == .full { AddPlaceButton(); ReviewMenu() }
                    else {
                        Button { setDrawer(.full) } label: {
                            Image(systemName: "chevron.up").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44)
                        }.disabled(store.drawing)
                            .accessibilityLabel(store.drawing ? "Finish or cancel drawing before expanding activity" : "Expand activity feed")
                            .accessibilityIdentifier("drawer.expand")
                    }
                }.padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 8)
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 22).onEnded { value in
                if value.translation.height < -30 { setDrawer(store.drawer == .peek ? .half : .full) }
                if value.translation.height > 30 { setDrawer(store.drawer == .full ? .half : .peek) }
            })
            if store.fromProfile {
                Button { store.backToProfile() } label: { Label("Back to Profile", systemImage: "arrow.left").font(Ink.body(13, weight: "DemiBold")).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44) }
                    .padding(.horizontal, 22).accessibilityIdentifier("profile.return")
            }
            if store.drawer == .peek {
                Button { setDrawer(.half) } label: {
                    HStack { Text(store.filtered.first.map { "\($0.person) \($0.kind.verb) \($0.place)" } ?? "No places in this view").lineLimit(2); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(Ink.body(13)).padding(.horizontal, 22).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }.disabled(store.drawing)
                    .accessibilityLabel(store.drawing ? "Finish or cancel drawing before showing activity" : "Show activity beside the map")
                Spacer(minLength: 0)
            } else {
                scopeRail
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        GeometryReader { geometry in
                            Color.clear.preference(key: FeedOffsetPreference.self, value: geometry.frame(in: .named("activityScroll")).minY)
                        }.frame(height: 0)
                        if store.drawer == .full {
                            HStack { searchField; Button { store.sheet = .filters } label: { Image(systemName: "slider.horizontal.3").frame(width: 48, height: 52).background(Ink.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 18)) }.accessibilityLabel("Filters").accessibilityIdentifier("filters.open") }
                                .padding(.top, 16)
                        }
                        HStack {
                            Text(store.filterSummary).font(Ink.body(11, relativeTo: .caption)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 5)
                            if store.activeFilterCount > 0 || !store.query.isEmpty {
                                Button("Reset") { store.resetFilters() }.font(Ink.body(12, weight: "DemiBold")).frame(minHeight: 44)
                            }
                        }.padding(.top, 12).padding(.bottom, 8)
                        if store.scenario == .offline {
                            Label("You’re seeing saved demo activity. Changes stay on this device.", systemImage: "wifi.slash")
                                .font(Ink.body(13)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Ink.text.opacity(0.05), in: RoundedRectangle(cornerRadius: 14)).padding(.bottom, 16)
                        }
                        if store.filtered.isEmpty { emptyState; if store.showTransition { transitionCard.padding(.vertical, 16) } }
                        if store.filtered.contains(where: { $0.kind != .plan }) {
                            Text("RECENT ACTIVITY").font(Ink.body(10, weight: "DemiBold", relativeTo: .caption)).tracking(1.2).foregroundStyle(Ink.muted).padding(.top, 20)
                            ForEach(store.filtered.filter { $0.kind != .plan }) { activity in
                                ActivityRow(activity: activity)
                                if activity.id == store.filtered.first(where: { $0.kind != .plan })?.id && store.showTransition {
                                    transitionCard.padding(.vertical, 16)
                                }
                            }
                        }
                        if store.filtered.contains(where: { $0.kind == .plan }) {
                            Text("UPCOMING PLANS").font(Ink.body(10, weight: "DemiBold", relativeTo: .caption)).tracking(1.2).foregroundStyle(Ink.accentText).padding(.top, 10)
                            ForEach(store.filtered.filter { $0.kind == .plan }) { activity in ActivityRow(activity: activity) }
                        }
                        Button { store.sheet = .events } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles").foregroundStyle(Ink.accentText)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Astir gatherings").font(Ink.body(15, weight: "DemiBold"))
                                    Text("Explore events · demo preview").font(Ink.body(12)).foregroundStyle(Ink.muted)
                                }
                                Spacer(); Image(systemName: "arrow.up.right")
                            }.padding(16).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                                .background(Ink.surface, in: RoundedRectangle(cornerRadius: 19))
                        }.buttonStyle(.plain).padding(.vertical, 18).accessibilityIdentifier("events.open")
                        DemoNote().padding(.vertical, 22)
                    }.padding(.horizontal, 22).padding(.bottom, store.drawer == .full ? 68 : 16)
                }.coordinateSpace(name: "activityScroll")
                    .onPreferenceChange(FeedOffsetPreference.self) { feedOffset = $0 }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollDisabled(store.drawer == .half)
                    .highPriorityGesture(DragGesture(minimumDistance: 12).onEnded { value in
                        guard store.drawer == .half,
                              abs(value.translation.height) > abs(value.translation.width),
                              value.translation.height < -24 else { return }
                        setDrawer(.full)
                    }, including: store.drawer == .half ? .all : .none)
                    .simultaneousGesture(DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            if dragStartOffset == nil { dragStartOffset = feedOffset }
                        }
                        .onEnded { value in
                            defer { dragStartOffset = nil }
                            guard abs(value.translation.height) > abs(value.translation.width) else { return }
                            // Keep hit targets stationary until the finger lifts. Changing
                            // detents during the drag could activate a moved row on release.
                            if store.drawer == .full && (dragStartOffset ?? -100) >= -2 && value.translation.height > 80 {
                                setDrawer(.half)
                            }
                        }, including: store.drawer == .full ? .all : .none)
                    .accessibilityIdentifier("live.activityScroll")
                    .overlay(alignment: .bottom) {
                        if store.drawer == .full {
                            Button { setDrawer(.peek) } label: { Label("Map", systemImage: "map.fill") }
                                .buttonStyle(GlassButton()).padding(.bottom, 14).accessibilityIdentifier("feed.map")
                        }
                    }
            }
        }.frame(height: height).frame(maxWidth: .infinity)
            .background(Ink.canvas, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
            .shadow(color: .black.opacity(0.13), radius: 16, y: -4)
    }
    private var scopeRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(PeopleScope.allCases) { scope in
                    Button { store.scope = scope; store.time = scope == .yours ? .all : .week } label: {
                        VStack(spacing: 7) {
                            Text(scope.rawValue).font(Ink.body(14, weight: store.scope == scope ? "DemiBold" : "Regular"))
                                .foregroundStyle(store.scope == scope ? Ink.text : Ink.text.opacity(0.58))
                            Rectangle().fill(store.scope == scope ? Ink.coral : .clear).frame(height: 2)
                        }.frame(minHeight: 44)
                    }.accessibilityAddTraits(store.scope == scope ? .isSelected : []).accessibilityIdentifier("scope.\(scope.id)")
                }
            }.padding(.horizontal, 22)
        }.overlay(alignment: .bottom) { Rectangle().fill(Ink.text.opacity(0.08)).frame(height: 0.5) }
    }
    private var transitionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A NEW VIEW OF YOUR FEED").font(Ink.body(9, weight: "DemiBold", relativeTo: .caption2)).tracking(1.1).foregroundStyle(Ink.accentText)
            EditorialTitle(text: "Your Feed now has a map.", size: 25)
            Text("Explore your people’s recent activity. Your Map is still in Profile.").font(Ink.body(14))
            HStack {
                Button("Show me") { store.dismissTransition(); store.sheet = .guide }.buttonStyle(QuietButton())
                Button("Not now") { store.dismissTransition() }.font(Ink.body(13)).frame(minHeight: 44).padding(.horizontal, 8)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 20))
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "map").font(.system(size: 30)).foregroundStyle(Ink.accentText)
            EditorialTitle(text: store.scenario == .empty ? "A little quiet here" : "Nothing in this view", size: 27)
            Text(store.scenario == .empty ? "Your next place memory can start the conversation." : "Try a wider area, a different time, or another group of people.").font(Ink.body(14)).foregroundStyle(Ink.muted)
            Button(store.scenario == .empty ? "Add a place" : "Clear filters") {
                if store.scenario == .empty { store.sheet = .add } else { store.resetFilters() }
            }.buttonStyle(QuietButton())
        }.padding(.vertical, 24)
    }
    private func setDrawer(_ height: DrawerHeight) {
        searchFocused = false
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { store.changeDrawer(to: height) }
    }
}

private struct FeedOffsetPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ActivityRow: View {
    @EnvironmentObject private var store: ReviewStore
    let activity: Activity
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button { store.sheet = .detail(activity) } label: {
                HStack(alignment: .top, spacing: 12) {
                    Avatar(initials: activity.initials)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) { Text(activity.person).font(Ink.body(15, weight: "DemiBold")); Spacer(); Text(activity.timeLabel).font(Ink.body(11, relativeTo: .caption)).foregroundStyle(Ink.muted) }
                        Text(activity.kind.verb).font(Ink.body(12)).foregroundStyle(Ink.muted)
                        Text(activity.place).font(Ink.title(23)).padding(.top, 2)
                        Text("\(activity.neighborhood) · \(activity.category)").font(Ink.body(12)).foregroundStyle(Ink.muted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("activity.open.\(activity.place)")
            Text(activity.note).font(Ink.body(14)).fixedSize(horizontal: false, vertical: true).padding(.leading, 54)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }.padding(.leading, 54)
        }.padding(.vertical, 19)
            .overlay(alignment: .bottom) { Rectangle().fill(Ink.text.opacity(0.12)).frame(height: 0.5) }
    }
    @ViewBuilder private var actions: some View {
        if activity.kind == .wanna {
            Button { store.sheet = .plan(activity) } label: { Label("Make a plan", systemImage: "calendar.badge.plus") }.buttonStyle(QuietButton())
        }
        if !activity.isOwn {
            Button { store.sheet = .reply(activity) } label: { Label("Reply", systemImage: "bubble.left") }.buttonStyle(QuietButton())
        }
    }
}
