import SwiftUI
import MapKit

struct LiveMapRequest: Equatable {
    let userID: String
    let audience: FeedAudience
    let query: LiveFeedQuery
    let featured: Bool
    let viewport: MapViewport?
    let refresh: UInt64

    func hasSameScope(as other: Self) -> Bool {
        userID == other.userID && audience == other.audience && query == other.query
            && featured == other.featured && viewport == other.viewport
    }
}

enum LiveMapPaging {
    @MainActor
    static func readAll(page: (String?) async throws -> FollowedFeedPage,
                        receive: ([FeedActivity], Bool) -> Void) async throws {
        var cursor: String?, requested = Set<String>(), seen = Set<String>()
        var accumulated: [FeedActivity] = []
        repeat {
            try Task.checkCancellation()
            if let cursor, !requested.insert(cursor).inserted {
                throw WanderRemoteError.invalidResponse("Map pagination did not advance")
            }
            let next = try await page(cursor)
            try Task.checkCancellation()
            accumulated.append(contentsOf: next.activity.filter { seen.insert($0.id).inserted })
            cursor = next.nextCursor
            receive(accumulated, cursor == nil)
            await Task.yield()
        } while cursor != nil
    }

    static func countText(_ count: Int, complete: Bool) -> String {
        let count = max(0, count)
        if count >= 100 { return "100+ activities" }
        if !complete && count == 0 { return "Finding activities…" }
        return "\(count)\(complete ? "" : "+") \(count == 1 && complete ? "activity" : "activities")"
    }
}

/// A map snapshot is independent of the Feed's visible tile window. It changes
/// on page/query/authorization updates, never on a drawer animation frame.
@MainActor
final class LiveMapResults: ObservableObject {
    @Published private(set) var activities: [FeedActivity] = []
    @Published private(set) var featuredPlaces: [VisiblePlace] = []
    @Published private(set) var complete = false
    @Published private(set) var error = false
    @Published private(set) var revision: UInt64 = 0
    private var requestID = UUID()
    private var lease = LiveFeedDisplayLease()
    private var expiryTask: Task<Void, Never>?
    private var currentRequest: LiveMapRequest?
    private var loadingRequest: LiveMapRequest?
    private var completedAt: ContinuousClock.Instant?
    private var featuredExpiresAt: ContinuousClock.Instant?
    private let clock: () -> ContinuousClock.Instant
    private struct Snapshot {
        let request: LiveMapRequest
        let activities: [FeedActivity]
        let featured: [VisiblePlace]
        let lease: LiveFeedDisplayLease
        let completedAt: ContinuousClock.Instant
        let featuredExpiresAt: ContinuousClock.Instant?
    }
    private var snapshots: [Snapshot] = []

    init(clock: @escaping () -> ContinuousClock.Instant = { .now }) { self.clock = clock }

    func load(request: LiveMapRequest, repository: (any FeedRepository)?,
              fixture: [FeedActivity], featured: @escaping @MainActor () async -> [VisiblePlace]?,
              permits: @escaping (FeedActivity) -> Bool) async {
        guard !Task.isCancelled else { return }
        if loadingRequest == request { return }
        let previousRequest = currentRequest
        rememberSnapshot()
        if previousRequest?.userID != request.userID { snapshots.removeAll() }
        let sameScope = previousRequest?.hasSameScope(as: request) == true
        if !sameScope {
            if let cached = snapshots.last(where: { $0.request.hasSameScope(as: request) }) {
                activities = cached.activities; featuredPlaces = cached.featured
                lease = cached.lease; completedAt = cached.completedAt
                featuredExpiresAt = cached.featuredExpiresAt; complete = true
            } else {
                // Matching, still-authorized rows bridge movement. Never bridge an
                // account/audience change or carry the old query's cursor.
                let canBridge = previousRequest?.userID == request.userID
                    && previousRequest?.audience == request.audience
                activities = canBridge ? activities.filter { request.query.includes($0) } : []
                if !canBridge { lease = LiveFeedDisplayLease() }
                if canBridge && request.featured && request.audience == .everyone {
                    featuredPlaces = featuredPlaces.filter { request.query.includesFeatured($0) }
                } else { featuredPlaces = []; featuredExpiresAt = nil }
                completedAt = nil; complete = false
            }
        }
        let token = UUID(); requestID = token; currentRequest = request
        loadingRequest = nil
        expiryTask?.cancel()
        revalidate(userID: request.userID, permits: permits)
        let fresh = completedAt.map { $0.duration(to: clock()) >= .zero && $0.duration(to: clock()) < .seconds(60) } ?? false
        if complete && fresh && (!sameScope || previousRequest?.refresh == request.refresh) {
            error = false
            scheduleExpiry(userID: request.userID, token: token)
            return
        }
        loadingRequest = request
        defer { if requestID == token { loadingRequest = nil } }
        error = false
        scheduleExpiry(userID: request.userID, token: token)
        // Featured has its own request and receipt; it must not wait for every
        // social-history page in a busy city.
        let featuredTask = Task { @MainActor [weak self] in
            let candidates = await featured()
            guard let self, !Task.isCancelled, self.requestID == token else { return }
            self.featuredPlaces = candidates ?? []
            self.featuredExpiresAt = candidates == nil ? nil : self.clock().advanced(by: LiveFeedDisplayLease.duration)
            self.revision &+= 1
            self.scheduleExpiry(userID: request.userID, token: token)
        }
        await withTaskCancellationHandler {
            do {
                if let repository {
                    var processedCount = 0
                    var accumulated: [FeedActivity] = []
                    var lastPublishedCount = 0
                    try await LiveMapPaging.readAll(page: { cursor in
                        try await repository.liveMapActivity(audience: request.audience, query: request.query,
                                                             before: cursor, limit: 50)
                    }, receive: { [weak self] rows, exhausted in
                        guard let self, self.requestID == token, !Task.isCancelled else { return }
                        let now = self.clock()
                        let incoming = rows.dropFirst(processedCount).filter { request.query.includes($0) && permits($0) }
                        processedCount = rows.count
                        accumulated.append(contentsOf: incoming)
                        self.lease.accept(activityIDs: incoming.map(\.id), at: now, replacing: false)
                        if exhausted || accumulated.count <= 100 || accumulated.count - lastPublishedCount >= 250 {
                            let newIDs = Set(accumulated.map(\.id))
                            let retained = exhausted ? [] : self.activities.filter { !newIDs.contains($0.id) }
                            self.activities = (accumulated + retained).filter { permits($0) && self.lease.permits(
                                activityID: $0.id, isOwn: $0.actor.id == request.userID, at: now) }
                            lastPublishedCount = accumulated.count
                            self.complete = exhausted
                            self.revision &+= 1
                        }
                        self.scheduleExpiry(userID: request.userID, token: token)
                    })
                } else {
                    activities = fixture.filter { request.query.includes($0) && permits($0) }
                    lease.accept(activityIDs: activities.map(\.id), at: clock(), replacing: true)
                    complete = true; revision &+= 1
                }
                guard requestID == token, !Task.isCancelled else { return }
                completedAt = clock()
            } catch {
                guard requestID == token, !Task.isCancelled else { return }
                if !ProtectedContentCachePolicy.permitsOfflineRead(after: error) {
                    activities = []; featuredPlaces = []; featuredExpiresAt = nil
                    lease = LiveFeedDisplayLease(); snapshots.removeAll(); featuredTask.cancel()
                }
                self.error = true; complete = false; completedAt = nil; revision &+= 1
            }
            await featuredTask.value
            guard requestID == token, !Task.isCancelled else { return }
            scheduleExpiry(userID: request.userID, token: token)
            rememberSnapshot()
        } onCancel: { featuredTask.cancel() }
    }

    func invalidateFreshness() {
        completedAt = nil
        snapshots.removeAll()
    }

    func revalidate(userID: String, permits: (FeedActivity) -> Bool) {
        if let currentRequest, currentRequest.userID != userID {
            requestID = UUID(); expiryTask?.cancel(); loadingRequest = nil
            self.currentRequest = nil; activities = []; featuredPlaces = []
            lease = LiveFeedDisplayLease(); snapshots.removeAll()
            completedAt = nil; featuredExpiresAt = nil; complete = false; error = false
        }
        let now = clock()
        activities.removeAll { !permits($0) || !lease.permits(activityID: $0.id, isOwn: $0.actor.id == userID, at: now) }
        // Intermediate pages may be authorized but not published yet.
        if loadingRequest == nil { lease.retain(activityIDs: Set(activities.map(\.id))) }
        if let expiry = featuredExpiresAt, now >= expiry { featuredPlaces = []; featuredExpiresAt = nil }
        // A cached snapshot never renews authorization or resurrects a local revocation.
        snapshots = snapshots.filter { $0.request.userID == userID && $0.completedAt.duration(to: now) < LiveFeedDisplayLease.duration }
        for index in snapshots.indices {
            let old = snapshots[index]
            snapshots[index] = Snapshot(request: old.request,
                activities: old.activities.filter { permits($0) }, featured: old.featured,
                lease: old.lease, completedAt: old.completedAt, featuredExpiresAt: old.featuredExpiresAt)
        }
        revision &+= 1
    }

    private func rememberSnapshot() {
        guard complete, let request = currentRequest, let completedAt else { return }
        snapshots.removeAll { $0.request.hasSameScope(as: request) }
        lease.retain(activityIDs: Set(activities.map(\.id)))
        // Bound inactive memory without clipping the active map's complete result.
        guard activities.count + featuredPlaces.count <= 2_000 else { return }
        snapshots.append(Snapshot(request: request, activities: activities, featured: featuredPlaces,
            lease: lease, completedAt: completedAt, featuredExpiresAt: featuredExpiresAt))
        if snapshots.count > 4 { snapshots.removeFirst(snapshots.count - 4) }
    }

    private func scheduleExpiry(userID: String, token: UUID) {
        expiryTask?.cancel()
        let now = clock()
        let expiry = [lease.nextExpiry(after: now), featuredExpiresAt].compactMap { $0 }.filter { $0 > now }.min()
        guard let expiry else { return }
        let delay = now.duration(to: expiry)
        expiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, self.requestID == token else { return }
            self.revalidate(userID: userID, permits: { _ in true })
            self.complete = false
            self.completedAt = nil
            self.error = true
            self.scheduleExpiry(userID: userID, token: token)
        }
    }

}

/// A presentation identity for an already-authorized place. Coordinate overlap
/// alone never joins venues, people, or activity records.
struct LivePlaceIdentity: Hashable {
    let aliases: Set<String>
    let placeIDs: Set<String>
    fileprivate let members: Set<Member>
    private let membersByAlias: [String: Set<Member>]

    init(places: [LocalPlace]) {
        let members = Set(places.map(Member.init))
        self.members = members
        aliases = Set(members.flatMap(\.lookupKeys))
        // An unverified provider UUID must not become an independent RPC seed.
        // Validated target rows enter this set as members of the map component.
        placeIDs = Set(members.flatMap(\.ids))
        var index: [String: Set<Member>] = [:]
        for member in members {
            for key in member.lookupKeys { index[key, default: []].insert(member) }
        }
        membersByAlias = index
    }

    var persistedPlaceIDs: [String] {
        Array(Set(placeIDs.compactMap { UUID(uuidString: $0)?.uuidString.lowercased() })).sorted()
    }

    var cacheKey: String { members.map(\.cacheKey).sorted().map(Self.field).joined() }

    func matches(_ place: LocalPlace) -> Bool { matches(Member(place)) }

    func intersects(_ other: LivePlaceIdentity) -> Bool {
        other.members.contains { matches($0) }
    }

    private func matches(_ member: Member) -> Bool {
        var checked = Set<Member>()
        return member.lookupKeys.contains { key in
            (membersByAlias[key] ?? []).contains { candidate in
                checked.insert(candidate).inserted && candidate.matches(member)
            }
        }
    }

    static func aliases(for place: LocalPlace) -> Set<String> { Member(place).lookupKeys }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.members == rhs.members }
    func hash(into hasher: inout Hasher) { hasher.combine(members) }
    private static func field(_ value: String) -> String { "\(value.utf8.count):\(value)" }

    /// Immutable identity evidence: old pin identity must not mutate when a
    /// refreshed SwiftData object corrects its provider or address metadata.
    fileprivate struct Member: Hashable {
        let ids: Set<String>
        let provider: String
        let providerID: String
        let referenceID: String?
        let name: String
        let street: String
        let locality: String
        let region: String
        let country: String
        let latitude: Double?
        let longitude: Double?

        init(_ place: LocalPlace) {
            ids = Set([place.id, place.localID, place.serverID].compactMap { value in
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
                return UUID(uuidString: value)?.uuidString.lowercased() ?? value
            })
            provider = place.sourceProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            providerID = (place.sourceProviderPlaceID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            referenceID = UUID(uuidString: providerID)?.uuidString.lowercased()
            func text(_ value: String?) -> String {
                VisiblePlaceGrouping.normalizedText(value, locale: Locale(identifier: "en_US_POSIX"))
            }
            name = text(place.canonicalName)
            let suffixes = ["avenue": "ave", "boulevard": "blvd", "circle": "cir", "court": "ct",
                "drive": "dr", "highway": "hwy", "lane": "ln", "parkway": "pkwy", "place": "pl",
                "road": "rd", "street": "st", "terrace": "ter"]
            street = text(place.address).split(separator: " ").map { suffixes[String($0)] ?? String($0) }.joined(separator: " ")
            locality = text(place.locality); region = text(place.region)
            // MapKit and older imports can describe one country as US/USA or
            // United States. Compare canonical names before joining address
            // aliases, or one venue can survive as both a saved pin and a dot.
            country = text(CountryCanonicalizer.canonicalName(place.country))
            let valid = place.latitude.isFinite && place.longitude.isFinite
                && CLLocationCoordinate2DIsValid(.init(latitude: place.latitude, longitude: place.longitude))
            latitude = valid ? (place.latitude == 0 ? 0 : place.latitude) : nil
            longitude = valid ? (place.longitude == 0 ? 0 : place.longitude) : nil
        }

        var strongKeys: Set<String> {
            var keys = Set(ids.map { "id:\($0)" })
            // UUID-valued provider IDs are historical references, so their
            // geography/name corroboration cannot be bypassed as a strong key.
            if referenceID == nil, !provider.isEmpty, !providerID.isEmpty {
                keys.insert("provider:" + LivePlaceIdentity.field(provider) + LivePlaceIdentity.field(providerID))
            }
            return keys
        }

        var weakKeys: Set<String> {
            var keys = Set(ids.map { "reference:\($0)" })
            if let referenceID { keys.insert("reference:\(referenceID)") }
            if !name.isEmpty, !street.isEmpty, !locality.isEmpty {
                keys.insert("address:" + [name, street, locality, region, country].map(LivePlaceIdentity.field).joined())
            }
            return keys
        }

        var lookupKeys: Set<String> { strongKeys.union(weakKeys) }
        var cacheKey: String {
            (ids.sorted() + [provider, providerID, name, street, locality, region, country,
                latitude.map { String($0) } ?? "", longitude.map { String($0) } ?? ""]).map(LivePlaceIdentity.field).joined()
        }

        func matches(_ other: Member) -> Bool {
            if !strongKeys.isDisjoint(with: other.strongKeys) { return true }
            guard let latitude, let longitude, let otherLatitude = other.latitude, let otherLongitude = other.longitude,
                  CLLocation(latitude: latitude, longitude: longitude).distance(from:
                    CLLocation(latitude: otherLatitude, longitude: otherLongitude)) <= 100 else { return false }
            let sameName = !name.isEmpty && name == other.name
            let sameStreetLocality = !street.isEmpty && !locality.isEmpty
                && street == other.street && locality == other.locality
            let sameReferenceToken = referenceID != nil && referenceID == other.referenceID
                && !provider.isEmpty && provider == other.provider && providerID == other.providerID
            let references = (referenceID.map { other.ids.contains($0) } ?? false)
                || (other.referenceID.map { ids.contains($0) } ?? false) || sameReferenceToken
            if references { return sameName || sameStreetLocality }
            return sameName && sameStreetLocality && region == other.region && country == other.country
        }
    }
}

struct LivePlacePin: Identifiable {
    let id: String
    let place: VisiblePlace
    let activities: [FeedActivity]
    let hasPriorOwnCheckIn: Bool
    let identity: LivePlaceIdentity
    let totemState: LiveTotemState

    init(id: String, place: VisiblePlace, activities: [FeedActivity], hasPriorOwnCheckIn: Bool = false,
         identity: LivePlaceIdentity? = nil, totemState: LiveTotemState = .empty) {
        self.id = id
        self.place = place
        self.activities = activities
        self.hasPriorOwnCheckIn = hasPriorOwnCheckIn
        self.identity = identity ?? LivePlaceIdentity(places: [place.place] + activities.compactMap { $0.place?.place })
        self.totemState = totemState
    }

    func isViewed(dates: [String: Date], now: Date = .now) -> Bool {
        identity.placeIDs.union([id]).contains { LiveViewedPinHistory.isViewed($0, dates: dates, now: now) }
    }

    var kind: LivePinKind {
        if hasPriorOwnCheckIn || activities.isEmpty || activities.contains(where: { $0.resolvedTicketKind == .checkIn })
            || ([place] + activities.compactMap(\.place)).contains(where: { visible in
                visible.owner.deletedAt == nil && visible.userPlace.deletedAt == nil
                    && visible.owner.id == visible.userPlace.userID
                    && (visible.userPlace.status == .been || visible.userPlace.visitedAt != nil
                        || visible.userPlace.recommendedCount > 0)
            }) { return .checkIn }
        if activities.contains(where: { $0.resolvedTicketKind == .wanna }) { return .wanna }
        return .list
    }
    var accessibilityLabel: String {
        let stateSummary = totemState.accessibilitySummary
        guard let latest = activities.first else {
            return [place.place.canonicalName, stateSummary].filter { !$0.isEmpty }.joined(separator: ", ")
        }
        let summary = "\(latest.actor.displayName), \(LiveActivityPresentation.title(for: latest)), \(FeedPresentation.timestampText(for: latest.occurredAt))"
        return [place.place.canonicalName, stateSummary, summary].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

enum LiveMapProjection {
    /// Own history changes only badge evidence, never the filtered activity set.
    static func pins(activities: [FeedActivity], featured: [VisiblePlace],
                     ownCheckInPlaces: [VisiblePlace] = [], totemContext: LiveTotemContext? = nil,
                     previousPins: [LivePlacePin] = []) -> [LivePlacePin] {
        let ownIdentity = LivePlaceIdentity(places: ownCheckInPlaces.filter {
            $0.owner.deletedAt == nil && $0.userPlace.deletedAt == nil && $0.owner.id == $0.userPlace.userID
        }.map(\.place))
        var seenEvents = Set<String>()
        let events = activities.filter { $0.place != nil && seenEvents.insert($0.id).inserted }
        let places = events.compactMap(\.place) + featured
        guard !places.isEmpty else { return [] }
        let identityPlaces = places.map(\.place) + (totemContext?.identityPlaces ?? [])
        var parents = Array(identityPlaces.indices)
        func root(_ index: Int) -> Int {
            var current = index
            while parents[current] != current {
                parents[current] = parents[parents[current]]
                current = parents[current]
            }
            return current
        }
        func join(_ lhs: Int, _ rhs: Int) {
            let left = root(lhs), right = root(rhs)
            if left != right { parents[max(left, right)] = min(left, right) }
        }
        var evidenceByObject: [ObjectIdentifier: LivePlaceIdentity.Member] = [:]
        let evidence = identityPlaces.map { place in
            let key = ObjectIdentifier(place)
            if let member = evidenceByObject[key] { return member }
            let member = LivePlaceIdentity.Member(place)
            evidenceByObject[key] = member
            return member
        }
        var firstByMember: [LivePlaceIdentity.Member: Int] = [:]
        var firstByStrongKey: [String: Int] = [:]
        var indicesByWeakKey: [String: [Int]] = [:]
        for (index, member) in evidence.enumerated() {
            if let first = firstByMember[member] { join(first, index); continue }
            firstByMember[member] = index
            for key in member.strongKeys {
                if let first = firstByStrongKey[key] { join(first, index) }
                else { firstByStrongKey[key] = index }
            }
            // Candidate indexes avoid comparing every venue in the city. Only
            // shared address/reference keys need the stricter geographic check.
            var checked = Set<Int>()
            for key in member.weakKeys {
                for candidate in indicesByWeakKey[key] ?? [] where checked.insert(candidate).inserted {
                    if member.matches(evidence[candidate]) { join(candidate, index) }
                }
                indicesByWeakKey[key, default: []].append(index)
            }
        }
        let members = Dictionary(grouping: identityPlaces.indices, by: root)
        var result: [LivePlacePin] = []
        for indices in members.values {
            let groupEvents = indices.filter { $0 < events.count }.map { events[$0] }
            let groupPlaces = indices.filter { $0 < places.count }.map { places[$0] }
            let valid = groupPlaces.filter {
                $0.place.latitude.isFinite && $0.place.longitude.isFinite
                    && CLLocationCoordinate2DIsValid(.init(latitude: $0.place.latitude, longitude: $0.place.longitude))
            }
            let eventPlaceIDs = Set(groupEvents.compactMap { $0.place?.id })
            guard let place = valid.sorted(by: { lhs, rhs in
                let lhsEvent = eventPlaceIDs.contains(lhs.id), rhsEvent = eventPlaceIDs.contains(rhs.id)
                if lhsEvent != rhsEvent { return lhsEvent }
                if lhs.place.id != rhs.place.id { return lhs.place.id < rhs.place.id }
                return lhs.id < rhs.id
            }).first else { continue }
            let identity = LivePlaceIdentity(places: indices.map { identityPlaces[$0] })
            let featuredPlaces = indices.filter { $0 >= events.count && $0 < places.count }.map { places[$0] }
            let isFeatured = featuredPlaces.contains { $0.userPlace.deletedAt == nil && $0.owner.deletedAt == nil }
            result.append(LivePlacePin(id: place.place.id, place: place,
                activities: FeedPresentation.newestFirst(groupEvents),
                hasPriorOwnCheckIn: identity.intersects(ownIdentity), identity: identity,
                totemState: totemContext?.state(for: identity, activities: groupEvents, featured: isFeatured,
                    additionalSavedPlaces: featuredPlaces, hasPriorOwnCheckIn: identity.intersects(ownIdentity)) ?? .empty))
        }
        result.sort { $0.id < $1.id }
        var previousByAlias: [String: Set<Int>] = [:]
        for (index, pin) in previousPins.enumerated() {
            for alias in pin.identity.aliases { previousByAlias[alias, default: []].insert(index) }
        }
        let previousMatches = result.map { pin in
            Set(pin.identity.aliases.flatMap { previousByAlias[$0] ?? [] }).filter {
                pin.identity.intersects(previousPins[$0].identity)
            }.sorted()
        }
        var assigned: [Int: String] = [:]
        var used = Set<String>()
        // Give a surviving original its own identifier before offering that old
        // component's identifier to another component after an alias correction.
        for index in result.indices {
            if let previous = previousMatches[index].first(where: {
                result[index].identity.placeIDs.contains(previousPins[$0].id) && !used.contains(previousPins[$0].id)
            }) {
                let id = previousPins[previous].id
                assigned[index] = id; used.insert(id)
            }
        }
        let currentIDs = Set(result.map(\.id))
        for index in result.indices where assigned[index] == nil {
            if let previous = previousMatches[index].first(where: {
                !used.contains(previousPins[$0].id) && !currentIDs.contains(previousPins[$0].id)
            }) {
                let id = previousPins[previous].id
                assigned[index] = id; used.insert(id)
            }
        }
        return result.enumerated().map { index, pin in
            var id = assigned[index] ?? pin.id
            if assigned[index] == nil {
                var suffix = 0
                while used.contains(id) { suffix += 1; id = "\(pin.id):component:\(suffix)" }
                used.insert(id)
            }
            return LivePlacePin(id: id, place: pin.place, activities: pin.activities,
                hasPriorOwnCheckIn: pin.hasPriorOwnCheckIn, identity: pin.identity, totemState: pin.totemState)
        }.sorted { $0.id < $1.id }
    }
}
