import SwiftUI
import MapKit

struct FiltersView: View {
    @EnvironmentObject private var store: ReviewStore
    @Environment(\.dismiss) private var dismiss
    @State private var stagedKinds: Set<ActivityKind> = []
    @State private var stagedTime: TimeWindow = .week
    @State private var stagedArea: GeographicArea?
    @State private var stagedRadius: Double = 5000
    @State private var stagedQuery = ""
    @State private var loaded = false
    private var count: Int { store.projection(kinds: stagedKinds, time: stagedTime, area: stagedArea, nearbyRadius: stagedRadius, query: stagedQuery).count }
    var body: some View {
        SheetShell(title: "A little more specific", doneTitle: "Cancel") {
            EditorialTitle(text: "Find your kind of moment")
            Text("The map and activity always show the same places.").font(Ink.body(14)).foregroundStyle(Ink.muted)
            VStack(alignment: .leading, spacing: 6) {
                Text("ACTIVITY").font(Ink.body(11, weight: "DemiBold", relativeTo: .caption)).tracking(1.5)
                ForEach(ActivityKind.allCases) { kind in
                    Button {
                        if stagedKinds.contains(kind) { stagedKinds.remove(kind) } else { stagedKinds.insert(kind) }
                    } label: {
                        HStack { Label(kind.rawValue, systemImage: kind.symbol); Spacer(); Image(systemName: stagedKinds.contains(kind) ? "checkmark.circle.fill" : "circle").foregroundStyle(stagedKinds.contains(kind) ? Ink.accentText : Ink.text.opacity(0.3)) }.frame(minHeight: 48)
                    }.foregroundStyle(Ink.text).accessibilityAddTraits(stagedKinds.contains(kind) ? .isSelected : [])
                }
                Text("Nothing selected includes all activity.").font(Ink.body(12)).foregroundStyle(Ink.muted)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("WHEN").font(Ink.body(11, weight: "DemiBold", relativeTo: .caption)).tracking(1.5)
                ForEach(TimeWindow.allCases) { window in
                    Button { stagedTime = window } label: {
                        HStack { Text(window.rawValue); Spacer(); if stagedTime == window { Image(systemName: "checkmark").foregroundStyle(Ink.accentText) } }.frame(minHeight: 48)
                    }.foregroundStyle(Ink.text).accessibilityAddTraits(stagedTime == window ? .isSelected : [])
                }
            }
            if let area = stagedArea {
                HStack { Label(area.label, systemImage: "circle.dashed"); Spacer(); Button("Clear area") { stagedArea = nil }.frame(minHeight: 44) }
            }
            if store.scope == .nearby {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NEAR OCEAN PARK").font(Ink.body(11, weight: "DemiBold", relativeTo: .caption)).tracking(1.5)
                    Text("A chosen demo neighborhood, not your live location.").font(Ink.body(13)).foregroundStyle(Ink.muted)
                    Picker("Nearby radius", selection: $stagedRadius) {
                        Text("5 km").tag(5000.0); Text("15 km").tag(15000.0); Text("25 km").tag(25000.0)
                    }.pickerStyle(.segmented)
                }
            }
            Button("Show \(count) \(count == 1 ? "memory" : "memories")") {
                store.kinds = stagedKinds; store.time = stagedTime; store.area = stagedArea
                store.nearbyRadius = stagedRadius; store.query = stagedQuery; dismiss()
            }.buttonStyle(SignalButton()).accessibilityIdentifier("filters.apply")
            Button("Reset filters") {
                stagedKinds = []; stagedTime = store.scope == .yours ? .all : .week
                stagedArea = nil; stagedRadius = 5000; stagedQuery = ""
            }.frame(maxWidth: .infinity, minHeight: 44)
        }.onAppear {
            guard !loaded else { return }
            stagedKinds = store.kinds; stagedTime = store.time; stagedArea = store.area
            stagedRadius = store.nearbyRadius; stagedQuery = store.query; loaded = true
        }
    }
}

struct ActivityDetail: View {
    @EnvironmentObject private var store: ReviewStore
    let activity: Activity
    var body: some View {
        SheetShell(title: "A place memory") {
            HStack(spacing: 13) {
                Avatar(initials: activity.initials, size: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.person).font(Ink.body(21, weight: "DemiBold"))
                    Text("\(activity.kind.verb) · \(activity.timeLabel)").font(Ink.body(13)).foregroundStyle(Ink.muted)
                    Text(activity.isOwn ? "Only you · demo" : "Following · demo visibility").font(Ink.body(11, relativeTo: .caption)).foregroundStyle(Ink.accentText)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                EditorialTitle(text: activity.place, size: 35)
                Text("\(activity.category) · \(activity.neighborhood)").font(Ink.body(14)).foregroundStyle(Ink.muted)
                Text(activity.note).font(Ink.body(17)).padding(.top, 12).fixedSize(horizontal: false, vertical: true)
            }
            if activity.isOwn {
                let history = store.activities.filter { $0.isOwn && $0.placeKey == activity.placeKey }.sorted { $0.hoursAgo < $1.hoursAgo }
                if history.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("YOUR PLACE HISTORY").font(Ink.body(11, weight: "DemiBold", relativeTo: .caption)).tracking(1.2)
                        ForEach(history) { memory in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(memory.kind.rawValue) · \(memory.timeLabel)").font(Ink.body(13, weight: "DemiBold"))
                                Text(memory.note).font(Ink.body(14)).foregroundStyle(Ink.muted)
                            }
                        }
                    }
                }
            }
            Map(initialPosition: .region(.init(center: activity.coordinate, span: .init(latitudeDelta: 0.013, longitudeDelta: 0.013))), interactionModes: []) {
                Marker(activity.place, coordinate: activity.coordinate).tint(Ink.coral)
            }.mapStyle(.standard(pointsOfInterest: .excludingAll)).frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 21)).accessibilityLabel("Map showing the fictional location of \(activity.place)")
            if activity.kind == .wanna {
                Button { store.sheet = .plan(activity) } label: { Label("Make a plan", systemImage: "calendar.badge.plus") }.buttonStyle(SignalButton()).accessibilityIdentifier("detail.plan")
            }
            if !activity.isOwn {
                Button { store.sheet = .reply(activity) } label: { Label("Reply to \(activity.person.components(separatedBy: " ").first ?? activity.person)", systemImage: "bubble.left") }
                    .buttonStyle(activity.kind == .wanna ? AnyReviewButtonStyle(QuietButton()) : AnyReviewButtonStyle(SignalButton()))
                    .accessibilityIdentifier("detail.reply")
            }
            Button {
                store.sheet = nil
                if activity.isOwn && store.tab == .profile { store.exploreOwnPlace(activity) }
                else {
                    store.tab = .live; store.drawer = .half; store.query = activity.place
                    store.scope = activity.isOwn ? .yours : activity.isFollowing ? .following : .nearby
                    store.time = .all; store.kinds = []; store.area = nil
                    store.camera = .region(.init(center: activity.coordinate, span: .init(latitudeDelta: 0.025, longitudeDelta: 0.025)))
                }
            } label: { Label(activity.isOwn && store.tab == .profile ? "Explore this place in Live" : "Find on Live", systemImage: "map") }
                .buttonStyle(QuietButton()).accessibilityIdentifier("detail.exploreLive")
            if activity.isOwn && store.tab == .profile {
                Text("Review idea: preview just this place in Live. Your Map and Patterns stay in Profile.").font(Ink.body(12)).foregroundStyle(Ink.muted)
            }
            DemoNote()
        }
    }
}

struct AnyReviewButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

struct PlanComposer: View {
    @EnvironmentObject private var store: ReviewStore
    let activity: Activity
    @State private var title = "Let’s go together"
    @State private var when = "This weekend"
    @State private var includePerson = true
    private var recipient: String { activity.isOwn ? "Maya Chen" : activity.person }
    var body: some View {
        SheetShell(title: "Make a plan") {
            Text(activity.isOwn ? "FROM YOUR WANNA" : "FROM \(activity.person.uppercased())’S WANNA").font(Ink.body(10, weight: "DemiBold", relativeTo: .caption)).tracking(1.1).foregroundStyle(Ink.accentText)
            EditorialTitle(text: activity.place, size: 34)
            Text("A good place to start something.").foregroundStyle(Ink.muted)
            VStack(alignment: .leading, spacing: 8) {
                Text("Plan name").font(Ink.body(13, weight: "DemiBold"))
                TextField("A little get-together", text: $title).padding(15).background(Ink.surface, in: RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("plan.title")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("When").font(Ink.body(13, weight: "DemiBold"))
                ForEach(["This weekend", "Next week", "Find a time together"], id: \.self) { option in
                    Button { when = option } label: { HStack { Text(option); Spacer(); Image(systemName: when == option ? "largecircle.fill.circle" : "circle") }.frame(minHeight: 46) }
                        .foregroundStyle(when == option ? Ink.accentText : Ink.text)
                        .accessibilityAddTraits(when == option ? .isSelected : [])
                }
            }
            Toggle(isOn: $includePerson) { Text("Include \(recipient) in this demo plan").font(Ink.body(14)) }.tint(Ink.coral)
            Text("This creates a local demo plan. No invitations or notifications are sent.").font(Ink.body(13)).foregroundStyle(Ink.muted)
            Button("Create demo plan") {
                store.savePlan(for: activity, title: title.trimmingCharacters(in: .whitespacesAndNewlines) + (includePerson ? " · with \(recipient)" : ""), when: when)
            }.buttonStyle(SignalButton()).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("plan.create")
        }
    }
}

struct ReplyComposer: View {
    @EnvironmentObject private var store: ReviewStore
    let activity: Activity
    @State private var message = ""
    @State private var saved = false
    @FocusState private var messageFocused: Bool
    var body: some View {
        SheetShell(title: "A reply, with context") {
            HStack(spacing: 12) { Avatar(initials: activity.initials); VStack(alignment: .leading, spacing: 3) { Text(activity.person).font(Ink.body(16, weight: "DemiBold")); Text("About \(activity.place)").font(Ink.body(13)).foregroundStyle(Ink.muted) } }
            Text("“\(activity.note)”").font(Ink.body(16)).padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Ink.surface, in: RoundedRectangle(cornerRadius: 18))
            if saved {
                Label("Reply saved in your demo inbox", systemImage: "checkmark.circle.fill").font(Ink.body(18, weight: "DemiBold")).foregroundStyle(Ink.accentText)
                Text("This is a local interaction preview. \(activity.person) hasn’t received a message.").font(Ink.body(14)).foregroundStyle(Ink.muted)
                Button("Open demo inbox") { store.sheet = .inbox }.buttonStyle(SignalButton())
            } else {
                Text("Your reply").font(Ink.body(13, weight: "DemiBold"))
                TextEditor(text: $message).scrollContentBackground(.hidden).frame(minHeight: 150).padding(10)
                    .background(Ink.surface, in: RoundedRectangle(cornerRadius: 17)).accessibilityLabel("Write a reply").accessibilityIdentifier("reply.message")
                    .focused($messageFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done typing") { messageFocused = false }.accessibilityIdentifier("reply.doneTyping")
                        }
                    }
                Text("Demo only. This reply is saved locally and never sent.").font(Ink.body(13)).foregroundStyle(Ink.muted)
                Button("Save demo reply") {
                    store.replies.insert(.init(person: activity.person, place: activity.place, message: message.trimmingCharacters(in: .whitespacesAndNewlines)), at: 0)
                    saved = true
                }.buttonStyle(SignalButton()).disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("reply.save")
            }
        }
    }
}

struct InboxView: View {
    @EnvironmentObject private var store: ReviewStore
    var body: some View {
        SheetShell(title: "Demo inbox") {
            EditorialTitle(text: "The place is part of the conversation")
            Text("Local previews of your replies. Nothing here has been sent.").font(Ink.body(14)).foregroundStyle(Ink.muted)
            if store.replies.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 34)).foregroundStyle(Ink.accentText)
                    Text("Start with a place").font(Ink.body(18, weight: "DemiBold"))
                    Text("Reply to someone’s place memory in Live. Their place and your reply will stay together here.").font(Ink.body(15))
                }.padding(.vertical, 22)
            }
            ForEach(store.replies) { reply in
                VStack(alignment: .leading, spacing: 8) {
                    Text(reply.person).font(Ink.body(16, weight: "DemiBold"))
                    Text(reply.place).font(Ink.title(23))
                    Text(reply.message).font(Ink.body(15))
                    Text("Saved locally · not sent").font(Ink.body(11, relativeTo: .caption)).foregroundStyle(Ink.accentText)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Ink.surface, in: RoundedRectangle(cornerRadius: 19))
            }
        }
    }
}

struct AddComposer: View {
    @EnvironmentObject private var store: ReviewStore
    @State private var kind: ActivityKind = .checkin
    @State private var selected = 0
    @State private var note = ""
    private var choices: [Activity] { Array(Fixtures.activities.prefix(6)) }
    var body: some View {
        SheetShell(title: "Add a place") {
            EditorialTitle(text: "Keep a little of today")
            Picker("Place memory type", selection: $kind) {
                Text("Been").tag(ActivityKind.checkin); Text("Wanna go").tag(ActivityKind.wanna)
            }.pickerStyle(.segmented)
            Text("CHOOSE A SAMPLE PLACE").font(Ink.body(11, weight: "DemiBold", relativeTo: .caption)).tracking(1.1)
            ForEach(choices.indices, id: \.self) { index in
                Button { selected = index } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) { Text(choices[index].place).font(Ink.body(16, weight: "Medium")); Text(choices[index].neighborhood).font(Ink.body(12)).foregroundStyle(Ink.muted) }
                        Spacer(); Image(systemName: selected == index ? "checkmark.circle.fill" : "circle").foregroundStyle(selected == index ? Ink.accentText : Ink.text.opacity(0.3))
                    }.frame(minHeight: 48)
                }.foregroundStyle(Ink.text).accessibilityAddTraits(selected == index ? .isSelected : [])
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("A note to remember").font(Ink.body(13, weight: "DemiBold"))
                TextField("What made it worth keeping?", text: $note, axis: .vertical).lineLimit(3...6).padding(15).background(Ink.surface, in: RoundedRectangle(cornerRadius: 17))
            }
            Label("Only you · local demo", systemImage: "lock").font(Ink.body(13)).foregroundStyle(Ink.muted)
            Button(kind == .checkin ? "Save demo check-in" : "Save demo Wanna") { store.savePlace(choices[selected], kind: kind, note: note) }
                .buttonStyle(SignalButton()).accessibilityIdentifier("add.save")
            DemoNote(text: "Sample place selection only. This prototype does not look up places or request your location.")
        }
    }
}

struct GuideView: View {
    @EnvironmentObject private var store: ReviewStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        SheetShell(title: "Your Feed now has a map.") {
            EditorialTitle(text: "Explore your people’s recent activity.")
            Text("Your Map is still in Profile.").font(Ink.body(16)).foregroundStyle(Ink.muted)
            guideRow("map", "Live brings them together", "The map and activity are two views of the same place memories. Pull the drawer, or use its arrow controls.")
            guideRow("person.crop.circle", "Your Map stays in Profile", "Your identity, streak, recent activity, calendar, Your Map, and Patterns keep their familiar home. A selected place can be explored in Live as a review idea.")
            guideRow("calendar.badge.plus", "A Wanna can become a plan", "Open a friend’s Wanna, make a demo plan, or leave a contextual reply in the local demo inbox.")
            DemoNote(text: "Standalone review app. All names, places, history, and social relationships are fictional. Plans, saves, and replies exist only for this session. Apple Maps supplies the background; no Astir services are connected.")
            Button("Explore Live") { store.cancelAreaDraft(); store.tab = .live; store.drawer = .half; dismiss() }.buttonStyle(SignalButton())
        }
    }
    private func guideRow(_ symbol: String, _ title: String, _ copy: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: symbol).font(.system(size: 23)).foregroundStyle(Ink.accentText).frame(width: 30)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(Ink.body(17, weight: "DemiBold")); Text(copy).font(Ink.body(14)).foregroundStyle(Ink.muted) }
        }
    }
}

struct EventsView: View {
    @EnvironmentObject private var store: ReviewStore
    var body: some View {
        SheetShell(title: "Astir gatherings") {
            Image(systemName: "sun.horizon").font(.system(size: 42, weight: .light)).foregroundStyle(Ink.accentText)
            EditorialTitle(text: "Good company. A place to begin.", size: 35)
            Text("A preview of a future home for small gatherings around places your people love.").font(Ink.body(16)).foregroundStyle(Ink.muted)
            VStack(alignment: .leading, spacing: 12) {
                Text("COMING SOON · CONCEPT ONLY").font(Ink.body(10, weight: "DemiBold", relativeTo: .caption)).tracking(1.2).foregroundStyle(Ink.accentText)
                EditorialTitle(text: "A neighborhood coffee walk", size: 27)
                Text("An illustrative gathering, with no scheduled date, host, or real attendance list.").font(Ink.body(14))
            }.padding(22).background(Ink.surface, in: RoundedRectangle(cornerRadius: 22))
            Button(store.eventsInterested ? "Demo interest saved" : "Save demo interest") { store.eventsInterested = true }
                .buttonStyle(SignalButton()).disabled(store.eventsInterested).accessibilityIdentifier("events.interest")
            DemoNote(text: "This is not an RSVP or a real event. Interest is saved only for this app session. No registration, invitation, or notification is sent.")
        }
    }
}
