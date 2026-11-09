import SwiftUI
import MapKit

// Design-only native harness. Sample data, in-memory state, no account or backend.
// Palette and typography mirror DESIGN.md and AstirVisualSystem.swift.
private enum T {
    static let coral = Color(red: 240/255, green: 90/255, blue: 60/255)
    static let ink = Color(red: 20/255, green: 23/255, blue: 20/255)
    static let paper = Color(red: 242/255, green: 233/255, blue: 219/255)
    static func body(_ size: CGFloat = 16) -> Font { .custom("AvenirNext-Regular", size: size, relativeTo: .body) }
    static func label(_ size: CGFloat = 15) -> Font { .custom("AvenirNext-DemiBold", size: size, relativeTo: .body) }
    static let title = Font.system(.title, design: .serif).weight(.semibold)
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

private struct VisitDraft {
    var rating: Double? = nil
    var note = ""
    var time = "Now"
    var audience = "Friends"
    var silent = false
    var selections: [String: Set<String>] = [:]
}

struct QuickCapturePreview: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft = VisitDraft()
    @State private var wannaDraft = VisitDraft(time: "Anytime")
    @State private var isWanna = false
    @State private var showingCapture = false
    @State private var expanded = false
    @State private var saved = false
    @State private var editing = false
    @State private var section: String?
    @State private var detent: PresentationDetent = .height(445)
    @State private var selectedDate = Date()
    @State private var showingDate = false
    @State private var toast = false

    init() {
        let args = CommandLine.arguments
        let screen = args.firstIndex(of: "--screen").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "quick"
        let isExpanded = screen == "details" || screen == "edit"
        _isWanna = State(initialValue: screen == "wanna")
        _expanded = State(initialValue: isExpanded)
        _editing = State(initialValue: screen == "edit")
        _saved = State(initialValue: screen == "saved")
        _draft = State(initialValue: VisitDraft(time: ["saved", "later", "edit"].contains(screen) ? "Today, 2:15 PM" : "Now"))
        _detent = State(initialValue: isExpanded || args.contains("--large-text") ? .large : .height(445))
    }

    private let coordinate = CLLocationCoordinate2D(latitude: 34.0011, longitude: -118.4825)
    private var background: Color { scheme == .dark ? T.ink : T.paper }
    private var foreground: Color { scheme == .dark ? T.paper : T.ink }
    private var surface: Color { scheme == .dark ? Color(red: 27/255, green: 31/255, blue: 27/255) : Color(red: 251/255, green: 246/255, blue: 237/255) }
    private var secondary: Color { scheme == .dark ? Color(red: 152/255, green: 149/255, blue: 141/255) : Color(red: 101/255, green: 95/255, blue: 87/255) }
    private var accentText: Color { scheme == .dark ? T.coral : Color(red: 178/255, green: 54/255, blue: 32/255) }
    private var current: Binding<VisitDraft> { isWanna ? $wannaDraft : $draft }

    var body: some View {
        ZStack(alignment: .top) {
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))) {
                Annotation("Juniper Coffee", coordinate: coordinate) {
                    Image(systemName: "cup.and.saucer.fill").font(.title3)
                        .padding(13).foregroundStyle(T.ink).background(T.coral, in: Circle())
                        .overlay(Circle().stroke(T.paper, lineWidth: 3))
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Text("ASTIR").font(.system(size: 24, weight: .medium, design: .serif)).tracking(2)
                    Spacer()
                    Image(systemName: "magnifyingglass").frame(width: 44, height: 44)
                }.padding(.horizontal, 18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 25))
                Spacer()
                if saved { savedCard }
                else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Juniper Coffee").font(T.title)
                        Text("Coffee shop · Ocean Park").font(T.body(14)).foregroundStyle(secondary)
                        HStack {
                            primary("Check in", icon: "checkmark.circle") { openCapture(wanna: false) }
                            Button { openCapture(wanna: true) } label: {
                                Label("Wanna", systemImage: "bookmark").font(T.label()).frame(minHeight: 52).padding(.horizontal, 18)
                            }.background(surface, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }.padding(20).background(background, in: RoundedRectangle(cornerRadius: 28))
                }
                HStack {
                    ForEach([("Map", "map"), ("Add", "plus"), ("Discover", "sparkle.magnifyingglass"), ("Profile", "person.crop.circle")], id: \.0) { item in
                        Button { if item.0 == "Add" { openCapture(wanna: false) } } label: {
                            VStack(spacing: 4) { Image(systemName: item.1); Text(item.0).font(T.label(10)) }
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                    }
                }.padding(6).background(.regularMaterial, in: Capsule())
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
        }
        .foregroundStyle(foreground).tint(accentText).buttonStyle(.plain)
        .sheet(isPresented: $showingCapture) { captureSheet }
        .task {
            if !saved { showingCapture = true }
        }
    }

    private var captureSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(editing ? (isWanna ? "Your Wanna" : "Your check-in") : (isWanna ? "Wanna go" : "Check in"))
                                .font(T.label(13)).foregroundStyle(accentText)
                            Text("Juniper Coffee").font(T.title)
                            Text("Coffee shop · Ocean Park").font(T.body(14)).foregroundStyle(secondary)
                        }
                        Spacer(minLength: 6)
                        Button { showingCapture = false } label: {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                                .frame(width: 44, height: 44).background(surface, in: Circle())
                        }.accessibilityLabel("Close")
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { timeControl; audienceControl }
                        VStack(alignment: .leading, spacing: 10) { timeControl; audienceControl }
                    }
                    if !expanded {
                        Label(current.wrappedValue.silent ? "Silent save" : "Notifications on", systemImage: current.wrappedValue.silent ? "bell.slash" : "bell")
                            .font(T.body(12)).foregroundStyle(secondary).padding(.top, -10)
                    }
                    if expanded {
                        details
                    } else {
                        Divider().overlay(foreground.opacity(0.12))
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { expanded = true; detent = .large }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.pencil").font(.title3).foregroundStyle(accentText)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Add details").font(T.label())
                                    Text(isWanna ? "Notes, lists, people & more" : "Rating, photos, people & more")
                                        .font(T.body(13)).foregroundStyle(secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(secondary)
                            }.frame(minHeight: 54).contentShape(Rectangle())
                        }.accessibilityIdentifier("capture.addDetails")
                    }
                }.padding(22)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    primary(editing ? "Save changes" : (isWanna ? "Save to Wanna" : "Check in"), icon: isWanna ? "bookmark" : "checkmark") { save() }
                        .accessibilityIdentifier("capture.save")
                    Text(editing ? (isWanna ? "Updates this Wanna." : "Updates this visit. No new check-in.") : "Add anything else whenever you like.")
                        .font(T.body(12)).foregroundStyle(secondary).multilineTextAlignment(.center)
                }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 14).background(background)
            }
            .background(background)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingDate) { datePicker }
            .sheet(item: Binding(get: { section.map(DetailSection.init) }, set: { section = $0?.id })) { item in
                sectionEditor(item.id)
            }
        }
        .presentationDetents([.height(445), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .presentationBackground(background)
        .foregroundStyle(foreground).tint(accentText)
        .dynamicTypeSize(CommandLine.arguments.contains("--large-text") ? .accessibility1 : .large)
    }

    private var timeControl: some View {
        Menu {
            if !isWanna {
                Button("Now") { draft.time = "Now" }
                Button("An hour ago") { draft.time = "An hour ago" }
            } else { Button("Anytime") { wannaDraft.time = "Anytime" } }
            Button("Choose date and time") { showingDate = true }
        } label: { chip(current.wrappedValue.time, icon: "calendar") }
    }

    private var audienceControl: some View {
        Menu {
            Picker("Who can see this?", selection: current.audience) {
                Text("Everyone (followers)").tag("Everyone")
                Text("Friends (mutual follows)").tag("Friends")
                Text("Self (only me)").tag("Self")
            }
            Toggle("Silent save", isOn: current.silent)
        } label: { chip(current.wrappedValue.audience + (current.wrappedValue.silent ? " · Silent" : ""), icon: current.wrappedValue.audience == "Self" ? "lock" : "person.2") }
        .accessibilityLabel("Audience: \(current.wrappedValue.audience). \(current.wrappedValue.silent ? "Silent save" : "Notifications on"). Change audience or notifications.")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Make it yours").font(.system(.title3, design: .serif).weight(.semibold))
                Spacer()
                Text("All optional").font(T.body(12)).foregroundStyle(secondary)
            }
            if !isWanna {
                Button { section = "Rating" } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Your rating").font(T.label())
                            HStack(spacing: 12) {
                                ForEach(1...5, id: \.self) { n in
                                    Image(systemName: Double(n) <= (draft.rating ?? 0) ? "star.fill" : "star")
                                        .foregroundStyle(draft.rating == nil ? secondary : accentText)
                                }
                            }.font(.title3)
                        }
                        Spacer()
                        Text(draft.rating.map { String(format: "%g / 5", $0) } ?? "Not rated")
                            .font(T.body(13)).foregroundStyle(secondary)
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }.padding(16).background(surface, in: RoundedRectangle(cornerRadius: 18))
                }.accessibilityLabel(draft.rating.map { "Rating \($0) out of 5. Edit" } ?? "Not rated. Add a rating")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(isWanna ? "What caught your eye?" : "Anything to remember?").font(T.label())
                TextField(isWanna ? "A recommendation, a dish to try…" : "A good table, a favorite order…", text: current.note, axis: .vertical)
                    .font(T.body(14)).lineLimit(2...4).padding(14)
                    .background(surface, in: RoundedRectangle(cornerRadius: 16))
            }
            VStack(spacing: 0) {
                if !isWanna { detailRow("Photos", icon: "photo", subtitle: "Add a photo") }
                detailRow(isWanna ? "Go with" : "Friends", icon: "person.2", subtitle: isWanna ? "Plan with people" : "Who was there?")
                detailRow("Lists", icon: "list.bullet.rectangle", subtitle: "Add to a list")
                detailRow("Tags", icon: "tag", subtitle: "Describe the place")
                if !isWanna { detailRow("Useful details", icon: "slider.horizontal.3", subtitle: "Your questions & answers") }
                detailRow("Place type", icon: "cup.and.saucer", subtitle: "Coffee shop")
            }
            Toggle("Silent save", isOn: current.silent).font(T.body(14)).tint(accentText)
            Text("Visibility: \(current.wrappedValue.audience). Silent saves keep the same audience.")
                .font(T.body(12)).foregroundStyle(secondary)
        }
    }

    private func detailRow(_ title: String, icon: String, subtitle: String) -> some View {
        Button { section = title } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24).foregroundStyle(accentText)
                Text(title).font(T.label(14))
                Spacer(minLength: 4)
                Text(current.wrappedValue.selections[title]?.isEmpty == false ? "\(current.wrappedValue.selections[title]!.count) added" : subtitle)
                    .font(T.body(12)).foregroundStyle(secondary).lineLimit(2)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(secondary)
            }.frame(minHeight: 52).contentShape(Rectangle())
        }.overlay(alignment: .bottom) { Rectangle().fill(foreground.opacity(0.09)).frame(height: 0.5) }
    }

    private var savedCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(accentText)
                Text(toast ? "Changes saved" : (isWanna ? "Saved to Wanna" : "Checked in")).font(T.label(14))
                Spacer()
                Button("Undo") { saved = false; editing = false; draft = VisitDraft() }.font(T.label(13))
            }
            Text("Juniper Coffee").font(T.title)
            HStack {
                Text(isWanna ? "Anytime" : draft.time).font(T.body(13))
                Text("·").foregroundStyle(secondary)
                Label(current.wrappedValue.audience, systemImage: "person.2").font(T.body(13))
            }.foregroundStyle(secondary)
            if !current.wrappedValue.note.isEmpty { Text(current.wrappedValue.note).font(T.body(14)) }
            HStack {
                Text(isWanna ? "A place for another day" : (draft.rating.map { String(format: "%g / 5", $0) } ?? "Not rated"))
                    .font(T.body(13)).foregroundStyle(secondary)
                Spacer()
                Button { editing = true; expanded = true; detent = .large; showingCapture = true } label: {
                    Label("Add details", systemImage: "square.and.pencil").font(T.label(14)).frame(minHeight: 44)
                }.foregroundStyle(accentText).accessibilityIdentifier("capture.enrich")
            }
        }.padding(22).background(background, in: RoundedRectangle(cornerRadius: 28))
    }

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(isWanna ? "When would you like to go?" : "When was your visit?").font(T.title)
            if isWanna {
                DatePicker("Planned date", selection: $selectedDate, in: Date()..., displayedComponents: [.date]).datePickerStyle(.graphical)
            } else {
                DatePicker("Visit date and time", selection: $selectedDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
            }
            primary("Use this date", icon: "checkmark") {
                current.wrappedValue.time = selectedDate.formatted(date: .abbreviated, time: isWanna ? .omitted : .shortened)
                showingDate = false
            }
        }.padding(24).presentationDetents([.large]).presentationBackground(background)
    }

    private func sectionEditor(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Text(title).font(T.title); Spacer(); Button("Done") { section = nil }.frame(minHeight: 44) }
            if title == "Rating" {
                Text("Choose a rating for this visit.").font(T.body())
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(stride(from: 1.0, through: 5.0, by: 0.5)), id: \.self) { value in
                        Button { draft.rating = value; section = nil } label: {
                            Text(String(format: "%g", value)).font(T.label(18)).frame(maxWidth: .infinity, minHeight: 52)
                                .background(draft.rating == value ? T.coral : surface, in: RoundedRectangle(cornerRadius: 14))
                        }.accessibilityLabel("\(value) out of 5")
                    }
                }
                Button("Remove rating") { draft.rating = nil; section = nil }.frame(minHeight: 44)
            } else {
                Text("Optional · sample choices for this preview").font(T.body(13)).foregroundStyle(secondary)
                ForEach(options(for: title), id: \.self) { option in
                    Button {
                        var choices = current.wrappedValue.selections[title] ?? []
                        if choices.contains(option) { choices.remove(option) } else { choices.insert(option) }
                        current.wrappedValue.selections[title] = choices
                    } label: {
                        HStack {
                            Text(option).font(T.body())
                            Spacer()
                            Image(systemName: current.wrappedValue.selections[title]?.contains(option) == true ? "checkmark.circle.fill" : "circle")
                        }.frame(minHeight: 48)
                    }
                }
            }
            Spacer()
        }.padding(24).presentationDetents([.medium, .large]).presentationBackground(background)
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

    private func chip(_ text: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
            Text(text).font(T.label(13)).fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }.padding(.horizontal, 13).frame(minHeight: 44).background(surface, in: Capsule())
    }

    private func primary(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(T.label(16)).frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(T.ink).background(T.coral, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func openCapture(wanna: Bool) { isWanna = wanna; editing = false; expanded = false; detent = typeSize.isAccessibilitySize ? .large : .height(445); showingCapture = true }
    private func save() { toast = editing; saved = true; showingCapture = false }
    private struct DetailSection: Identifiable { let id: String }
}
