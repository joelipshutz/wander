import Foundation

// Design fixtures only. A visual slider position is never a stored rating.
struct PreviewRating: Equatable {
    private(set) var value: Double?
    var sliderPosition: Double { value ?? 3 }
    mutating func select(_ score: Double) { value = min(5, max(1, (score * 2).rounded() / 2)) }
    mutating func beginInteraction() { if value == nil { select(sliderPosition) } }
    mutating func remove() { value = nil }
}

struct PreviewVisit: Identifiable, Equatable {
    var id: String
    var place = "Juniper Coffee"
    var area = "Coffee shop · Ocean Park"
    var time = "Today, 8:15 AM"
    var rating = PreviewRating()
    var note = ""
    var audience = "Friends"
    var silent = false
    var isWanna = false
    var quickCapture = true
    var invitationDismissed = false
    var selections: [String: Set<String>] = [:]
    var hasDetails: Bool { rating.value != nil || !note.isEmpty || selections.values.contains { !$0.isEmpty } }
    var invitationEligible: Bool { quickCapture && !hasDetails && !invitationDismissed && !isWanna }

    static let fixtures: [PreviewVisit] = [
        PreviewVisit(id: "visit-juniper-today"),
        PreviewVisit(id: "visit-cove-yesterday", place: "Cove Kitchen", area: "Neighborhood restaurant · Ocean Park", time: "Yesterday, 7:30 PM", rating: PreviewRating(value: 4.5), note: "The corner table is the one to get.", quickCapture: false),
        PreviewVisit(id: "visit-juniper-friday", time: "Fri, Nov 6 · 10:40 AM", rating: PreviewRating(value: 4), note: "Quiet in the morning. Try the cardamom bun.", quickCapture: false)
    ]
    static let wanna = PreviewVisit(id: "wanna-juniper", time: "Anytime", isWanna: true)
}

struct PreviewHistory {
    var visits = PreviewVisit.fixtures
    mutating func save(_ visit: PreviewVisit) {
        if let index = visits.firstIndex(where: { $0.id == visit.id }) { visits[index] = visit }
        else { visits.insert(visit, at: 0) }
    }
}
