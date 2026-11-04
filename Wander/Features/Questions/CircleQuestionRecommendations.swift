import SwiftUI
import MapKit

struct CircleQuestionRecommendations: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.astirBrandMode) private var brand
    @ObservedObject var state: CircleQuestionStore
    let question: CircleQuestion
    var onCompleted: () -> Void = {}
    @State private var source = "Quick picks"
    @State private var query = ""
    @State private var results: [CircleQuestionPlace] = []
    @State private var basket = CircleQuestionBasket()
    @State private var loading = false
    @State private var failed = false
    @State private var next = false
    private var quick: [CircleQuestionPlace] { Array(store.visiblePlaces(for: store.currentUser.id).prefix(30)).map(CircleQuestionPlace.init) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("You know a place.\nOr a few.").font(.system(.largeTitle, design: .serif).weight(.semibold))
                Text("Pick your recommendations. Add a little local knowledge next.").font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                Picker("Find places", selection: $source) {
                    Text("Quick picks").tag("Quick picks"); Text("Search").tag("Search"); Text("Lists").tag("Lists")
                }.pickerStyle(.segmented)
                if basket.places.count == 50 {
                    Text("50 places selected. Send these first, then add more to the question.")
                        .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                }
                if source == "Search" {
                    TextField("Search places", text: $query).textFieldStyle(.roundedBorder).submitLabel(.search)
                    if loading { ProgressView("Finding places…") }
                    if failed { Text("Couldn’t search places. Try again.").font(AstirTypography.bodySmall) }
                    ForEach(results) { row($0) }
                    if !loading && !query.isEmpty && results.isEmpty && !failed { Text("No places found. Try another search.").font(AstirTypography.bodySmall) }
                } else if source == "Lists" {
                    if store.visiblePlaceLists.isEmpty { Text("Your saved lists will appear here.").font(AstirTypography.body) }
                    ForEach(store.visiblePlaceLists) { list in
                        let places = store.visiblePlaces(in: list).map(CircleQuestionPlace.init)
                        DisclosureGroup {
                            Button("Select all \(places.count) places") { basket.selectAll(places) }
                                .font(AstirTypography.control).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            ForEach(places) { row($0) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.name).font(AstirTypography.cardTitle)
                                Text("\(places.count) places · Choose all or a few").font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                            }.padding(.vertical, 12)
                        }
                        Divider()
                    }
                } else {
                    Text("From your map").font(AstirTypography.sectionTitle)
                    if quick.isEmpty { Text("Search for a place or choose from a list.").font(AstirTypography.body) }
                    ForEach(quick) { row($0) }
                }
            }.padding(22)
        }.astirScreen().navigationTitle("Recommend places").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                CircleQuestionAction(title: "Next · \(basket.places.count) selected", disabled: basket.places.isEmpty) { next = true }
                    .padding(18).background(brand.background)
            }
            .navigationDestination(isPresented: $next) {
                CircleQuestionKnowledge(state: state, question: question, onFinish: onCompleted, basket: $basket)
            }
            .task(id: query) {
                results = []; failed = false
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { loading = false; return }
                loading = true
                do {
                    try await Task.sleep(for: .milliseconds(350))
                    let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query; request.resultTypes = [.pointOfInterest]
                    if let area = question.draft.area { request.region = .init(center: area.coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000) }
                    let response = try await MKLocalSearch(request: request).start()
                    guard !Task.isCancelled else { return }
                    results = response.mapItems.map { item in
                        CircleQuestionPlace(id: "\(item.name ?? "")|\(item.placemark.coordinate.latitude)|\(item.placemark.coordinate.longitude)",
                            name: item.name ?? "Place", detail: item.placemark.title ?? "", latitude: item.placemark.coordinate.latitude,
                            longitude: item.placemark.coordinate.longitude)
                    }; loading = false
                } catch { if !Task.isCancelled { failed = true; loading = false } }
            }
    }
    private func row(_ place: CircleQuestionPlace) -> some View {
        Button { basket.toggle(place) } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse").frame(width: 42, height: 46)
                    .background(CircleQuestionStyle.lilac.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(place.name).font(AstirTypography.cardTitle).foregroundStyle(brand.primaryText)
                    Text(place.detail).font(AstirTypography.caption).foregroundStyle(brand.secondaryText).lineLimit(2)
                }
                Spacer()
                Image(systemName: basket.contains(place) ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(basket.contains(place) ? brand.accentText : brand.secondaryText)
            }.padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("circleQuestion.place.\(place.selectionKey)").accessibilityAddTraits(basket.contains(place) ? [.isSelected] : [])
    }
}

struct CircleQuestionKnowledge: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brand
    @ObservedObject var state: CircleQuestionStore
    let question: CircleQuestion
    var onFinish: () -> Void = {}
    @Binding var basket: CircleQuestionBasket
    @State private var note = ""
    @State private var clientID = UUID()
    @State private var sent = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(sent ? "Good places, passed on." : "A little local\nknowledge.").font(.system(.largeTitle, design: .serif).weight(.semibold))
                Text(sent ? "Your recommendations are on the question." : "The order, the quiet corner, the best time to go. Add a note if you like.")
                    .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                ForEach(basket.places) { place in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(place.name).font(AstirTypography.cardTitle)
                                Text(place.detail).font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                            }
                            Spacer()
                            if !sent {
                                Button { basket.remove(place.selectionKey) } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                                    .accessibilityLabel("Remove \(place.name)")
                            }
                        }
                        if !sent {
                            TextField("Your tip for this place · Optional", text: Binding(get: {
                                basket.places.first { $0.selectionKey == place.selectionKey }?.note ?? ""
                            }, set: { basket.setNote($0, for: place.selectionKey) }), axis: .vertical)
                                .font(AstirTypography.body).lineLimit(2...4)
                        }
                    }.padding(18).background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 20))
                }
                if !sent {
                    TextField("Anything else? · Optional", text: $note, axis: .vertical).font(AstirTypography.body).lineLimit(2...4)
                        .onChange(of: note) { _, value in if value.count > 1000 { note = String(value.prefix(1000)) } }
                    if let message = state.message { Text(message).font(AstirTypography.bodySmall).foregroundStyle(brand.accentText) }
                    CircleQuestionAction(title: state.isBusy ? "Sending…" : "Send \(basket.places.count) recommendations", disabled: basket.places.isEmpty || state.isBusy) {
                        Task {
                            sent = await state.perform(event: .answered, requestID: clientID) { try await $0.reply(questionID: question.id, clientID: clientID, places: basket.places, note: note) }
                        }
                    }
                }
            }.padding(22)
        }.astirScreen().navigationTitle(sent ? "Sent" : "Your recommendations").navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(sent).toolbar {
                if sent { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onFinish) } }
            }
    }
}
