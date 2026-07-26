import AppIntents
import CoreLocation
import MapKit
import SwiftUI
import WidgetKit

@main
struct WanderNearbyPlacesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WanderWidgetConstants.nearbyPlacesKind,
            provider: WanderNearbyTimelineProvider()
        ) { entry in
            WanderNearbyWidgetView(entry: entry)
        }
        .configurationDisplayName("Nearby Rich Visit")
        .description("Pick a nearby place and add a Rich Visit in rec.me.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

struct WanderRefreshNearbyPlacesIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh nearby spots"
    static let description = IntentDescription(
        "Updates the nearby spots shown in the rec.me widget."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let startedAt = Date()
        let refreshStateStore = WanderNearbyWidgetRefreshStateStore()
        if case .refreshing = refreshStateStore.state(at: startedAt) {
            return .result()
        }
        guard let requestID = try? refreshStateStore.begin(at: startedAt) else {
            return .result()
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WanderWidgetConstants.nearbyPlacesKind)
        await Task.yield()

        let update = await WanderNearbyTimelineLoader().load(
            now: startedAt,
            forceFreshnessAdvance: true
        )
        let minimumFeedbackDuration: TimeInterval = 0.8
        let remainingFeedbackDuration = minimumFeedbackDuration
            - Date().timeIntervalSince(startedAt)
        if remainingFeedbackDuration > 0 {
            try? await Task.sleep(
                nanoseconds: UInt64(remainingFeedbackDuration * 1_000_000_000)
            )
        }

        _ = try? refreshStateStore.complete(
            requestID: requestID,
            at: .now,
            availability: update.availability
        )
        WidgetCenter.shared.reloadTimelines(ofKind: WanderWidgetConstants.nearbyPlacesKind)
        return .result()
    }
}

private struct WanderNearbyEntry: TimelineEntry {
    let date: Date
    let snapshot: WanderNearbyWidgetSnapshot?
    let availability: WanderNearbyWidgetAvailability
    let isRefreshing: Bool
}

private final class WanderNearbyTimelineCompletion: @unchecked Sendable {
    let call: (Timeline<WanderNearbyEntry>) -> Void

    init(_ call: @escaping (Timeline<WanderNearbyEntry>) -> Void) {
        self.call = call
    }
}

private final class WanderNearbySnapshotCompletion: @unchecked Sendable {
    let call: (WanderNearbyEntry) -> Void

    init(_ call: @escaping (WanderNearbyEntry) -> Void) {
        self.call = call
    }
}

private struct WanderNearbyTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WanderNearbyEntry {
        WanderNearbyEntry(
            date: WanderNearbyPreviewData.date,
            snapshot: WanderNearbyPreviewData.snapshot,
            availability: .ready,
            isRefreshing: false
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WanderNearbyEntry) -> Void
    ) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }

        let completion = WanderNearbySnapshotCompletion(completion)
        Task { @MainActor in
            let snapshotStore = WanderNearbyWidgetSnapshotStore()
            let locationProvider = WanderNearbyWidgetLocationProvider()
            guard locationProvider.isEligibleForWidgetLocation else {
                _ = try? snapshotStore.clear()
                completion.call(
                    WanderNearbyEntry(
                        date: .now,
                        snapshot: nil,
                        availability: .locationAuthorizationRequired,
                        isRefreshing: false
                    )
                )
                return
            }

            let snapshot = snapshotStore.load()
            completion.call(
                WanderNearbyEntry(
                    date: .now,
                    snapshot: snapshot,
                    availability: snapshot == nil ? .locationTemporarilyUnavailable : .ready,
                    isRefreshing: false
                )
            )
        }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WanderNearbyEntry>) -> Void
    ) {
        let completion = WanderNearbyTimelineCompletion(completion)
        Task { @MainActor in
            let now = Date()
            let snapshotStore = WanderNearbyWidgetSnapshotStore()
            let locationProvider = WanderNearbyWidgetLocationProvider()
            guard locationProvider.isEligibleForWidgetLocation else {
                _ = try? snapshotStore.clear()
                let update = WanderNearbyTimelineUpdate(
                    date: now,
                    snapshot: nil,
                    availability: .locationAuthorizationRequired,
                    reloadAfter: now.addingTimeInterval(
                        WanderNearbyWidgetAvailability
                            .locationAuthorizationRequired
                            .reloadInterval
                    )
                )
                completion.call(
                    Timeline(
                        entries: entries(for: update),
                        policy: .after(update.reloadAfter)
                    )
                )
                return
            }

            let snapshot = snapshotStore.load()
            switch WanderNearbyWidgetRefreshStateStore().state(at: now) {
            case .refreshing:
                completion.call(
                    Timeline(
                        entries: [
                            WanderNearbyEntry(
                                date: now,
                                snapshot: snapshot,
                                availability: snapshot == nil
                                    ? .locationTemporarilyUnavailable
                                    : .ready,
                                isRefreshing: true
                            )
                        ],
                        policy: .after(now.addingTimeInterval(5))
                    )
                )
                return
            case .completed(_, let availability):
                let update = WanderNearbyTimelineUpdate(
                    date: now,
                    snapshot: snapshot,
                    availability: availability,
                    reloadAfter: now.addingTimeInterval(availability.reloadInterval)
                )
                completion.call(
                    Timeline(
                        entries: entries(for: update),
                        policy: .after(update.reloadAfter)
                    )
                )
                return
            case .idle:
                break
            }

            let update = await WanderNearbyTimelineLoader().load()
            completion.call(
                Timeline(
                    entries: entries(for: update),
                    policy: .after(update.reloadAfter)
                )
            )
        }
    }

    private func entries(
        for update: WanderNearbyTimelineUpdate
    ) -> [WanderNearbyEntry] {
        func entry(at date: Date) -> WanderNearbyEntry {
            WanderNearbyEntry(
                date: date,
                snapshot: update.snapshot,
                availability: update.availability,
                isRefreshing: false
            )
        }

        guard let generatedAt = update.snapshot?.generatedAt else {
            return [entry(at: update.date)]
        }

        let exactDistanceExpiration = generatedAt.addingTimeInterval(
            WanderNearbyWidgetFreshness.exactDistanceLifetime + 1
        )
        let resultExpiration = generatedAt.addingTimeInterval(
            WanderNearbyWidgetFreshness.usableLifetime + 1
        )
        var entryDates = [update.date]
        entryDates.append(contentsOf: [
            exactDistanceExpiration,
            resultExpiration
        ]
        .filter { $0 > update.date }
        .sorted())
        return entryDates.map { entry(at: $0) }
    }

}

@MainActor
private struct WanderNearbyTimelineUpdate {
    let date: Date
    let snapshot: WanderNearbyWidgetSnapshot?
    let availability: WanderNearbyWidgetAvailability
    let reloadAfter: Date
}

@MainActor
private struct WanderNearbyTimelineLoader {
    private let snapshotStore = WanderNearbyWidgetSnapshotStore()

    func load(
        now: Date = .now,
        forceFreshnessAdvance: Bool = false
    ) async -> WanderNearbyTimelineUpdate {
        let cachedSnapshot = snapshotStore.load()
        let locationProvider = WanderNearbyWidgetLocationProvider()

        guard locationProvider.isEligibleForWidgetLocation else {
            _ = try? snapshotStore.clear()
            return update(
                now: now,
                cachedSnapshot: nil,
                availability: .locationAuthorizationRequired,
                retryAfter: WanderNearbyWidgetAvailability
                    .locationAuthorizationRequired
                    .reloadInterval
            )
        }

        do {
            let location = try await locationProvider.currentLocation()
            let places = try await WanderNearbyMapKitSearch().places(near: location)
            guard !places.isEmpty else {
                return update(
                    now: now,
                    cachedSnapshot: cachedSnapshot,
                    availability: .noPlaces,
                    retryAfter: WanderNearbyWidgetAvailability.noPlaces.reloadInterval
                )
            }

            let snapshot = WanderNearbyWidgetSnapshot(
                generatedAt: now,
                places: places
            )
            _ = try? snapshotStore.save(
                snapshot,
                forceFreshnessAdvance: forceFreshnessAdvance
            )
            return WanderNearbyTimelineUpdate(
                date: now,
                snapshot: snapshotStore.load() ?? snapshot,
                availability: .ready,
                reloadAfter: now.addingTimeInterval(
                    WanderNearbyWidgetAvailability.ready.reloadInterval
                )
            )
        } catch {
            return update(
                now: now,
                cachedSnapshot: cachedSnapshot,
                availability: .locationTemporarilyUnavailable,
                retryAfter: WanderNearbyWidgetAvailability
                    .locationTemporarilyUnavailable
                    .reloadInterval
            )
        }
    }

    private func update(
        now: Date,
        cachedSnapshot: WanderNearbyWidgetSnapshot?,
        availability: WanderNearbyWidgetAvailability,
        retryAfter: TimeInterval
    ) -> WanderNearbyTimelineUpdate {
        WanderNearbyTimelineUpdate(
            date: now,
            snapshot: cachedSnapshot,
            availability: availability,
            reloadAfter: now.addingTimeInterval(retryAfter)
        )
    }
}

private extension WanderNearbyWidgetAvailability {
    var reloadInterval: TimeInterval {
        switch self {
        case .ready, .noPlaces:
            15 * 60
        case .locationTemporarilyUnavailable:
            5 * 60
        case .locationAuthorizationRequired:
            60 * 60
        }
    }
}

@MainActor
private final class WanderNearbyWidgetLocationProvider:
    NSObject,
    @preconcurrency CLLocationManagerDelegate
{
    private static let maximumLocationAge: TimeInterval = 5 * 60
    private static let maximumHorizontalAccuracy: CLLocationAccuracy = 500

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var isEligibleForWidgetLocation: Bool {
        let status = manager.authorizationStatus
        let appAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
        return appAuthorized && manager.isAuthorizedForWidgetUpdates
    }

    func currentLocation() async throws -> CLLocation {
        guard isEligibleForWidgetLocation else {
            throw WanderNearbyWidgetLocationError.notAuthorized
        }
        guard continuation == nil else {
            throw WanderNearbyWidgetLocationError.requestAlreadyInFlight
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let now = Date()
        guard let location = locations
            .filter({
                $0.horizontalAccuracy >= 0
                    && $0.horizontalAccuracy <= Self.maximumHorizontalAccuracy
                    && now.timeIntervalSince($0.timestamp) <= Self.maximumLocationAge
            })
            .min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy })
        else {
            finish(throwing: WanderNearbyWidgetLocationError.unavailable)
            return
        }
        finish(returning: location)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        finish(throwing: error)
    }

    private func finish(returning location: CLLocation) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: location)
    }

    private func finish(throwing error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}

private enum WanderNearbyWidgetLocationError: Error {
    case notAuthorized
    case requestAlreadyInFlight
    case unavailable
}

@MainActor
private struct WanderNearbyMapKitSearch {
    func places(near origin: CLLocation) async throws -> [WanderNearbyPlaceSnapshot] {
        var mapItems: [MKMapItem] = []
        var seen = Set<String>()

        for radius in [
            CLLocationDistance(200),
            CLLocationDistance(400),
            CLLocationDistance(800)
        ] {
            let request = MKLocalPointsOfInterestRequest(
                center: origin.coordinate,
                radius: radius
            )
            request.pointOfInterestFilter = .includingAll
            let response = try await MKLocalSearch(request: request).start()

            for item in response.mapItems {
                guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty,
                      CLLocationCoordinate2DIsValid(item.placemark.coordinate)
                else {
                    continue
                }
                let sourceID = sourceProviderPlaceID(for: item, name: name)
                guard seen.insert(sourceID).inserted else { continue }
                mapItems.append(item)
            }

            if mapItems.count >= WanderNearbyWidgetSnapshot.maximumVisiblePlaces {
                break
            }
        }

        return mapItems
            .sorted {
                distance(from: origin, to: $0) < distance(from: origin, to: $1)
            }
            .prefix(WanderNearbyWidgetSnapshot.maximumVisiblePlaces)
            .compactMap { snapshot(for: $0, origin: origin) }
    }

    private func snapshot(
        for item: MKMapItem,
        origin: CLLocation
    ) -> WanderNearbyPlaceSnapshot? {
        guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else {
            return nil
        }

        let coordinate = item.placemark.coordinate
        let sourceID = sourceProviderPlaceID(for: item, name: name)
        let category = categoryMetadata(for: item.pointOfInterestCategory)
        return WanderNearbyPlaceSnapshot(
            id: sourceID,
            name: name,
            category: category.value,
            categoryLabel: category.label,
            categoryEmoji: category.emoji,
            rawProviderType: item.pointOfInterestCategory?.rawValue,
            address: address(for: item.placemark),
            locality: item.placemark.locality,
            region: item.placemark.administrativeArea,
            country: item.placemark.countryCode,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: sourceID,
            distanceMeters: distance(from: origin, to: item),
            websiteURLString: item.url?.absoluteString,
            phoneNumber: item.phoneNumber,
            timeZoneIdentifier: item.timeZone?.identifier,
            confidence: item.pointOfInterestCategory == nil ? 0.74 : 0.9
        )
    }

    private func categoryMetadata(
        for category: MKPointOfInterestCategory?
    ) -> (value: String, label: String, emoji: String) {
        let raw = category?.rawValue.lowercased() ?? ""

        if raw.contains("restaurant") || raw.contains("food") {
            return ("restaurants_food", "Restaurant", "🍽️")
        }
        if raw.contains("cafe") || raw.contains("bakery") {
            return ("coffee_tea_sweets", "Coffee & sweets", "☕️")
        }
        if raw.contains("nightlife") || raw.contains("brewery") || raw.contains("winery") {
            return ("bars_nightlife", "Bar & nightlife", "🍸")
        }
        if raw.contains("park") || raw.contains("beach") || raw.contains("marina") {
            return ("outdoors_nature", "Outdoors", "🌲")
        }
        if raw.contains("store") || raw.contains("market") {
            return ("shopping", "Shopping", "🛍️")
        }
        if raw.contains("museum") || raw.contains("theater") || raw.contains("music") {
            return ("things_to_do", "Things to do", "🎟️")
        }
        if raw.contains("fitness") || raw.contains("spa") || raw.contains("hospital") {
            return ("wellness_fitness", "Wellness", "🧘")
        }
        if raw.contains("hotel") {
            return ("stays", "Stay", "🛏️")
        }
        return ("place", "Place", "📍")
    }

    private func distance(from origin: CLLocation, to item: MKMapItem) -> CLLocationDistance {
        CLLocation(
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        ).distance(from: origin)
    }

    private func address(for placemark: MKPlacemark) -> String? {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")
        if !street.isEmpty { return street }

        return placemark.title?
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sourceProviderPlaceID(for item: MKMapItem, name: String) -> String {
        let coordinate = item.placemark.coordinate
        let latitude = Int((coordinate.latitude * 100_000).rounded())
        let longitude = Int((coordinate.longitude * 100_000).rounded())
        return "mapkit_\(slug(name))_\(latitude)_\(longitude)"
    }

    private func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let parts = value
            .lowercased()
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        return String(parts)
            .split(separator: "-")
            .joined(separator: "-")
    }
}

private struct WanderNearbyWidgetView: View {
    let entry: WanderNearbyEntry

    private var freshness: WanderNearbyWidgetFreshness? {
        entry.snapshot.map {
            WanderNearbyWidgetFreshness(generatedAt: $0.generatedAt, now: entry.date)
        }
    }

    private var canShowPlaces: Bool {
        entry.availability != .locationAuthorizationRequired
            && entry.snapshot?.places.isEmpty == false
            && freshness?.isUsable == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if canShowPlaces, let snapshot = entry.snapshot {
                VStack(spacing: 6) {
                    ForEach(snapshot.places) { place in
                        if let destination = WanderDeepLinkRoute
                            .nearbyPlace(candidateID: place.id)
                            .url
                        {
                            Link(destination: destination) {
                                placeRow(place, snapshot: snapshot)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .privacySensitive()
            } else {
                unavailableState
            }

            refreshFooter
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .containerBackground(for: .widget) {
            WanderNearbyPalette.canvasWarm
        }
        .widgetURL(WanderWidgetConstants.quickCaptureURL)
    }

    private var refreshFooter: some View {
        HStack(alignment: .center) {
            Button(intent: WanderRefreshNearbyPlacesIntent()) {
                Label(
                    entry.isRefreshing ? "Refreshing…" : "Refresh",
                    systemImage: "arrow.clockwise"
                )
                .font(.caption2.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(WanderNearbyPalette.terracottaDark)
            }
            .buttonStyle(.plain)
            .disabled(entry.isRefreshing)
            .accessibilityLabel(
                entry.isRefreshing
                    ? "Refreshing nearby spots"
                    : "Refresh nearby spots"
            )

            Spacer()
            if let generatedAt = entry.snapshot?.generatedAt {
                TimelineView(.everyMinute) { context in
                    Text(
                        WanderNearbyWidgetFreshness(
                            generatedAt: generatedAt,
                            now: context.date
                        ).minuteAgeLabel
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WanderNearbyPalette.textMuted)
                    .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nearby spots")
                    .font(.title2.weight(.black))
                    .fontDesign(.rounded)
                    .foregroundStyle(WanderNearbyPalette.textInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(headerSubtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WanderNearbyPalette.textMuted)
            }
            .layoutPriority(1)

            Spacer()

            Link(destination: WanderWidgetConstants.quickCaptureURL) {
                Label("See all", systemImage: "chevron.right")
                    .font(.caption.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(WanderNearbyPalette.terracottaDark)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(WanderNearbyPalette.surfaceBone)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(WanderNearbyPalette.borderHairline, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all nearby spots in I'm Here Now")
        }
    }

    private var headerSubtitle: String {
        switch entry.availability {
        case .ready:
            "tap a place to check-in"
        case .locationAuthorizationRequired:
            "location access needed"
        case .locationTemporarilyUnavailable:
            "showing the latest nearby places"
        case .noPlaces:
            "no nearby places found yet"
        }
    }

    private func placeRow(
        _ place: WanderNearbyPlaceSnapshot,
        snapshot: WanderNearbyWidgetSnapshot
    ) -> some View {
        let distanceLabel = place.distanceLabel(
            generatedAt: snapshot.generatedAt,
            now: entry.date,
            allowsExactDistance: entry.availability == .ready
        )

        return HStack(spacing: 10) {
            Text(place.categoryEmoji)
                .font(.system(size: 20))
                .frame(width: 38, height: 38)
                .background(WanderNearbyPalette.terracottaTint)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.subheadline.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(WanderNearbyPalette.textInk)
                    .lineLimit(1)

                Text("\(place.categoryLabel) · \(distanceLabel)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WanderNearbyPalette.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "plus")
                .font(.caption.weight(.black))
                .foregroundStyle(WanderNearbyPalette.terracotta)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(WanderNearbyPalette.surfaceBone)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(WanderNearbyPalette.borderHairline, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(place.name), \(place.categoryLabel), \(distanceLabel). Check in here."
        )
    }

    private var unavailableState: some View {
        VStack(spacing: 10) {
            Image(systemName: unavailableSymbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(WanderNearbyPalette.terracotta)

            Text(unavailableTitle)
                .font(.headline.weight(.black))
                .fontDesign(.rounded)
                .foregroundStyle(WanderNearbyPalette.textInk)

            Text(unavailableMessage)
                .font(.caption.weight(.medium))
                .foregroundStyle(WanderNearbyPalette.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Text("Open rec.me")
                .font(.caption.weight(.bold))
                .foregroundStyle(WanderNearbyPalette.textOnAction)
                .padding(.horizontal, 18)
                .frame(height: 32)
                .background(WanderNearbyPalette.terracottaDark)
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
        .background(WanderNearbyPalette.surfaceBone)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var unavailableSymbol: String {
        switch entry.availability {
        case .locationAuthorizationRequired:
            "location.slash.fill"
        case .noPlaces:
            "map.fill"
        case .ready, .locationTemporarilyUnavailable:
            "location.magnifyingglass"
        }
    }

    private var unavailableTitle: String {
        switch entry.availability {
        case .locationAuthorizationRequired:
            "Turn on nearby spots"
        case .noPlaces:
            "Nothing nearby yet"
        case .ready, .locationTemporarilyUnavailable:
            "Finding nearby places"
        }
    }

    private var unavailableMessage: String {
        switch entry.availability {
        case .locationAuthorizationRequired:
            "Open rec.me and allow location while using the app, then approve location for this widget."
        case .noPlaces:
            "Open rec.me to search manually or try again after moving to a new area."
        case .ready, .locationTemporarilyUnavailable:
            "WidgetKit will retry automatically. Opening rec.me can refresh it sooner."
        }
    }
}

private enum WanderNearbyPalette {
    static let canvasWarm = Color(
        red: 243.0 / 255.0,
        green: 223.0 / 255.0,
        blue: 202.0 / 255.0
    )
    static let surfaceBone = Color(
        red: 255.0 / 255.0,
        green: 247.0 / 255.0,
        blue: 234.0 / 255.0
    )
    static let textInk = Color(
        red: 44.0 / 255.0,
        green: 33.0 / 255.0,
        blue: 24.0 / 255.0
    )
    static let textMuted = Color(
        red: 123.0 / 255.0,
        green: 101.0 / 255.0,
        blue: 85.0 / 255.0
    )
    static let textOnAction = Color(
        red: 255.0 / 255.0,
        green: 247.0 / 255.0,
        blue: 234.0 / 255.0
    )
    static let borderHairline = Color(
        red: 219.0 / 255.0,
        green: 194.0 / 255.0,
        blue: 170.0 / 255.0
    )
    static let terracotta = Color(
        red: 212.0 / 255.0,
        green: 111.0 / 255.0,
        blue: 77.0 / 255.0
    )
    static let terracottaDark = Color(
        red: 169.0 / 255.0,
        green: 79.0 / 255.0,
        blue: 53.0 / 255.0
    )
    static let terracottaTint = Color(
        red: 246.0 / 255.0,
        green: 224.0 / 255.0,
        blue: 210.0 / 255.0
    )
}

private enum WanderNearbyPreviewData {
    static let date = Date()
    static let snapshot = WanderNearbyWidgetSnapshot(
        generatedAt: date,
        places: [
            place(
                id: "ggiata",
                name: "Ggiata Delicatessen",
                category: "restaurants_food",
                label: "Restaurant",
                emoji: "🥪",
                distance: 10.7
            ),
            place(
                id: "canyon-coffee",
                name: "Canyon Coffee",
                category: "coffee_tea_sweets",
                label: "Coffee & sweets",
                emoji: "☕️",
                distance: 58
            ),
            place(
                id: "gold-line",
                name: "Gold Line",
                category: "bars_nightlife",
                label: "Bar & nightlife",
                emoji: "🍸",
                distance: 112
            ),
            place(
                id: "cookbook",
                name: "Cookbook Market",
                category: "shopping",
                label: "Shopping",
                emoji: "🛍️",
                distance: 172
            ),
            place(
                id: "echo-park",
                name: "Echo Park Lake",
                category: "outdoors_nature",
                label: "Outdoors",
                emoji: "🌲",
                distance: 420
            )
        ]
    )

    private static func place(
        id: String,
        name: String,
        category: String,
        label: String,
        emoji: String,
        distance: Double
    ) -> WanderNearbyPlaceSnapshot {
        WanderNearbyPlaceSnapshot(
            id: id,
            name: name,
            category: category,
            categoryLabel: label,
            categoryEmoji: emoji,
            latitude: 34.08,
            longitude: -118.26,
            sourceProviderPlaceID: id,
            distanceMeters: distance,
            confidence: 0.9
        )!
    }
}

#Preview("Nearby Rich Visit", as: .systemLarge) {
    WanderNearbyPlacesWidget()
} timeline: {
    WanderNearbyEntry(
        date: WanderNearbyPreviewData.date,
        snapshot: WanderNearbyPreviewData.snapshot,
        availability: .ready,
        isRefreshing: false
    )
}

#Preview("Nearby Rich Visit — Refreshing", as: .systemLarge) {
    WanderNearbyPlacesWidget()
} timeline: {
    WanderNearbyEntry(
        date: WanderNearbyPreviewData.date,
        snapshot: WanderNearbyPreviewData.snapshot,
        availability: .ready,
        isRefreshing: true
    )
}

#Preview("Nearby Rich Visit — Recovering", as: .systemLarge) {
    WanderNearbyPlacesWidget()
} timeline: {
    WanderNearbyEntry(
        date: WanderNearbyPreviewData.date,
        snapshot: nil,
        availability: .locationTemporarilyUnavailable,
        isRefreshing: true
    )
}
