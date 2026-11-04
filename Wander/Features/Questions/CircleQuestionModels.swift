import Combine
import CoreLocation
import Foundation

struct CircleQuestionArea: Codable, Equatable {
    var name: String
    var detail: String
    var latitude: Double
    var longitude: Double
    var city: String?
    var region: String?
    var countryCode: String?
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct CircleQuestionPerson: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var hometown: String?
    var isFriend: Bool = false
}

struct CircleQuestionDraft: Codable, Equatable {
    enum Audience: String, Codable { case all, hometown, people }
    var id = UUID()
    // Empty means Everything; it is exclusive of specific categories.
    var categories: [String] = []
    var subcategories: [String] = []
    var area: CircleQuestionArea?
    var note = ""
    var audience: Audience = .all
    var recipientIDs: [String] = []
    var stealth = false
    var days = 7

    static func categoryTitle(_ id: String) -> String {
        WanderPlaceCategory.taxonomy.first { $0.id == id }?.group ?? id
    }
    var topic: String {
        if categories.isEmpty { return "everything" }
        if !subcategories.isEmpty { return subcategories.joined(separator: ", ").lowercased() }
        return categories.map { Self.categoryTitle($0).lowercased() }.joined(separator: ", ")
    }
    var headline: String { "Looking for \(topic)\n in \(area?.name ?? "…")".replacingOccurrences(of: "\n in", with: "\nin") }
    var isValid: Bool {
        guard let area, !area.name.isEmpty, area.latitude.isFinite, area.longitude.isFinite,
              (-90...90).contains(area.latitude), (-180...180).contains(area.longitude),
              (1...30).contains(days), note.unicodeScalars.count <= 1000,
              !note.unicodeScalars.contains(where: { $0.value == 0 }) else { return false }
        return (!stealth && audience == .all) || !recipientIDs.isEmpty
    }
    mutating func toggleCategory(_ id: String) {
        if categories.contains(id) { categories.removeAll { $0 == id } } else { categories.append(id) }
        let valid = Set(categories.flatMap { WanderPlaceCategory.subcategorySuggestions(for: $0) })
        subcategories.removeAll { !valid.contains($0) }
    }
    mutating func selectEverything() { categories = []; subcategories = [] }
}

struct CircleQuestionPlace: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var detail: String
    var latitude: Double
    var longitude: Double
    var note = ""

    init(id: String, name: String, detail: String, latitude: Double, longitude: Double, note: String = "") {
        self.id = id; self.name = name; self.detail = detail
        self.latitude = latitude; self.longitude = longitude; self.note = note
    }
    init?(_ candidate: PlaceCandidate) {
        guard let lat = candidate.latitude, let lon = candidate.longitude else { return nil }
        self.init(id: candidate.sourceProviderPlaceID ?? candidate.id, name: candidate.name,
                  detail: candidate.address ?? candidate.locality ?? candidate.category, latitude: lat, longitude: lon)
    }
    init(_ visible: VisiblePlace) {
        let place = visible.place
        self.init(id: place.id, name: place.canonicalName, detail: place.address ?? place.locality ?? "",
                  latitude: place.latitude, longitude: place.longitude)
    }
    // A result can appear in search and several lists with different local IDs.
    var selectionKey: String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        + "|\(Int((latitude * 10_000).rounded()))|\(Int((longitude * 10_000).rounded()))"
    }
}

struct CircleQuestionBasket: Equatable {
    private(set) var places: [CircleQuestionPlace] = []
    func contains(_ place: CircleQuestionPlace) -> Bool { places.contains { $0.selectionKey == place.selectionKey } }
    mutating func toggle(_ place: CircleQuestionPlace) {
        if contains(place) { places.removeAll { $0.selectionKey == place.selectionKey } }
        else if places.count < 50 { places.append(place) }
    }
    mutating func selectAll(_ values: [CircleQuestionPlace]) {
        for place in values where !contains(place) && places.count < 50 { places.append(place) }
    }
    mutating func remove(_ key: String) { places.removeAll { $0.selectionKey == key } }
    mutating func setNote(_ text: String, for key: String) {
        guard let index = places.firstIndex(where: { $0.selectionKey == key }) else { return }
        places[index].note = String(text.prefix(1000))
    }
}

struct CircleQuestionReply: Codable, Equatable, Identifiable {
    var id: UUID
    var author: CircleQuestionPerson
    var note: String
    var places: [CircleQuestionPlace]
    var createdAt: Date
}

struct CircleQuestion: Codable, Equatable, Identifiable {
    var id: UUID { draft.id }
    var draft: CircleQuestionDraft
    var author: CircleQuestionPerson
    var createdAt: Date
    var expiresAt: Date
    var likes: Int = 0
    var liked = false
    var replies: [CircleQuestionReply] = []
    func isOnMap(at now: Date) -> Bool { expiresAt > now }
}

@MainActor protocol CircleQuestionRepository {
    func question(id: UUID) async throws -> CircleQuestion
    func inbox() async throws -> [CircleQuestionInboxItem]
    func markRead(id: UUID) async throws
    func questions() async throws -> [CircleQuestion]
    func publish(_ draft: CircleQuestionDraft) async throws -> CircleQuestion
    func reply(questionID: UUID, clientID: UUID, places: [CircleQuestionPlace], note: String) async throws -> CircleQuestion
    func setLike(questionID: UUID, liked: Bool) async throws -> CircleQuestion
}

struct CircleQuestionInboxItem: Codable, Identifiable {
    var question: CircleQuestion
    var isRead: Bool
    var id: UUID { question.id }
}

extension CircleQuestionRepository {
    func question(id: UUID) async throws -> CircleQuestion {
        guard let item = try await questions().first(where: { $0.id == id }) else { throw WanderRemoteError.notConfigured }
        return item
    }
    func inbox() async throws -> [CircleQuestionInboxItem] { [] }
    func markRead(id: UUID) async throws {}
}

@MainActor final class CircleQuestionStore: ObservableObject {
    @Published private(set) var items: [CircleQuestion] = []
    @Published private(set) var isBusy = false
    @Published var message: String?
    private var ownerID: String?
    private var generation = UUID()
    private var trackedRequests = Set<UUID>()
    private var loadID = UUID()
    var analytics: any AnalyticsClient = NoopAnalyticsClient()
    enum Success { case posted, answered }
    var repository: (any CircleQuestionRepository)?

    init(repository: (any CircleQuestionRepository)? = nil) { self.repository = repository }
    func reset(userID: String) {
        guard ownerID != userID else { return }
        ownerID = userID; generation = UUID(); items = []; message = nil; isBusy = false; trackedRequests = []
    }
    func load(userID: String) async {
        reset(userID: userID)
        guard let repository else { return }
        let request = generation
        let currentLoad = UUID(); loadID = currentLoad
        do {
            let result = try await repository.questions()
            guard request == generation, currentLoad == loadID else { return }
            items = result
        } catch { if request == generation, currentLoad == loadID { items = []; message = "Questions couldn’t refresh. Try again." } }
    }
    func refreshQuestion(id: UUID) async -> CircleQuestion? {
        guard let repository else { return nil }
        let request = generation
        do {
            let question = try await repository.question(id: id)
            guard request == generation else { return nil }
            items.removeAll { $0.id == id }; items.append(question); items.sort { $0.createdAt > $1.createdAt }
            return question
        } catch {
            if request == generation { items.removeAll { $0.id == id } }
            return nil
        }
    }
    func perform(event: Success? = nil, requestID: UUID? = nil, _ action: @MainActor (any CircleQuestionRepository) async throws -> CircleQuestion) async -> Bool {
        guard !isBusy else { return false }
        guard let repository else { message = "Questions aren’t connected yet. Your draft is still here."; return false }
        let request = generation
        isBusy = true; message = nil
        defer { if request == generation { isBusy = false } }
        do {
            let question = try await action(repository)
            guard request == generation else { return false }
            loadID = UUID()
            items.removeAll { $0.id == question.id }; items.append(question)
            items.sort { $0.createdAt > $1.createdAt }
            if let event, let requestID, trackedRequests.insert(requestID).inserted {
                analytics.track(AnalyticsEvent(name: event == .posted ? WanderAnalyticsEvents.circleQuestionPosted : WanderAnalyticsEvents.circleQuestionAnswered, properties: [:]))
                analytics.track(.engagement(need: event == .posted ? .expression : .connect,
                    action: event == .posted ? .questionAsked : .questionAnswered, surface: "live"))
            }
            return true
        } catch {
            if request == generation { message = "Couldn’t confirm that change. Your draft is kept here; try again." }
            return false
        }
    }
}

@MainActor final class SupabaseCircleQuestionRepository: CircleQuestionRepository {
    private let rpc: any RemoteProcedureCalling
    init(rpc: any RemoteProcedureCalling) { self.rpc = rpc }
    func question(id: UUID) async throws -> CircleQuestion {
        try await rpc.call("circle_question", params: ID(input_question_id: id))
    }
    func inbox() async throws -> [CircleQuestionInboxItem] {
        try await rpc.call("circle_question_inbox", params: Empty())
    }
    func markRead(id: UUID) async throws {
        let _: EmptyRPCResponse = try await rpc.call("circle_question_read", params: ID(input_question_id: id))
    }
    private struct ID: Encodable { let input_question_id: UUID }
    func questions() async throws -> [CircleQuestion] {
        try await rpc.call("circle_questions", params: Empty())
    }
    func publish(_ draft: CircleQuestionDraft) async throws -> CircleQuestion {
        guard draft.isValid else { throw WanderRemoteError.notConfigured }
        return try await rpc.call("circle_question_publish", params: Publish(input_draft: draft))
    }
    func reply(questionID: UUID, clientID: UUID, places: [CircleQuestionPlace], note: String) async throws -> CircleQuestion {
        try await rpc.call("circle_question_reply", params: Reply(input_question_id: questionID,
            input_client_id: clientID, input_places: places, input_note: note))
    }
    func setLike(questionID: UUID, liked: Bool) async throws -> CircleQuestion {
        try await rpc.call("circle_question_like", params: Like(input_question_id: questionID, input_liked: liked))
    }
    private struct Empty: Encodable {}
    private struct Publish: Encodable { let input_draft: CircleQuestionDraft }
    private struct Reply: Encodable {
        let input_question_id: UUID; let input_client_id: UUID; let input_places: [CircleQuestionPlace]; let input_note: String
    }
    private struct Like: Encodable { let input_question_id: UUID; let input_liked: Bool }
}
