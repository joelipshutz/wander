import SwiftUI
import MapKit

// Native design harness. Fictional fixtures, in-memory state, no account or backend.
private enum T {
    static let coral = Color(red: 240/255, green: 90/255, blue: 60/255)
    static let ink = Color(red: 20/255, green: 23/255, blue: 20/255)
    static let paper = Color(red: 242/255, green: 233/255, blue: 219/255)
    static func body(_ size: CGFloat = 16) -> Font { .custom("AvenirNext-Regular", size: size, relativeTo: .body) }
    static func label(_ size: CGFloat = 15) -> Font { .custom("AvenirNext-DemiBold", size: size, relativeTo: .body) }
    static let title = Font.system(.title, design: .serif).weight(.semibold)
    static let subtitle = Font.system(.title2, design: .serif).weight(.semibold)
}

@main struct QuickCapturePreviewApp: App {
    var body: some Scene {
        WindowGroup {
            QuickCapturePreview()
                .preferredColorScheme(CommandLine.arguments.contains("--dark") ? .dark : .light)
                .dynamicTypeSize(CommandLine.arguments.contains("--large-text") ? .accessibility1 : .large)
        }
    }
}

struct QuickCapturePreview: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var history = PreviewHistory()
    @State private var wanna = PreviewVisit.wanna
    @State private var draft = PreviewVisit(id: "new-visit", time: "Now")
    @State private var route = "map"
    @State private var selectedID = "visit-juniper-today"
    @State private var showingCapture = false
    @State private var expanded = false
    @State private var editing = false
    @State private var saved = false
    @State private var changed = false
    @State private var showInvitation = false
    @State private var remindersEnabled = true
    @State private var reminderTiming = "A few hours later"
    @State private var detent: PresentationDetent = .height(445)
    @State private var section: DetailSection?
    @State private var selectedDate = Date()
    @State private var showingDate = false
    @State private var discardAlert = false
    @State private var unavailableReminder = false
    @State private var originalDraft = PreviewVisit(id: "new-visit", time: "Now")
    @State private var query = ""
    private let launchScreen: String
    private let coordinate = CLLocationCoordinate2D(latitude: 34.0011, longitude: -118.4825)

    init() {
        let args = CommandLine.arguments
        let screen = args.firstIndex(of: "--screen").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "invitation"
        launchScreen = screen
        let routes = ["profile", "history", "place", "visits", "visit", "updated", "reminders", "notification", "wannas", "wanna-detail"]
        _route = State(initialValue: routes.contains(screen) ? screen : "map")
        _showInvitation = State(initialValue: screen == "invitation")
        _saved = State(initialValue: ["saved", "wanna-saved"].contains(screen))
        let isEdit = ["edit", "rated", "push-edit", "options", "wanna-edit"].contains(screen)
        let isExpanded = isEdit || ["details", "wanna-details"].contains(screen)
        let isWanna = ["wanna", "wanna-edit", "wanna-saved", "wanna-details"].contains(screen)
        var value = isEdit ? PreviewVisit.fixtures[0] : PreviewVisit(id: "new-visit", time: screen == "later" ? "Today, 7:15 AM" : "Now")
        if isWanna { value = .wanna }
        if screen == "saved" { value = PreviewVisit.fixtures[0] }
        if screen == "rated" { value.rating.select(4.5); value.note = "A sunny table, a good flat white. Easy to stay a while." }
        _draft = State(initialValue: value)
        _originalDraft = State(initialValue: value)
        _editing = State(initialValue: isEdit)
        _expanded = State(initialValue: isExpanded)
        _detent = State(initialValue: isExpanded || args.contains("--large-text") ? .large : .height(445))
        _changed = State(initialValue: screen == "updated")
        if screen == "updated" {
            var state = PreviewHistory()
            state.visits[0].rating.select(4.5)
            state.visits[0].note = "A sunny table, a good flat white. Easy to stay a while."
            state.visits[0].invitationDismissed = true
            _history = State(initialValue: state)
        }
    }

    private var background: Color { scheme == .dark ? T.ink : T.paper }
    private var foreground: Color { scheme == .dark ? T.paper : T.ink }
    private var surface: Color { scheme == .dark ? Color(red: 27/255, green: 31/255, blue: 27/255) : Color(red: 251/255, green: 246/255, blue: 237/255) }
    private var secondary: Color { scheme == .dark ? Color(red: 174/255, green: 170/255, blue: 160/255) : Color(red: 101/255, green: 95/255, blue: 87/255) }
    private var accent: Color { scheme == .dark ? T.coral : Color(red: 178/255, green: 54/255, blue: 32/255) }
    private var selectedVisit: PreviewVisit { history.visits.first { $0.id == selectedID } ?? history.visits[0] }
    private var recent: PreviewVisit { history.visits[0] }

    var body: some View {
        ZStack { background.ignoresSafeArea(); rootContent }
            .foregroundStyle(foreground).tint(accent).buttonStyle(.plain)
            .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
            .sheet(isPresented: $showingCapture) { captureSheet }
            .alert("This check-in is no longer available", isPresented: $unavailableReminder) {
                Button("Your check-ins") { route = "history" }
                Button("Close", role: .cancel) { }
            }
            .task {
                let captureStates = ["quick", "details", "later", "edit", "rated", "push-edit", "options", "wanna", "wanna-edit", "wanna-details"]
                if captureStates.contains(launchScreen) { showingCapture = true }
            }
    }

    @ViewBuilder private var rootContent: some View {
        switch route {
        case "profile": profilePage
        case "history": historyPage(placeOnly: false)
        case "visits": historyPage(placeOnly: true)
        case "place": placePage
        case "visit", "updated": visitPage
        case "reminders": remindersPage
        case "notification": notificationPage
        case "wannas": wannaHistoryPage
        case "wanna-detail": wannaDetailPage
        default: mapPage
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach([("Map", "map"), ("Add", "plus"), ("Discover", "sparkle.magnifyingglass"), ("Profile", "person.crop.circle")], id: \.0) { item in
                Button {
                    if item.0 == "Add" { startCapture(wanna: false) }
                    else if item.0 == "Profile" { route = "profile" }
                    else if item.0 == "Map" { route = "map" }
                    else { /* Discover is outside this scoped prototype. */ }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.1).font(.system(size: 19))
                        Text(item.0).font(T.label(10))
                        Capsule().fill((route == "map" && item.0 == "Map") || (route != "map" && item.0 == "Profile") ? accent : .clear).frame(width: 20, height: 2)
                    }.frame(maxWidth: .infinity, minHeight: 52)
                }
            }
        }.padding(.horizontal, 10).padding(.top, 8).background(.regularMaterial)
            .foregroundStyle(foreground).tint(accent).buttonStyle(.plain)
    }

    private var mapPage: some View {
        ZStack {
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)))) {
                Annotation("Juniper Coffee", coordinate: coordinate) {
                    Image(systemName: "cup.and.saucer.fill").font(.title3).padding(13)
                        .foregroundStyle(T.ink).background(T.coral, in: Circle()).overlay(Circle().stroke(T.paper, lineWidth: 3))
                }
            }.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll)).ignoresSafeArea()
            VStack(spacing: 12) {
                HStack {
                    Text("ASTIR").font(.system(size: 24, weight: .medium, design: .serif)).tracking(2)
                        .padding(.horizontal, 18).frame(height: 48).background(.regularMaterial, in: Capsule())
                    Spacer()
                    Button { route = "history" } label: { Image(systemName: "clock.arrow.circlepath").frame(width: 48, height: 48).background(.regularMaterial, in: Circle()) }
                        .accessibilityLabel("Your check-ins")
                }
                Spacer()
                if showInvitation && recent.invitationEligible { invitationCard }
                if saved { successCard }
                else if !showInvitation {
                    VStack(alignment: .leading, spacing: 12) {
                        Button { route = "place" } label: {
                            HStack { VStack(alignment: .leading, spacing: 5) { Text("Juniper Coffee").font(T.subtitle); Text("Coffee shop · Ocean Park").font(T.body(13)).foregroundStyle(secondary) }; Spacer(); Image(systemName: "chevron.right") }
                        }
                        HStack(spacing: 10) {
                            primary("Check in", icon: "checkmark") { startCapture(wanna: false) }
                            Button { startCapture(wanna: true) } label: { Label("Wanna", systemImage: "bookmark").font(T.label()).padding(.horizontal, 16).frame(minHeight: 52).background(surface, in: RoundedRectangle(cornerRadius: 17)) }
                        }
                    }.padding(20).background(background, in: RoundedRectangle(cornerRadius: 25))
                }
            }.padding(16)
        }
    }

    private var invitationCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                Label("Your recent check-in", systemImage: "clock").font(T.label(12)).foregroundStyle(secondary)
                Spacer()
                Button { dismissInvitation() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 44, height: 44) }
                    .accessibilityLabel("Dismiss this invitation").padding(.trailing, -10).padding(.top, -12)
            }
            Text(recent.place).font(T.subtitle)
            Text(recent.time).font(T.body(13)).foregroundStyle(secondary)
            Text("Want to add a rating, photo, or note?").font(T.body(15))
            HStack {
                Button { edit(recent) } label: { Label("Add details", systemImage: "square.and.pencil").font(T.label()).frame(minHeight: 44) }.foregroundStyle(accent)
                Spacer()
                Button("Dismiss") { dismissInvitation() }.font(T.body(14)).foregroundStyle(secondary).frame(minHeight: 44)
            }
        }.padding(20).background(background, in: RoundedRectangle(cornerRadius: 25))
    }

    private var successCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(changed ? "Changes saved" : (draft.isWanna ? "Saved to Wanna" : "Checked in"), systemImage: "checkmark.circle.fill").font(T.label(14)).foregroundStyle(accent)
                Spacer()
                if !changed { Button("Undo") { undoSave() }.font(T.label(13)).frame(minHeight: 44) }
            }
            Text(draft.place).font(T.subtitle)
            Text("\(draft.time) · \(draft.audience)").font(T.body(13)).foregroundStyle(secondary)
            HStack {
                Text(draft.isWanna ? "A place for another day" : ratingText(draft)).font(T.body(13)).foregroundStyle(secondary)
                Spacer()
                Button { edit(draft) } label: { Label("Add details", systemImage: "square.and.pencil").font(T.label(14)).frame(minHeight: 44) }.foregroundStyle(accent)
            }
            if !draft.isWanna {
                Button("View this check-in") { selectedID = draft.id; route = "visit" }.font(T.body(13)).frame(minHeight: 44)
            }
        }.padding(20).background(background, in: RoundedRectangle(cornerRadius: 25))
    }

    private var profilePage: some View {
        page {
            HStack { Text("Your profile").font(T.label(14)); Spacer(); Button { route = "reminders" } label: { Image(systemName: "gearshape").frame(width: 44, height: 44) }.accessibilityLabel("Notification settings") }
            HStack(spacing: 16) {
                Text("JL").font(.system(.title, design: .serif)).frame(width: 72, height: 72).background(surface, in: Circle())
                VStack(alignment: .leading, spacing: 5) { Text("Jamie Lane").font(T.title); Text("Good places, good company.").font(T.body(14)).foregroundStyle(secondary) }
            }.padding(.bottom, 6)
            HStack(spacing: 30) { stat("28", "Places"); stat("34", "Following"); stat("21", "Followers") }.padding(.bottom, 10)
            Text("Your places & visits").font(T.subtitle)
            navigationRow("Your check-ins", subtitle: "Every visit, all in one place", icon: "clock.arrow.circlepath", count: "3") { route = "history" }
            navigationRow("Your Wanna", subtitle: "Places for another day", icon: "bookmark", count: "1") { route = "wannas" }
            navigationRow("Your map", subtitle: "Places you've kept", icon: "map") { route = "map" }
            Text("Recent check-in").font(T.subtitle).padding(.top, 12)
            visitCard(recent)
        }
    }

    private func historyPage(placeOnly: Bool) -> some View {
        page {
            back(placeOnly ? "Juniper Coffee" : "Profile", to: placeOnly ? "place" : "profile")
            Text(placeOnly ? "Your visits" : "Your check-ins").font(T.title)
            Text(placeOnly ? "Juniper Coffee · 2 visits" : "Your memories, visit by visit.").font(T.body(15)).foregroundStyle(secondary)
            if !placeOnly {
                HStack { Image(systemName: "magnifyingglass"); TextField("Find a place", text: $query).font(T.body(15)) }.padding(14).background(surface, in: RoundedRectangle(cornerRadius: 16))
            }
            ForEach(history.visits.filter { (!placeOnly || $0.place == "Juniper Coffee") && (query.isEmpty || $0.place.localizedCaseInsensitiveContains(query)) }) { visit in
                visitCard(visit)
            }
            if placeOnly {
                primary("Check in again", icon: "plus") { startCapture(wanna: false) }
            }
        }
    }

    private func visitCard(_ visit: PreviewVisit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { selectedID = visit.id; route = "visit" } label: {
                HStack(alignment: .top, spacing: 12) {
                    placeGlyph(visit.place == "Juniper Coffee" ? "cup.and.saucer" : "fork.knife", size: 44)
                    VStack(alignment: .leading, spacing: 6) { Text(visit.place).font(T.label(17)); Text(visit.time).font(T.body(13)).foregroundStyle(secondary) }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).padding(.top, 8)
                }.frame(minHeight: 48)
            }
            if !visit.note.isEmpty { Text(visit.note).font(T.body(14)).foregroundStyle(secondary) }
            HStack {
                Label(ratingText(visit), systemImage: visit.rating.value == nil ? "star" : "star.fill").font(T.body(13)).foregroundStyle(secondary)
                Spacer()
                Button(visit.hasDetails ? "Edit visit" : "Add details") { edit(visit) }.font(T.label(14)).foregroundStyle(accent).frame(minHeight: 44)
            }
        }.padding(18).background(surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private var placePage: some View {
        page {
            back("Map", to: "map")
            HStack(alignment: .center, spacing: 16) { placeGlyph("cup.and.saucer", size: 64); VStack(alignment: .leading, spacing: 6) { Text("Juniper Coffee").font(T.title); Text("Coffee shop · Ocean Park").font(T.body(14)).foregroundStyle(secondary) } }
            HStack { primary("Check in", icon: "checkmark") { startCapture(wanna: false) }; Button { startCapture(wanna: true) } label: { Label("Wanna", systemImage: "bookmark").font(T.label()).padding(16).background(surface, in: RoundedRectangle(cornerRadius: 17)) } }
            Divider().padding(.vertical, 4)
            HStack { Text("Your visits").font(T.subtitle); Spacer(); Button("See all (2)") { route = "visits" }.font(T.label(13)).foregroundStyle(accent).frame(minHeight: 44) }
            visitCard(recent)
            Text("For another day").font(T.subtitle).padding(.top, 4)
            navigationRow("Saved to Wanna", subtitle: "Add a note or make a plan", icon: "bookmark.fill") { route = "wanna-detail" }
            Text("Your check-ins stay separate, so each visit keeps its own memories.").font(T.body(14)).foregroundStyle(secondary)
        }
    }

    private var visitPage: some View {
        let visit = selectedVisit
        return page {
            back("Your check-ins", to: "history")
            if changed { Label("Changes saved", systemImage: "checkmark.circle.fill").font(T.label(14)).foregroundStyle(accent) }
            Text("Your check-in").font(T.label(13)).foregroundStyle(accent)
            Text(visit.place).font(T.title)
            Text(visit.area).font(T.body(14)).foregroundStyle(secondary)
            VStack(alignment: .leading, spacing: 16) {
                Label(visit.time, systemImage: "calendar").font(T.label(15))
                Label(visit.audience, systemImage: visit.audience == "Self" ? "lock" : "person.2").font(T.body(14)).foregroundStyle(secondary)
                Label(ratingText(visit), systemImage: visit.rating.value == nil ? "star" : "star.fill").font(T.label(17)).foregroundStyle(visit.rating.value == nil ? secondary : accent)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: RoundedRectangle(cornerRadius: 20))
            if visit.note.isEmpty {
                Text("A moment worth keeping.").font(T.subtitle)
                Text("Your visit is saved. Add a little more whenever you like.").font(T.body()).foregroundStyle(secondary)
            } else {
                Text("Your note").font(T.subtitle)
                Text(visit.note).font(T.body())
            }
            primary(visit.hasDetails ? "Edit visit" : "Add details", icon: "square.and.pencil") { edit(visit) }
            HStack(spacing: 16) {
                quickDetail("Photos", icon: "photo")
                quickDetail("Friends", icon: "person.2")
                quickDetail("More", icon: "ellipsis")
            }
            Divider().padding(.vertical, 4)
            navigationRow("Juniper Coffee", subtitle: "View place & all your visits", icon: "mappin") { route = "place" }
        }
    }

    private func quickDetail(_ title: String, icon: String) -> some View {
        Button { edit(selectedVisit); section = DetailSection(id: title == "More" ? "Tags" : title) } label: {
            VStack(spacing: 7) { Image(systemName: icon); Text(title).font(T.label(12)) }.frame(maxWidth: .infinity, minHeight: 68).background(surface, in: RoundedRectangle(cornerRadius: 15))
        }
    }

    private var wannaHistoryPage: some View {
        page {
            back("Profile", to: "profile")
            Text("Your Wanna").font(T.title)
            Text("Places for another day.").font(T.body()).foregroundStyle(secondary)
            navigationRow(wanna.place, subtitle: "Saved today · \(wanna.time)", icon: "bookmark") { route = "wanna-detail" }
            Text("Add notes and plans whenever inspiration strikes.").font(T.body(14)).foregroundStyle(secondary)
        }
    }

    private var wannaDetailPage: some View {
        page {
            back("Your Wanna", to: "wannas")
            Label("Saved to Wanna", systemImage: "bookmark.fill").font(T.label(13)).foregroundStyle(accent)
            Text(wanna.place).font(T.title)
            Text(wanna.area).font(T.body(14)).foregroundStyle(secondary)
            Label(wanna.time, systemImage: "calendar").font(T.label()).padding(18).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: RoundedRectangle(cornerRadius: 18))
            Text(wanna.note.isEmpty ? "Something to look forward to." : "Your note").font(T.subtitle)
            Text(wanna.note.isEmpty ? "Keep a recommendation, pick a day, or plan with friends. It's all up to you." : wanna.note).font(T.body()).foregroundStyle(secondary)
            primary("Add details", icon: "square.and.pencil") { edit(wanna) }
            Divider().padding(.vertical, 8)
            Text("Made it here?").font(T.subtitle)
            Button { startCapture(wanna: false) } label: { Label("Check in", systemImage: "checkmark.circle").font(T.label()).frame(minHeight: 48) }.foregroundStyle(accent)
        }
    }

    private var remindersPage: some View {
        page {
            back("Profile", to: "profile")
            Text("Check-in reminders").font(T.title)
            Text("A little nudge to keep the good details.").font(T.body()).foregroundStyle(secondary)
            VStack(alignment: .leading, spacing: 18) {
                Toggle(isOn: $remindersEnabled) { VStack(alignment: .leading, spacing: 5) { Text("Remind me to add details").font(T.label()); Text("Push notifications").font(T.body(13)).foregroundStyle(secondary) } }.tint(accent)
                Divider()
                HStack { Text("Remind me").font(T.body(15)); Spacer(); Menu(reminderTiming) { Button("A few hours later") { reminderTiming = "A few hours later" }; Button("The next day") { reminderTiming = "The next day" } }.font(T.label(13)).foregroundStyle(accent) }.frame(minHeight: 44).disabled(!remindersEnabled)
            }.padding(20).background(surface, in: RoundedRectangle(cornerRadius: 20))
            Text("One gentle reminder after a quick check-in. Add any detail or dismiss its invitation, and we'll leave that visit be.").font(T.body(14)).foregroundStyle(secondary)
            Text("No more than one a day. Never overnight.").font(T.body(14)).foregroundStyle(secondary)
            Text("Notification preview").font(T.subtitle).padding(.top, 6)
            notificationCard
            Button("Preview where it opens") { openReminder() }.font(T.label(14)).foregroundStyle(accent).frame(minHeight: 44)
            Text("You can always find your visits in Profile → Your check-ins.").font(T.body(14)).foregroundStyle(secondary)
        }
    }

    private var notificationCard: some View {
        Button { openReminder() } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Image(systemName: "bell.badge.fill").foregroundStyle(accent); Text("ASTIR").font(T.label(12)).tracking(1); Spacer(); Text("now").font(T.body(12)).foregroundStyle(secondary) }
                Text("Add details to your recent check-in").font(T.label(16))
                Text("A rating, photo, or note—whenever you have a moment.").font(T.body(14)).foregroundStyle(secondary)
            }.padding(18).background(surface, in: RoundedRectangle(cornerRadius: 23))
        }.accessibilityLabel("Notification preview. Add details to your recent check-in. Opens today's Juniper Coffee visit.")
    }

    private var notificationPage: some View {
        page {
            back("Reminders", to: "reminders")
            Text("A timely invitation").font(T.title)
            Text("Push notification concept").font(T.body(14)).foregroundStyle(secondary)
            notificationCard.padding(.vertical, 12)
            Text("Straight to that visit.").font(T.subtitle)
            Text("Tapping the notification opens the check-in it belongs to, ready to add details.").font(T.body()).foregroundStyle(secondary)
            primary("Preview tap", icon: "arrow.up.forward") { openReminder() }
            Text("This native preview shows proposed copy and routing. No notification is sent.").font(T.body(13)).foregroundStyle(secondary)
        }
    }

    private var captureSheet: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 19) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(editing ? (draft.isWanna ? "Edit Wanna" : "Edit visit") : (draft.isWanna ? "Wanna go" : "Check in")).font(T.label(13)).foregroundStyle(accent)
                                Text(draft.place).font(T.title)
                                Text(draft.area).font(T.body(13)).foregroundStyle(secondary)
                            }
                            Spacer(minLength: 4)
                            Button { closeEditor() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 44, height: 44).background(surface, in: Circle()) }.accessibilityLabel("Close editor")
                        }
                        ViewThatFits(in: .horizontal) { HStack(spacing: 8) { timeControl; audienceControl }; VStack(alignment: .leading, spacing: 8) { timeControl; audienceControl } }
                        if expanded { details }
                        else {
                            Label(draft.silent ? "Silent save" : "Notifications on", systemImage: draft.silent ? "bell.slash" : "bell").font(T.body(12)).foregroundStyle(secondary).padding(.top, -8)
                            Divider()
                            Button { withAnimation { expanded = true; detent = .large } } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "square.and.pencil").foregroundStyle(accent)
                                    VStack(alignment: .leading, spacing: 4) { Text("Add details").font(T.label()); Text(draft.isWanna ? "Notes, lists, people & more" : "Rating, photos, people & more").font(T.body(13)).foregroundStyle(secondary) }
                                    Spacer(); Image(systemName: "chevron.right").font(.caption)
                                }.frame(minHeight: 54)
                            }
                        }
                    }.padding(22)
                }.scrollIndicators(.hidden)
                    .task { if launchScreen == "options" { try? await Task.sleep(for: .milliseconds(400)); proxy.scrollTo("optional-fields", anchor: .top) } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    primary(editing ? "Save changes" : (draft.isWanna ? "Save to Wanna" : "Check in"), icon: draft.isWanna ? "bookmark" : "checkmark") { save() }
                    Text(editing ? (draft.isWanna ? "Keep planning whenever you like." : "Visit · \(draft.time)") : "Add anything else whenever you like.").font(T.body(11)).foregroundStyle(secondary).multilineTextAlignment(.center)
                }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 12).background(background)
            }
            .background(background).navigationBarHidden(true)
            .sheet(item: $section) { sectionEditor($0.id) }
            .sheet(isPresented: $showingDate) { datePicker }
            .confirmationDialog("Discard your changes?", isPresented: $discardAlert, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { showingCapture = false }
                Button("Keep editing", role: .cancel) { }
            }
        }.presentationDetents([.height(445), .large], selection: $detent)
            .presentationDragIndicator(.visible).presentationCornerRadius(30).presentationBackground(background)
            .foregroundStyle(foreground).tint(accent).buttonStyle(.plain)
            .interactiveDismissDisabled(draft != originalDraft)
            .dynamicTypeSize(CommandLine.arguments.contains("--large-text") ? .accessibility1 : .large)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Make it yours").font(T.subtitle); Spacer(); Text("All optional").font(T.body(12)).foregroundStyle(secondary) }
            if !draft.isWanna { ratingControl }
            VStack(alignment: .leading, spacing: 8) {
                Text(draft.isWanna ? "What caught your eye?" : "Anything to remember?").font(T.label())
                TextField(draft.isWanna ? "A recommendation, a dish to try…" : "A good table, a favorite order…", text: $draft.note, axis: .vertical)
                    .font(T.body(14)).lineLimit(2...4).padding(14).background(surface, in: RoundedRectangle(cornerRadius: 15))
            }
            VStack(spacing: 0) {
                if !draft.isWanna { detailRow("Photos", icon: "photo", subtitle: "Add a photo") }
                detailRow(draft.isWanna ? "Go with" : "Friends", icon: "person.2", subtitle: draft.isWanna ? "Plan with people" : "Who was there?")
                detailRow("Lists", icon: "list.bullet.rectangle", subtitle: "Add to a list")
                detailRow("Tags", icon: "tag", subtitle: "Describe the place")
                if !draft.isWanna { detailRow("Useful details", icon: "slider.horizontal.3", subtitle: "Your questions & answers") }
                detailRow("Place type", icon: "cup.and.saucer", subtitle: "Coffee shop")
            }.id("optional-fields")
            Toggle("Silent save", isOn: $draft.silent).font(T.body(14)).tint(accent)
            Text("Visibility: \(draft.audience). Silent saves keep the same audience.").font(T.body(12)).foregroundStyle(secondary)
        }
    }

    private var ratingControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your rating").font(T.label())
                Spacer()
                Text(ratingText(draft)).font(T.label(14)).foregroundStyle(draft.rating.value == nil ? secondary : accent)
            }
            Slider(value: Binding(get: { draft.rating.sliderPosition }, set: { draft.rating.select($0) }), in: 1...5, step: 0.5, onEditingChanged: { started in
                if started { draft.rating.beginInteraction() }
            }).tint(draft.rating.value == nil ? secondary.opacity(0.3) : accent)
                .accessibilityLabel("Your rating").accessibilityValue(draft.rating.value.map { "\($0) out of 5" } ?? "Not rated")
                .accessibilityHint("Adjust to add a rating. Leaving this control untouched saves no rating.")
            HStack { Text("1"); Spacer(); Text("5") }.font(T.body(11)).foregroundStyle(secondary)
            if draft.rating.value == nil {
                Text("Optional. Touch the slider to add your rating.").font(T.body(12)).foregroundStyle(secondary)
            } else {
                Button("Remove rating") { draft.rating.remove() }.font(T.body(12)).foregroundStyle(accent).frame(minHeight: 44)
            }
        }.padding(16).background(surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var timeControl: some View {
        Menu {
            if draft.isWanna { Button("Anytime") { draft.time = "Anytime" } }
            else { Button("Now") { draft.time = "Now" }; Button("An hour ago") { draft.time = "Today, 7:15 AM" } }
            Button("Choose date and time") { showingDate = true }
        } label: { chip(draft.time, icon: "calendar") }
    }

    private var audienceControl: some View {
        Menu {
            Picker("Who can see this?", selection: $draft.audience) {
                Text("Everyone (followers)").tag("Everyone")
                Text("Friends (mutual follows)").tag("Friends")
                Text("Self (only me)").tag("Self")
            }
            Toggle("Silent save", isOn: $draft.silent)
        } label: { chip(draft.audience + (draft.silent ? " · Silent" : ""), icon: draft.audience == "Self" ? "lock" : "person.2") }
    }

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(draft.isWanna ? "When would you like to go?" : "When was your visit?").font(T.title)
            if draft.isWanna { DatePicker("Planned date", selection: $selectedDate, in: Date()..., displayedComponents: [.date]).datePickerStyle(.graphical) }
            else { DatePicker("Visit date and time", selection: $selectedDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).datePickerStyle(.graphical) }
            primary("Use this date", icon: "checkmark") { draft.time = selectedDate.formatted(date: .abbreviated, time: draft.isWanna ? .omitted : .shortened); showingDate = false }
        }.padding(24).presentationDetents([.large]).presentationBackground(background)
    }

    private func detailRow(_ title: String, icon: String, subtitle: String) -> some View {
        Button { section = DetailSection(id: title) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24).foregroundStyle(accent)
                Text(title).font(T.label(14)); Spacer(minLength: 4)
                Text(draft.selections[title]?.isEmpty == false ? "\(draft.selections[title]!.count) added" : subtitle).font(T.body(12)).foregroundStyle(secondary).lineLimit(2)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(secondary)
            }.frame(minHeight: 52)
        }.overlay(alignment: .bottom) { Rectangle().fill(foreground.opacity(0.09)).frame(height: 0.5) }
    }

    private func sectionEditor(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(title).font(T.title); Spacer(); Button("Done") { section = nil }.frame(minHeight: 44) }
            Text("Optional · sample choices for this preview").font(T.body(13)).foregroundStyle(secondary)
            ForEach(options(for: title), id: \.self) { option in
                Button {
                    var values = draft.selections[title] ?? []
                    if values.contains(option) { values.remove(option) } else { values.insert(option) }
                    draft.selections[title] = values
                } label: {
                    HStack { Text(option).font(T.body()); Spacer(); Image(systemName: draft.selections[title]?.contains(option) == true ? "checkmark.circle.fill" : "circle") }.frame(minHeight: 48)
                }
            }
            Spacer()
        }.padding(24).presentationDetents([.medium, .large]).presentationBackground(background).foregroundStyle(foreground).tint(accent)
    }

    private func options(for title: String) -> [String] {
        switch title {
        case "Photos": ["Sample visit photo"]
        case "Friends", "Go with": ["Alex (sample)", "Sam (sample)"]
        case "Lists": ["Weekend spots", "Coffee favorites"]
        case "Tags": ["Cozy", "Good for reading", "Coffee"]
        case "Useful details": ["Outdoor seating", "Dogs allowed", "Parking nearby", "Customize questions"]
        default: ["Coffee shop", "Cafe", "Bakery"]
        }
    }

    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 18, content: content).padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading) }.scrollIndicators(.hidden)
    }
    private func back(_ label: String, to destination: String) -> some View {
        Button { route = destination } label: { Label(label, systemImage: "chevron.left").font(T.label(14)).frame(minHeight: 44) }.foregroundStyle(accent)
    }
    private func navigationRow(_ title: String, subtitle: String, icon: String, count: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).frame(width: 28).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 5) { Text(title).font(T.label(16)); Text(subtitle).font(T.body(13)).foregroundStyle(secondary) }
                Spacer(minLength: 0)
                if let count { Text(count).font(T.body(14)).foregroundStyle(secondary) }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(secondary)
            }.padding(17).frame(minHeight: 74).background(surface, in: RoundedRectangle(cornerRadius: 18))
        }
    }
    private func stat(_ value: String, _ label: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(value).font(T.label(20)); Text(label).font(T.body(12)).foregroundStyle(secondary) } }
    private func placeGlyph(_ symbol: String, size: CGFloat) -> some View { Image(systemName: symbol).font(.system(size: size * 0.37)).frame(width: size, height: size).foregroundStyle(accent).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14)) }
    private func chip(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) { Image(systemName: icon); Text(title).font(T.label(12)).fixedSize(horizontal: false, vertical: true); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }.padding(.horizontal, 12).frame(minHeight: 44).background(surface, in: Capsule())
    }
    private func primary(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(T.label(16)).frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(T.ink).background(T.coral, in: RoundedRectangle(cornerRadius: 17)) }
    }
    private func ratingText(_ visit: PreviewVisit) -> String { visit.rating.value.map { String(format: "%g / 5", $0) } ?? "Not rated" }
    private func startCapture(wanna isWanna: Bool) {
        draft = isWanna ? .wanna : PreviewVisit(id: UUID().uuidString, time: "Now")
        originalDraft = draft; editing = false; expanded = false
        detent = typeSize.isAccessibilitySize ? .large : .height(445); showingCapture = true
    }
    private func edit(_ visit: PreviewVisit) {
        draft = visit; originalDraft = visit; selectedID = visit.id
        editing = true; expanded = true; detent = .large; showingCapture = true
    }
    private func save() {
        if !editing { draft.quickCapture = !expanded }
        if editing { draft.invitationDismissed = true }
        if draft.time == "Now" { draft.time = "Today, 9:41 AM" }
        if draft.isWanna { wanna = draft } else { history.save(draft); selectedID = draft.id }
        changed = editing; saved = true; showingCapture = false; showInvitation = false
        route = editing ? (draft.isWanna ? "wanna-detail" : "visit") : "map"
    }
    private func undoSave() { if !draft.isWanna { history.visits.removeAll { $0.id == draft.id } }; saved = false; changed = false }
    private func closeEditor() { if draft != originalDraft { discardAlert = true } else { showingCapture = false } }
    private func openReminder() {
        // A notification references its original event, never whichever visit is latest.
        guard let visit = history.visits.first(where: { $0.id == "visit-juniper-today" }) else { unavailableReminder = true; return }
        edit(visit)
    }
    private func dismissInvitation() { var visit = recent; visit.invitationDismissed = true; history.save(visit); showInvitation = false }
    private struct DetailSection: Identifiable { let id: String }
}
