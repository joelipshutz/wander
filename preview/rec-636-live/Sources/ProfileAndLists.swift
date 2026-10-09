import SwiftUI
import MapKit

struct ProfileView: View {
    @EnvironmentObject private var store: ReviewStore
    var body: some View {
        Group {
            if store.showYourMap { YourMapView() }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack { EditorialTitle(text: "Profile", size: 36); Spacer(); AddPlaceButton(); ReviewMenu() }
                        identity
                        social
                        streak
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { EditorialTitle(text: "Recent activity", size: 25); Spacer(); Text("Check-ins / Wanna").font(Ink.body(11)).foregroundStyle(Ink.muted) }
                            ForEach(store.ownPlaces.prefix(2)) { activity in
                                Button { store.sheet = .detail(activity) } label: {
                                    HStack(spacing: 13) {
                                        Image(systemName: activity.kind.symbol).foregroundStyle(Ink.accentText).frame(width: 26)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(activity.place).font(Ink.body(16, weight: "DemiBold"))
                                            Text("\(activity.kind.rawValue) · \(activity.timeLabel)").font(Ink.body(12)).foregroundStyle(Ink.muted)
                                        }
                                        Spacer(); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Ink.muted)
                                    }.frame(minHeight: 65).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                        yourMapCard
                        calendar
                        DemoNote(text: "Profile continuity review: fictional identity, social counts, streak, place history, and calendar. Your Map and its Patterns stay here.")
                    }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 28)
                }
            }
        }.background(Ink.canvas).clipped()
    }
    private var identity: some View {
        HStack(alignment: .center, spacing: 17) {
            Avatar(initials: "AL", size: 76)
            VStack(alignment: .leading, spacing: 5) {
                Text("Avery Lane").font(Ink.body(23, weight: "DemiBold"))
                Text("@avery · Ocean Park").font(Ink.body(13)).foregroundStyle(Ink.muted)
                Text("Always taking the long way home.").font(Ink.body(14)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var social: some View {
        HStack(spacing: 0) { stat("3", "friends"); stat("8", "followers"); stat("4", "following") }
            .padding(.vertical, 8)
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) { Text(value).font(Ink.body(22, weight: "DemiBold")); Text(label).font(Ink.body(12)).foregroundStyle(Ink.muted) }.frame(maxWidth: .infinity)
    }
    private var streak: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame").font(.system(size: 23)).foregroundStyle(Ink.accentText)
            VStack(alignment: .leading, spacing: 3) { Text("A 3-week save streak").font(Ink.body(15, weight: "DemiBold")); Text("A few good places, week after week.").font(Ink.body(12)).foregroundStyle(Ink.muted) }
            Spacer(minLength: 0)
        }.padding(17).background(Ink.surface, in: RoundedRectangle(cornerRadius: 19))
    }
    private var yourMapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { EditorialTitle(text: "Your Map", size: 26); Spacer(); Text("\(store.ownPlaces.count) places").font(Ink.body(12)).foregroundStyle(Ink.muted) }
            Map(initialPosition: .region(.init(center: ReviewStore.center, span: .init(latitudeDelta: 0.045, longitudeDelta: 0.045))), interactionModes: []) {
                ForEach(store.ownPlaces) { activity in Marker(activity.place, coordinate: activity.coordinate).tint(Ink.coral) }
            }.mapStyle(.standard(pointsOfInterest: .excludingAll)).frame(height: 125).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true)
            Button { store.openYourMap() } label: {
                HStack { Text("Explore Your Map"); Spacer(); Image(systemName: "arrow.up.right") }
            }.buttonStyle(QuietButton()).accessibilityIdentifier("profile.yourMap")
        }.padding(17).background(Ink.surface, in: RoundedRectangle(cornerRadius: 22))
    }
    private var calendar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { EditorialTitle(text: "Your calendar", size: 25); Spacer(); Text("October 2026").font(Ink.body(12)).foregroundStyle(Ink.muted) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 8) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in Text(String(day.prefix(1))).font(Ink.body(10, weight: "DemiBold")).foregroundStyle(Ink.muted).frame(height: 24) }
                ForEach(["padding-0", "padding-1", "padding-2"], id: \.self) { _ in Color.clear.frame(height: 30) }
                ForEach(1...31, id: \.self) { day in
                    Text("\(day)").font(Ink.body(12, weight: [3, 6, 9].contains(day) ? "DemiBold" : "Regular")).frame(maxWidth: .infinity, minHeight: 30)
                        .background([3, 6, 9].contains(day) ? Ink.coral.opacity(0.18) : .clear, in: Circle())
                }
            }
            Text("Sample activity days · no real calendar connected").font(Ink.body(11)).foregroundStyle(Ink.muted)
        }
    }
}

struct YourMapView: View {
    @EnvironmentObject private var store: ReviewStore
    @State private var shareExplanation = false
    private var places: [Activity] { store.ownPlaces(matching: store.profileMapKind) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { store.showYourMap = false; store.showPatterns = false } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Back to Profile").accessibilityIdentifier("yourMap.back")
                EditorialTitle(text: "Your Map", size: 28)
                Spacer()
                Button { shareExplanation = true } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }.accessibilityLabel("Share Your Map · prototype information")
            }.padding(.horizontal, 14).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.showPatterns { patterns }
                    else {
                        Map(position: $store.profileMapCamera) {
                            ForEach(places) { activity in
                                Annotation(activity.place, coordinate: activity.coordinate) {
                                    Button { store.sheet = .detail(activity) } label: { Image(systemName: activity.kind.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Ink.black).frame(width: 44, height: 44).background(Ink.coral, in: Circle()) }
                                        .accessibilityLabel(activity.place).accessibilityIdentifier("yourMap.pin.\(activity.place)")
                                }
                            }
                        }.mapStyle(.standard(pointsOfInterest: .excludingAll)).frame(height: 290).clipShape(RoundedRectangle(cornerRadius: 23))
                        HStack { Text("Snapshot").font(Ink.body(16, weight: "DemiBold")); Spacer(); Text("\(places.count) places · all time").font(Ink.body(12)).foregroundStyle(Ink.muted) }
                        Picker("Your Map status", selection: $store.profileMapKind) {
                            Text("All").tag(nil as ActivityKind?); Text("Been").tag(ActivityKind.checkin as ActivityKind?); Text("Wanna").tag(ActivityKind.wanna as ActivityKind?)
                        }.pickerStyle(.segmented).accessibilityIdentifier("yourMap.status")
                        ForEach(places) { activity in
                            Button { store.sheet = .detail(activity) } label: {
                                HStack { VStack(alignment: .leading, spacing: 4) { Text(activity.place).font(Ink.title(24)); Text("\(activity.neighborhood) · \(activity.kind.rawValue)").font(Ink.body(12)).foregroundStyle(Ink.muted) }; Spacer(); Image(systemName: "chevron.right") }.frame(minHeight: 62).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("yourMap.place.\(activity.place)")
                        }
                        DemoNote(text: "Your Map stays in Profile. This continuity representation shows sample status filtering and place history; production map filters and lenses are not being removed.")
                    }
                }.padding(22)
            }
            HStack(spacing: 32) {
                modeButton("Map", symbol: "map", patterns: false)
                modeButton("Patterns", symbol: "circle.hexagongrid", patterns: true)
            }.frame(maxWidth: .infinity).padding(.vertical, 8).background(Ink.surface)
        }
            .alert("Sharing stays in Your Map", isPresented: $shareExplanation) { Button("Done", role: .cancel) { } } message: { Text("This is a continuity representation. Sharing is not connected and no link is generated.") }
    }
    private func modeButton(_ label: String, symbol: String, patterns: Bool) -> some View {
        Button { store.showPatterns = patterns } label: {
            VStack(spacing: 5) { Label(label, systemImage: symbol).font(Ink.body(14, weight: "DemiBold")); Capsule().fill(store.showPatterns == patterns ? Ink.coral : .clear).frame(width: 25, height: 2) }.frame(minWidth: 100, minHeight: 44)
        }.foregroundStyle(store.showPatterns == patterns ? Ink.text : Ink.text.opacity(0.6)).accessibilityAddTraits(store.showPatterns == patterns ? .isSelected : []).accessibilityIdentifier(patterns ? "yourMap.mode.patterns" : "yourMap.mode.map")
    }
    private var patterns: some View {
        VStack(alignment: .leading, spacing: 23) {
            Text("YOUR SAMPLE SNAPSHOT").font(Ink.body(10, weight: "DemiBold", relativeTo: .caption)).tracking(1.5).foregroundStyle(Ink.accentText)
            EditorialTitle(text: "Close to home. Open to a detour.", size: 35)
            pattern("mug", "A good coffee is a compass", "Juniper Coffee is the familiar stop in this sample history.")
            pattern("sun.max", "A neighborhood kind of week", "Ocean Park anchors these place memories, with a little Venice in the mix.")
            pattern("bookmark", "Room for something new", "Dune Bakery is waiting on your Wanna list.")
            DemoNote(text: "Illustrative patterns, not computed analytics. Patterns remains a mode of Your Map within Profile.")
        }
    }
    private func pattern(_ icon: String, _ title: String, _ copy: String) -> some View {
        VStack(alignment: .leading, spacing: 12) { Image(systemName: icon).font(.system(size: 27)).foregroundStyle(Ink.accentText); EditorialTitle(text: title, size: 25); Text(copy).font(Ink.body(14)).foregroundStyle(Ink.muted) }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Ink.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct ListsView: View {
    @EnvironmentObject private var store: ReviewStore
    private let collections = ["All saved", "A slow Saturday", "Worth a dinner"]
    private var places: [Activity] {
        switch store.selectedCollection {
        case "A slow Saturday": [Fixtures.activities[0], Fixtures.activities[2], Fixtures.activities[7]]
        case "Worth a dinner": [Fixtures.activities[1], Fixtures.activities[6]]
        default: store.ownPlaces + [Fixtures.activities[1], Fixtures.activities[2]]
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { EditorialTitle(text: "Lists", size: 36); Spacer(); AddPlaceButton(); ReviewMenu() }
                Text("Good places, kept together.").font(Ink.body(15)).foregroundStyle(Ink.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 22) {
                        ForEach(collections, id: \.self) { collection in
                            Button { store.selectedCollection = collection } label: {
                                VStack(spacing: 9) { Text(collection).font(Ink.body(14, weight: store.selectedCollection == collection ? "DemiBold" : "Regular")); Rectangle().fill(store.selectedCollection == collection ? Ink.coral : .clear).frame(height: 2) }.frame(minHeight: 44)
                            }.foregroundStyle(Ink.text).accessibilityAddTraits(store.selectedCollection == collection ? .isSelected : [])
                        }
                    }
                }
                HStack { Text("\(places.count) places").font(Ink.body(12)).foregroundStyle(Ink.muted); Spacer(); Text("SAMPLE COLLECTION").font(Ink.body(9, weight: "DemiBold", relativeTo: .caption2)).tracking(1.3).foregroundStyle(Ink.accentText) }
                ForEach(places) { activity in
                    Button { store.sheet = .detail(activity) } label: {
                        HStack(alignment: .center, spacing: 17) {
                            Image(systemName: categoryIcon(activity.category)).font(.system(size: 26, weight: .light)).foregroundStyle(Ink.accentText).frame(width: 66, height: 78).background(Ink.coral.opacity(0.1), in: RoundedRectangle(cornerRadius: 19))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(activity.place).font(Ink.title(25)).fixedSize(horizontal: false, vertical: true)
                                Text("\(activity.neighborhood) · \(activity.category)").font(Ink.body(12)).foregroundStyle(Ink.muted)
                                Label(activity.kind == .wanna ? "Wanna go" : "Been", systemImage: activity.kind.symbol).font(Ink.body(11)).foregroundStyle(Ink.accentText)
                            }
                            Spacer(minLength: 0); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Ink.muted)
                        }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("list.place.\(activity.place)")
                    Divider().overlay(Ink.text.opacity(0.05))
                }
                DemoNote(text: "Sample saved collections for reviewing navigation. Creating or editing lists is outside this prototype.")
            }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 30)
        }.background(Ink.canvas).clipped()
    }
    private func categoryIcon(_ category: String) -> String {
        switch category { case "Coffee": "cup.and.saucer"; case "Books": "books.vertical"; case "Bakery": "birthday.cake"; case "Art": "paintpalette"; default: "fork.knife" }
    }
}
