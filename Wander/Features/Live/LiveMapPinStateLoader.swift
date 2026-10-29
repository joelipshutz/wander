import Foundation
import Combine

struct LiveMapPinStateRequest: Equatable {
    let map: LiveMapRequest
    let placeIDs: [String]
    let resultRevision: UInt64
    let storeRevision: UInt64
}

/// Short-lived authorization evidence. Query changes and failed/partial reads
/// discard old state; no status snapshot survives account changes or restart.
@MainActor
final class LiveMapPinStateLoader: ObservableObject {
    @Published private(set) var snapshot: LiveMapPinStateSnapshot?
    @Published private(set) var revision: UInt64 = 0
    private var requestToken = UUID()
    private var expiryTask: Task<Void, Never>?
    private var expiresAt: Date?
    private var lastRequest: LiveMapPinStateRequest?
    private let duration: Duration

    init(duration: Duration = LiveFeedDisplayLease.duration) { self.duration = duration }

    func reset() {
        requestToken = UUID()
        expiryTask?.cancel()
        expiryTask = nil
        expiresAt = nil
        snapshot = nil
        lastRequest = nil
        revision &+= 1
    }

    /// Suspension can delay a sleeping task. Revalidate synchronously before
    /// rebuilding the first foreground frame from authorization evidence.
    func revalidate(now: Date = .now) {
        guard snapshot != nil, let expiresAt, now >= expiresAt else { return }
        reset()
    }

    func load(request: LiveMapPinStateRequest?, repository: (any LiveMapPinStateRepository)?) async {
        revalidate()
        guard let request, !request.placeIDs.isEmpty, let repository else { reset(); return }
        if let previous = lastRequest, previous.map == request.map,
           previous.placeIDs == request.placeIDs, previous.storeRevision == request.storeRevision,
           let fetchedAt = snapshot?.fetchedAt, Date.now.timeIntervalSince(fetchedAt) < 60 { return }
        let retainsEvidence = lastRequest.map { $0.map.hasSameScope(as: request.map) } ?? false
        if !retainsEvidence { reset() }
        let token = UUID(); requestToken = token
        // Retain valid evidence while an equivalent request is pending. Failure,
        // partial data and scope changes still fail closed.
        var accepted = false
        defer { if !accepted, !Task.isCancelled, requestToken == token { reset() } }
        do {
            let result = try await repository.liveMapPinStates(placeIDs: request.placeIDs)
            guard !Task.isCancelled, token == requestToken, result.complete,
                  Set(result.states.map(\.placeID)) == Set(request.placeIDs),
                  result.states.count == Set(request.placeIDs).count,
                  let fetchedAt = result.fetchedAt else { return }
            let age = Date.now.timeIntervalSince(fetchedAt)
            let leaseSeconds = Double(LiveFeedDisplayLease.duration.components.seconds)
            guard age.isFinite, age >= -30, age < leaseSeconds else { return }
            let remaining = min(duration, Duration.seconds(leaseSeconds - max(0, age)))
            let seconds = Double(remaining.components.seconds)
                + Double(remaining.components.attoseconds) / 1e18
            accepted = true
            lastRequest = request
            expiryTask?.cancel()
            expiresAt = Date.now.addingTimeInterval(seconds)
            snapshot = result
            revision &+= 1
            let expiration = expiresAt
            expiryTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: remaining) } catch { return }
                guard let self, self.expiresAt == expiration else { return }
                self.reset()
            }
        } catch {
            // The map's authorized activity remains usable; unknown current
            // state never becomes proof of Featured or list membership.
        }
    }
}
