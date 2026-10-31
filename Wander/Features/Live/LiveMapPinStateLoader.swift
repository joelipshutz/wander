import Foundation
import Combine

struct LiveMapPinStateRequest: Equatable {
    let map: LiveMapRequest
    let placeIDs: [String]
    let resultRevision: UInt64
    let storeRevision: UInt64
}

/// Short-lived authorization evidence. Same-scope reloads keep the existing
/// receipt until replacement or its original expiry; failed/partial reads and
/// account/store invalidation still discard it. Nothing persists across restart.
@MainActor
final class LiveMapPinStateLoader: ObservableObject {
    @Published private(set) var snapshot: LiveMapPinStateSnapshot?
    @Published private(set) var revision: UInt64 = 0
    private var requestToken = UUID()
    private var receiptToken = UUID()
    private var receiptScope: AuthorizationScope?
    private var expiryTask: Task<Void, Never>?
    private var expiresAt: Date?
    private var lastRequest: LiveMapPinStateRequest?
    private let duration: Duration

    init(duration: Duration = LiveFeedDisplayLease.duration) { self.duration = duration }

    func reset() {
        requestToken = UUID()
        clearReceipt()
    }

    private func clearReceipt() {
        // Empty resets still fence pending work, but cannot change rendered facts.
        let hadSnapshot = snapshot != nil
        receiptToken = UUID()
        receiptScope = nil
        expiryTask?.cancel()
        expiryTask = nil
        expiresAt = nil
        if hadSnapshot { snapshot = nil }
        lastRequest = nil
        if hadSnapshot { revision &+= 1 }
    }

    /// Suspension can delay a sleeping task. Revalidate synchronously before
    /// rebuilding the first foreground frame from authorization evidence.
    func revalidate(now: Date = .now) {
        guard snapshot != nil, let expiresAt, now >= expiresAt else { return }
        // Expiring the old receipt must not cancel a fresh read already in flight.
        clearReceipt()
    }

    func load(request: LiveMapPinStateRequest?, repository: (any LiveMapPinStateRepository)?) async {
        guard !Task.isCancelled else { return }
        guard let request, let repository else { reset(); return }
        let token = UUID()
        requestToken = token
        revalidate()
        let scope = AuthorizationScope(userID: request.map.userID, storeRevision: request.storeRevision)
        if let receiptScope, receiptScope != scope { clearReceipt() }
        // Map enumeration temporarily publishes no pins. Keep the same-scope
        // receipt (and its timer), but it proves nothing about any additional IDs.
        guard !request.placeIDs.isEmpty else { return }
        // Preserve warm-return/result-only reuse without renewing the receipt.
        // A refresh, changed IDs, or changed query still reads current state.
        if let previous = lastRequest, previous.map == request.map,
           previous.placeIDs == request.placeIDs, previous.storeRevision == request.storeRevision,
           let fetchedAt = snapshot?.fetchedAt, Date.now.timeIntervalSince(fetchedAt) < 60 { return }
        do {
            let result = try await repository.liveMapPinStates(placeIDs: request.placeIDs)
            guard !Task.isCancelled, token == requestToken else { return }
            guard result.complete,
                  Set(result.states.map(\.placeID)) == Set(request.placeIDs),
                  result.states.count == Set(request.placeIDs).count,
                  let fetchedAt = result.fetchedAt else { clearReceipt(); return }
            let age = Date.now.timeIntervalSince(fetchedAt)
            let leaseSeconds = Double(LiveFeedDisplayLease.duration.components.seconds)
            guard age.isFinite, age >= -30, age < leaseSeconds else { clearReceipt(); return }
            let remaining = min(duration, Duration.seconds(leaseSeconds - max(0, age)))
            let seconds = Double(remaining.components.seconds)
                + Double(remaining.components.attoseconds) / 1e18
            lastRequest = request
            expiryTask?.cancel()
            let receipt = UUID()
            receiptToken = receipt
            receiptScope = scope
            expiresAt = Date.now.addingTimeInterval(seconds)
            snapshot = result
            revision &+= 1
            expiryTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: remaining) } catch { return }
                guard let self, self.receiptToken == receipt else { return }
                self.clearReceipt()
            }
        } catch {
            guard !Task.isCancelled, token == requestToken else { return }
            // The map's authorized activity remains usable; unknown current
            // state never becomes proof of Featured or list membership.
            clearReceipt()
        }
    }

    private struct AuthorizationScope: Equatable {
        let userID: String
        let storeRevision: UInt64
    }
}
