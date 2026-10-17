import Foundation

/// Session-only authorization receipts for Live rows. Paging renews only the
/// rows it actually reauthorizes; timestamps supplied by cached payloads do not.
/// Continuous time includes device suspension and cannot move with wall-clock
/// edits, so changing the calendar clock cannot extend or resurrect a receipt.
struct LiveFeedDisplayLease {
    static let duration: Duration = .seconds(15 * 60)
    private var authorizedAt: [String: ContinuousClock.Instant] = [:]

    mutating func accept(activityIDs: [String], at now: ContinuousClock.Instant, replacing: Bool) {
        if replacing { authorizedAt = [:] }
        for id in activityIDs { authorizedAt[id] = now }
    }

    func permits(activityID: String, isOwn: Bool, at now: ContinuousClock.Instant) -> Bool {
        if isOwn { return true }
        guard let accepted = authorizedAt[activityID] else { return false }
        let age = accepted.duration(to: now)
        return age >= .zero && age < Self.duration
    }

    func nextExpiry(after now: ContinuousClock.Instant) -> ContinuousClock.Instant? {
        authorizedAt.values.map { $0.advanced(by: Self.duration) }.filter { $0 > now }.min()
    }
}
