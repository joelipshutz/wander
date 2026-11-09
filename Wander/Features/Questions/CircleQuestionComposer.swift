import SwiftUI
import MapKit

enum CircleQuestionStyle {
    static let lilac = Color(red: 0.76, green: 0.69, blue: 0.96)
    static let plum = Color(red: 0.27, green: 0.18, blue: 0.43)
    static let headline = Font.system(.title, design: .serif).weight(.semibold)
}

struct CircleQuestionPin: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        // Match the Live place tile's 29 × 40 body, 10pt footing and 44pt target.
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CircleQuestionStyle.lilac)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.35) : CircleQuestionStyle.plum.opacity(0.2), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.23), radius: 2, y: 2)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CircleQuestionStyle.plum)
                .mask(alignment: .bottom) { Rectangle().frame(height: 10) }
            Image(systemName: "questionmark")
                .resizable().scaledToFit().font(.system(size: 20, weight: .medium))
                .foregroundStyle(CircleQuestionStyle.plum)
                .frame(width: 20, height: 20).frame(width: 29, height: 30).offset(y: -5)
        }.frame(width: 29, height: 40).frame(width: 44, height: 44)
            .accessibilityLabel("Question")
    }
}

struct CircleQuestionAction: View {
    @Environment(\.astirBrandMode) private var brand
    let title: String
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Image(systemName: "arrow.right") }
                .font(AstirTypography.control).padding(18)
                .foregroundStyle(Color.white).background(brand.accent, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.45 : 1)
    }
}

struct CircleQuestionComposer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brand
    @ObservedObject var state: CircleQuestionStore
    let author: CircleQuestionPerson
    let people: [CircleQuestionPerson]
    var onPosted: () -> Void = {}
    @State var draft = CircleQuestionDraft()
    @State private var picker: PickerPage?
    @State private var preview = false
    @State private var discard = false
    enum PickerPage: String, Identifiable { case category, subcategory, area, people, duration; var id: Self { self } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ask your circle.").font(.system(.largeTitle, design: .serif).weight(.semibold))
                            Text("for a recommendation")
                                .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Text("?").font(.system(size: 64, weight: .regular, design: .serif))
                            .foregroundStyle(CircleQuestionStyle.lilac).rotationEffect(.degrees(12))
                            .accessibilityHidden(true)
                    }
                    sentence
                    VStack(spacing: 0) {
                        setting("Direct the question", value: audienceLabel, symbol: "person.2") { picker = .people }
                        Divider()
                        setting("Time on the map", value: "\(draft.days) \(draft.days == 1 ? "day" : "days")", symbol: "clock") { picker = .duration }
                    }.padding(.horizontal, 18).background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 22))
                    CircleQuestionAction(title: "Done · Preview question", disabled: !draft.isValid) { preview = true }
                    Text("Good questions find good places.")
                        .font(.system(.callout, design: .serif).italic()).foregroundStyle(brand.secondaryText)
                        .frame(maxWidth: .infinity)
                }.padding(22)
            }.astirScreen().navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { discard = true } } }
                .confirmationDialog("Discard this question?", isPresented: $discard, titleVisibility: .visible) {
                    Button("Discard question", role: .destructive) { dismiss() }
                }
                .sheet(item: $picker) { page in
                    NavigationStack {
                        pickerContent(page).astirScreen().navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { picker = nil } } }
                    }.tint(brand.accentText)
                }
                .navigationDestination(isPresented: $preview) {
                    CircleQuestionPreview(state: state, draft: draft, author: author) { onPosted(); dismiss() }
                }
        }.tint(brand.accentText).interactiveDismissDisabled().sessionReplayMasked()
    }
    private var sentence: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Looking for").font(CircleQuestionStyle.headline)
            selectField(draft.categories.isEmpty ? "Everything" : draft.categories.map(CircleQuestionDraft.categoryTitle).joined(separator: ", "),
                        hint: "Choose categories", page: .category)
            if !draft.categories.isEmpty {
                selectField(draft.subcategories.isEmpty ? "Add subcategories" : draft.subcategories.joined(separator: ", "),
                            hint: "Optional", page: .subcategory)
            }
            Text("in").font(CircleQuestionStyle.headline)
            selectField(draft.area?.name ?? "Choose a city, state or country", hint: draft.area?.detail ?? "Where are you headed?", page: .area)
            Divider().padding(.vertical, 4)
            TextField("A little more about what you’re after…", text: $draft.note, axis: .vertical)
                .lineLimit(3...6).font(AstirTypography.body)
                .onChange(of: draft.note) { _, value in if value.count > 1000 { draft.note = String(value.prefix(1000)) } }
            Text("Optional · \(draft.note.count)/1,000").font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
        }.padding(22).background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 26))
            .overlay(alignment: .topLeading) {
                Capsule().fill(CircleQuestionStyle.lilac).frame(width: 48, height: 5).padding(.leading, 22)
            }
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(brand.border, lineWidth: 1))
    }
    private func selectField(_ title: String, hint: String, page: PickerPage) -> some View {
        Button { picker = page } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(AstirTypography.cardTitle).foregroundStyle(brand.primaryText)
                    Text(hint).font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                }
                Spacer(); Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }.padding(16).background(brand.recessedBackground, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
    private func setting(_ title: String, value: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(AstirTypography.control)
                    Text(value).font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption)
            }.foregroundStyle(brand.primaryText).padding(.vertical, 18)
        }.buttonStyle(.plain)
    }
    private var audienceLabel: String {
        let count = draft.recipientIDs.count
        if draft.stealth { return "Stealth · \(count) selected" }
        switch draft.audience {
        case .all: return "All followers"
        case .hometown: return "Friends in \(draft.area?.name ?? "this city")"
        case .people: return "\(count) people tagged · All followers can see"
        }
    }
    @ViewBuilder private func pickerContent(_ page: PickerPage) -> some View {
        switch page {
        case .category: CircleQuestionCategoryPicker(draft: $draft, subcategoriesOnly: false)
        case .subcategory: CircleQuestionCategoryPicker(draft: $draft, subcategoriesOnly: true)
        case .area: CircleQuestionAreaPicker { area in
            if draft.area != area && draft.audience == .hometown { draft.recipientIDs = [] }
            draft.area = area; picker = nil
        }
        case .people: CircleQuestionPeoplePicker(draft: $draft, people: people)
        case .duration:
            VStack(alignment: .leading, spacing: 24) {
                Text("Give your circle a little time.").font(CircleQuestionStyle.headline)
                Text("Your question stays in the feed. Choose how long its pin stays on the live map.").font(AstirTypography.body)
                Picker("Days on map", selection: $draft.days) {
                    ForEach(1...30, id: \.self) { day in Text("\(day) \(day == 1 ? "day" : "days")").tag(day) }
                }.pickerStyle(.wheel)
                Spacer()
            }.padding(24).navigationTitle("Time on the map")
        }
    }
}

struct CircleQuestionCategoryPicker: View {
    @Binding var draft: CircleQuestionDraft
    var subcategoriesOnly: Bool
    @State private var query = ""
    var body: some View {
        List {
            if subcategoriesOnly {
                ForEach(draft.categories, id: \.self) { category in
                    Section(CircleQuestionDraft.categoryTitle(category)) {
                        ForEach(WanderPlaceCategory.subcategorySuggestions(for: category).filter(matches), id: \.self) { value in
                            choice(value, selected: draft.subcategories.contains(value)) {
                                if draft.subcategories.contains(value) { draft.subcategories.removeAll { $0 == value } }
                                else { draft.subcategories.append(value) }
                            }
                        }
                    }
                }
            } else {
                choice("Everything", selected: draft.categories.isEmpty) { draft.selectEverything() }
                ForEach(WanderPlaceCategory.taxonomy.filter { $0.isEditable && matches($0.group) }, id: \.id) { category in
                    choice("\(category.emoji)  \(category.group)", selected: draft.categories.contains(category.id)) { draft.toggleCategory(category.id) }
                }
            }
        }.scrollContentBackground(.hidden).searchable(text: $query, prompt: "Search \(subcategoriesOnly ? "subcategories" : "categories")")
            .navigationTitle(subcategoriesOnly ? "Subcategories · Optional" : "What are you looking for?")
    }
    private func matches(_ text: String) -> Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }
    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Image(systemName: selected ? "checkmark.circle.fill" : "circle") }
                .font(AstirTypography.body).padding(.vertical, 8)
        }.accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct CircleQuestionAreaPicker: View {
    var select: (CircleQuestionArea) -> Void
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var loading = false
    @State private var failed = false
    var body: some View {
        List {
            if loading { ProgressView("Finding places…") }
            if failed { Text("Couldn’t search. Check your connection and try again.") }
            if !loading && !failed && !query.isEmpty && results.isEmpty { Text("No locations found. Try another name.") }
            ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                Button {
                    let p = item.placemark
                    select(.init(name: item.name ?? query, detail: [p.administrativeArea, p.country].compactMap { $0 }.joined(separator: ", "),
                                 latitude: p.coordinate.latitude, longitude: p.coordinate.longitude,
                                 city: p.locality, region: p.administrativeArea, countryCode: p.isoCountryCode))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name ?? query).font(AstirTypography.cardTitle)
                        Text([item.placemark.administrativeArea, item.placemark.country].compactMap { $0 }.joined(separator: ", "))
                            .font(AstirTypography.caption)
                    }.padding(.vertical, 7)
                }
            }
        }.scrollContentBackground(.hidden).navigationTitle("Where?")
            .searchable(text: $query, prompt: "City, state or country")
            .task(id: query) {
                results = []; failed = false
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { loading = false; return }
                loading = true
                do {
                    try await Task.sleep(for: .milliseconds(350))
                    let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query; request.resultTypes = [.address]
                    let response = try await MKLocalSearch(request: request).start()
                    guard !Task.isCancelled else { return }; results = response.mapItems; loading = false
                } catch { if !Task.isCancelled { failed = true; loading = false } }
            }
    }
}

struct CircleQuestionPeoplePicker: View {
    @Binding var draft: CircleQuestionDraft
    let people: [CircleQuestionPerson]
    @State private var query = ""
    private var localFriends: [CircleQuestionPerson] {
        guard let city = draft.area?.city else { return [] }
        return people.filter { $0.isFriend && $0.hometown?.localizedCaseInsensitiveCompare(city) == .orderedSame }
    }
    var body: some View {
        List {
            Section {
                Button { draft.audience = .all; draft.recipientIDs = []; draft.stealth = false } label: {
                    Label("All followers", systemImage: draft.audience == .all ? "checkmark.circle.fill" : "person.2")
                }.frame(minHeight: 44)
                Button {
                    draft.audience = .hometown; draft.recipientIDs = localFriends.map(\.id)
                } label: {
                    VStack(alignment: .leading) {
                        Text("Friends in \(draft.area?.city ?? "your selected city")")
                        Text("\(localFriends.count) friends · Matches their hometown").font(AstirTypography.caption)
                    }
                }.frame(minHeight: 44).disabled(localFriends.isEmpty)
            } footer: { Text("Tags direct the request with push and in-app notifications. All followers can still see it.") }
            Section {
                Toggle("Stealth", isOn: $draft.stealth).onChange(of: draft.stealth) { _, value in
                    if value && draft.audience == .all { draft.audience = .people }
                }
            } footer: { Text("Only you and the tagged people can see this question, its map pin and replies.") }
            Section("Choose people · \(draft.recipientIDs.count) selected") {
                ForEach(people.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { person in
                    Button {
                        draft.audience = .people
                        if draft.recipientIDs.contains(person.id) { draft.recipientIDs.removeAll { $0 == person.id } }
                        else { draft.recipientIDs.append(person.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) { Text(person.name); if let home = person.hometown { Text(home).font(AstirTypography.caption) } }
                            Spacer(); Image(systemName: draft.recipientIDs.contains(person.id) ? "checkmark.circle.fill" : "circle")
                        }.frame(minHeight: 44)
                    }
                }
            }
        }.font(AstirTypography.body).scrollContentBackground(.hidden).searchable(text: $query, prompt: "Find people")
            .navigationTitle("Direct your question")
    }
}
