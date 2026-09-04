import Combine
import CryptoKit
import EventKit
import Foundation

struct CalendarEventSnapshot: Equatable, Sendable {
    let stableIdentifier: String
    let title: String
    let location: String?
    let notes: String?
    let urlString: String?
    let startAt: Date
    let endAt: Date
    let timeZoneIdentifier: String
    let isAllDay: Bool
    let isCancelled: Bool
}

struct DetectedCalendarReservation: Equatable, Sendable {
    let occurrenceKey: String
    let placeQuery: String
    let localityHint: String?
    let startAt: Date
    let endAt: Date
    let timeZoneIdentifier: String
}

enum CalendarReservationDetector {
    private static let providerMarkers = [
        "resy.com", "opentable.com", "exploretock.com", "sevenrooms.com",
        "yelp.com/reservations", "tablecheck.com", "dorsia.com"
    ]
    private static let reservationMarkers = [
        "reservation", "reserved", "dinner at", "lunch at", "brunch at", "table at"
    ]
    private static let genericTitleWords: Set<String> = [
        "reservation", "reserved", "dinner", "lunch", "brunch", "table", "booking",
        "at", "for", "confirmed", "confirmation"
    ]

    static func detect(_ event: CalendarEventSnapshot) -> DetectedCalendarReservation? {
        guard !event.isAllDay, !event.isCancelled, event.endAt > event.startAt else { return nil }

        let searchable = [event.title, event.location, event.notes, event.urlString]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let hasProviderSignal = providerMarkers.contains { searchable.contains($0) }
        let hasReservationSignal = reservationMarkers.contains { searchable.contains($0) }
        guard hasProviderSignal || hasReservationSignal else { return nil }

        let normalizedTitle = normalizedPlaceName(event.title)
        let normalizedLocation = event.location
            .flatMap { $0.split(separator: ",", maxSplits: 1).first.map(String.init) }
            .map(normalizedPlaceName)
        let placeQuery = [Optional(normalizedTitle), normalizedLocation]
            .compactMap { candidate -> String? in
                guard let candidate else { return nil }
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 2,
                      !genericTitleWords.contains(trimmed.lowercased())
                else { return nil }
                return trimmed
            }
            .first
        guard let placeQuery else { return nil }

        let occurrenceSeed = "\(event.stableIdentifier)|\(Int(event.startAt.timeIntervalSince1970))"
        return DetectedCalendarReservation(
            occurrenceKey: sha256(occurrenceSeed),
            placeQuery: placeQuery,
            localityHint: localityHint(from: event.location),
            startAt: event.startAt,
            endAt: event.endAt,
            timeZoneIdentifier: event.timeZoneIdentifier
        )
    }

    private static func normalizedPlaceName(_ value: String) -> String {
        var result = value
        let patterns = [
            "(?i)^\\s*(reservation|booking|dinner|lunch|brunch|table)\\s+(at|for)\\s+",
            "(?i)\\s*[-–—:]?\\s*(reservation|booking|confirmed|confirmation)\\s*$"
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func localityHint(from location: String?) -> String? {
        guard let location else { return nil }
        let components = location.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard components.count > 1 else { return nil }
        let locality = components.count == 2 ? components[0] : components[1]
        guard !locality.isEmpty else { return nil }
        return locality
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct CalendarReservationSyncSummary: Equatable, Sendable {
    let detectedCount: Int
    let resolvedCount: Int
    let queuedCount: Int
    let cancelledCount: Int
}

enum CalendarPermissionAction: Equatable {
    case request
    case sync
    case openSettings
}

enum CalendarPermissionPolicy {
    static func action(for status: EKAuthorizationStatus) -> CalendarPermissionAction {
        switch status {
        case .fullAccess:
            .sync
        case .notDetermined, .writeOnly:
            .request
        case .denied, .restricted:
            .openSettings
        @unknown default:
            .request
        }
    }

    static func primaryTitle(for status: EKAuthorizationStatus) -> String {
        switch action(for: status) {
        case .request:
            "continue"
        case .sync:
            "sync now"
        case .openSettings:
            "open settings"
        }
    }
}

@MainActor
final class CalendarReservationManager: ObservableObject {
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncSummary: CalendarReservationSyncSummary?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var eventStoreRevision = 0

    private struct Cache: Codable {
        var itemsByOccurrenceKey: [String: CalendarReservationSyncItem]
    }

    private let eventStore: EKEventStore
    private let userDefaults: UserDefaults
    private let analytics: AnalyticsClient
    private var eventStoreObserver: NSObjectProtocol?
    private var lastSyncAt: Date?
    private var lastSyncedUserID: String?

    init(
        eventStore: EKEventStore = EKEventStore(),
        userDefaults: UserDefaults = .standard,
        analytics: AnalyticsClient = NoopAnalyticsClient()
    ) {
        self.eventStore = eventStore
        self.userDefaults = userDefaults
        self.analytics = analytics
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                self?.eventStoreRevision &+= 1
            }
        }
    }

    var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    var statusTitle: String {
        switch authorizationStatus {
        case .fullAccess: "Connected"
        case .denied, .restricted: "Off in iOS Settings"
        case .notDetermined, .writeOnly: "Not connected"
        @unknown default: "Unavailable"
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    @discardableResult
    func requestAccess() async -> Bool {
        lastErrorMessage = nil
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return granted && hasFullAccess
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            lastErrorMessage = "Could not connect Apple Calendar."
            return false
        }
    }

    func syncIfNeeded(
        backend: WanderBackend,
        store: WanderStore,
        userID: String,
        now: Date = .now,
        force: Bool = false,
        reason: String
    ) async {
        guard hasFullAccess,
              backend.notificationRepository != nil,
              !isSyncing
        else { return }
        if !force,
           lastSyncedUserID == userID,
           let lastSyncAt,
           now.timeIntervalSince(lastSyncAt) < 15 * 60 {
            return
        }

        isSyncing = true
        lastErrorMessage = nil
        defer { isSyncing = false }

        let calendar = Calendar.autoupdatingCurrent
        let windowStart = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let windowEnd = calendar.date(byAdding: .day, value: 180, to: now) ?? now.addingTimeInterval(180 * 86_400)
        let predicate = eventStore.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)
        let detected = eventStore.events(matching: predicate)
            .compactMap(snapshot)
            .compactMap(CalendarReservationDetector.detect)
            .sorted { $0.startAt < $1.startAt }
            .prefix(100)

        var cache = loadCache(userID: userID)
        var syncItems: [CalendarReservationSyncItem] = []
        for reservation in detected {
            if let cached = cache.itemsByOccurrenceKey[reservation.occurrenceKey] {
                syncItems.append(cached)
                continue
            }
            guard let candidates = try? await store.manualCandidates(
                name: reservation.placeQuery,
                areaHint: reservation.localityHint,
                category: "restaurant"
            ),
                  let candidate = candidates.first
            else { continue }
            let providerPlaceID = (candidate.sourceProviderPlaceID ?? candidate.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !providerPlaceID.isEmpty else { continue }

            let item = CalendarReservationSyncItem(
                occurrenceKey: reservation.occurrenceKey,
                canonicalName: candidate.name,
                locality: candidate.locality,
                sourceProvider: candidate.sourceProvider,
                sourceProviderPlaceID: providerPlaceID,
                startAt: reservation.startAt,
                endAt: reservation.endAt,
                eventTimezone: reservation.timeZoneIdentifier
            )
            cache.itemsByOccurrenceKey[reservation.occurrenceKey] = item
            syncItems.append(item)
        }

        do {
            let result = try await backend.syncCalendarReservations(
                syncItems,
                windowStart: windowStart,
                windowEnd: windowEnd
            )
            cache.itemsByOccurrenceKey = cache.itemsByOccurrenceKey.filter { key, _ in
                detected.contains { $0.occurrenceKey == key }
            }
            saveCache(cache, userID: userID)
            lastSyncAt = now
            lastSyncedUserID = userID
            lastSyncSummary = CalendarReservationSyncSummary(
                detectedCount: detected.count,
                resolvedCount: syncItems.count,
                queuedCount: result.queuedCount,
                cancelledCount: result.cancelledCount
            )
            analytics.track(AnalyticsEvent(
                name: WanderAnalyticsEvents.calendarReservationSyncCompleted,
                properties: [
                    "reason": reason,
                    "detected_count": "\(detected.count)",
                    "resolved_count": "\(syncItems.count)",
                    "queued_count": "\(result.queuedCount)",
                    "cancelled_count": "\(result.cancelledCount)"
                ]
            ))
        } catch {
            lastErrorMessage = "Calendar reservations could not sync. Try again later."
            #if DEBUG
            WanderDebugLog.remote.error("calendar reservation sync failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
        }
    }

    func clearAccountState(userID: String) {
        userDefaults.removeObject(forKey: cacheKey(userID: userID))
        if lastSyncedUserID == userID {
            lastSyncedUserID = nil
            lastSyncAt = nil
            lastSyncSummary = nil
        }
    }

    private func snapshot(_ event: EKEvent) -> CalendarEventSnapshot? {
        guard let startAt = event.startDate, let endAt = event.endDate else { return nil }
        let stableIdentifier = event.calendarItemExternalIdentifier
            ?? event.eventIdentifier
            ?? "\(event.title ?? "event")|\(Int(startAt.timeIntervalSince1970))"
        return CalendarEventSnapshot(
            stableIdentifier: stableIdentifier,
            title: event.title ?? "",
            location: event.location,
            notes: event.notes,
            urlString: event.url?.absoluteString,
            startAt: startAt,
            endAt: endAt,
            timeZoneIdentifier: event.timeZone?.identifier ?? TimeZone.autoupdatingCurrent.identifier,
            isAllDay: event.isAllDay,
            isCancelled: event.status == .canceled
        )
    }

    private func loadCache(userID: String) -> Cache {
        guard let data = userDefaults.data(forKey: cacheKey(userID: userID)),
              let cache = try? JSONDecoder().decode(Cache.self, from: data)
        else { return Cache(itemsByOccurrenceKey: [:]) }
        return cache
    }

    private func saveCache(_ cache: Cache, userID: String) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        userDefaults.set(data, forKey: cacheKey(userID: userID))
    }

    private func cacheKey(userID: String) -> String {
        let digest = SHA256.hash(data: Data(userID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "recme.calendar-reservations.v1.\(digest)"
    }
}
