import SwiftUI
import MapKit

/// Propagates the root's immutable, account-scoped launch decision to sheets.
private struct LiveExperienceEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var liveExperienceEnabled: Bool {
        get { self[LiveExperienceEnvironmentKey.self] }
        set { self[LiveExperienceEnvironmentKey.self] = newValue }
    }
}

/// One memory-only demo session is shared by the Live reply and Profile inbox.
/// Hardware and ordinary launches never create a simulated repository.
@MainActor
final class LivePrivateMessageSession: ObservableObject {
    @Published private(set) var repository: (any PrivateMessageRepository)?
    private var identity: String?
    func configure(userID: String, authenticatedUITest: Bool, enabled: Bool,
                   participants: [PrivateMessageParticipant]) {
        let next = "\(userID)|\(authenticatedUITest)|\(enabled)"
        guard identity != next else { return }
        identity = next
        repository = nil
        #if DEBUG && targetEnvironment(simulator)
        repository = PrivateMessageUITestFixtures.make(userID: userID,
            authenticatedUITest: authenticatedUITest, unifiedLiveEnabled: enabled,
            participants: participants)
        #endif
    }
}

private struct LiveMessageSessionKey: EnvironmentKey {
    static let defaultValue: LivePrivateMessageSession? = nil
}
extension EnvironmentValues {
    var liveMessageSession: LivePrivateMessageSession? {
        get { self[LiveMessageSessionKey.self] }
        set { self[LiveMessageSessionKey.self] = newValue }
    }
}

/// Explicit Astir review defaults, not universal platform standards.
enum LiveReviewContinuity {
    static let feedReturnInterval: TimeInterval = 30 * 60
    static let viewedPinInterval: TimeInterval = 24 * 60 * 60
    static func keepsFeedPosition(scrolled: Bool, departedAt: Date?, now: Date = .now) -> Bool {
        guard scrolled, let departedAt else { return false }
        return (0...feedReturnInterval).contains(now.timeIntervalSince(departedAt))
    }
}

enum LivePinKind: String { case checkIn, wanna, list
    var symbol: String {
        switch self { case .checkIn: "checkmark"; case .wanna: "bookmark.fill"; case .list: "list.bullet" }
    }
}

struct LiveMapPinView: View {
    let kind: LivePinKind
    let selected: Bool
    let viewed: Bool
    let compact: Bool
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var color: Color { kind == .list ? WanderTheme.stateInfo.color : brand.accent }
    var body: some View {
        ZStack {
            if compact && !selected {
                Circle().fill(viewed ? brand.secondaryText : color)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(brand.raisedBackground, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.24), radius: 2, y: 1)
            } else {
                Image(systemName: kind.symbol)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(kind == .wanna ? color : Color.white)
                    .frame(width: selected ? 34 : 28, height: selected ? 34 : 28)
                    .background {
                        Circle().fill(kind == .wanna ? brand.raisedBackground : color)
                        Circle().fill(LinearGradient(colors: [.white.opacity(0.28), .clear, .black.opacity(0.1)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(kind == .wanna ? color : .white.opacity(0.9), lineWidth: 2))
                    .overlay(Circle().stroke(brand.primaryText, lineWidth: selected ? 2 : 0).padding(-3))
                    .saturation(viewed && !selected ? 0.2 : 1)
                    .opacity(viewed && !selected ? 0.72 : 1)
                    .shadow(color: .black.opacity(selected ? 0.3 : 0.2), radius: selected ? 5 : 3, y: 2)
            }
        }
        .frame(width: 44, height: 44).contentShape(Circle())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: compact)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.7), value: selected)
    }
}

enum LivePinDensity {
    /// Keep deterministic individual dots, never merge people into numbered clusters.
    static func compactIDs(points: [(id: String, point: CGPoint)], selectedID: String?, minimumSpacing: CGFloat = 38) -> Set<String> {
        let sorted = points.sorted {
            if ($0.id == selectedID) != ($1.id == selectedID) { return $0.id == selectedID }
            return $0.id < $1.id
        }
        guard minimumSpacing > 0, minimumSpacing.isFinite else { return [] }
        struct Cell: Hashable { let x: CGFloat; let y: CGFloat }
        var buckets: [Cell: [CGPoint]] = [:], compact: Set<String> = []
        for entry in sorted where entry.point.x.isFinite && entry.point.y.isFinite {
            let cell = Cell(x: floor(entry.point.x / minimumSpacing), y: floor(entry.point.y / minimumSpacing))
            let overlaps = (-1...1).contains { dx in
                (-1...1).contains { dy in
                    (buckets[Cell(x: cell.x + CGFloat(dx), y: cell.y + CGFloat(dy))] ?? []).contains {
                        hypot($0.x - entry.point.x, $0.y - entry.point.y) < minimumSpacing
                    }
                }
            }
            if entry.id != selectedID && overlaps { compact.insert(entry.id) }
            else { buckets[cell, default: []].append(entry.point) }
        }
        return compact
    }
}

enum LiveViewedPinHistory {
    private static func key(_ userID: String) -> String { "astir.live.viewedPins." + userID }
    static func isViewed(_ id: String, dates: [String: Date], now: Date = .now) -> Bool {
        guard let date = dates[id] else { return false }
        return (0..<LiveReviewContinuity.viewedPinInterval).contains(now.timeIntervalSince(date))
    }
    static func load(userID: String, defaults: UserDefaults = .standard, now: Date = .now) -> [String: Date] {
        guard let data = defaults.data(forKey: key(userID)),
              let dates = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
        return dates.filter { isViewed($0.key, dates: dates, now: now) }
    }
    static func save(_ dates: [String: Date], userID: String, defaults: UserDefaults = .standard, now: Date = .now) {
        let recent = dates.filter { isViewed($0.key, dates: dates, now: now) }.sorted { $0.value > $1.value }.prefix(512)
        if let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: recent.map { ($0.key, $0.value) })) {
            defaults.set(data, forKey: key(userID))
        }
    }
}

enum LiveMapViewportPolicy {
    /// Preserve the geographic focus at the center of the exposed map, while
    /// zooming out just enough to fit the old footprint in the smaller window.
    static func fittedRegion(_ region: MKCoordinateRegion, size: CGSize, from oldRect: CGRect, to newRect: CGRect) -> MKCoordinateRegion? {
        guard [size.width, size.height, oldRect.minX, oldRect.minY, oldRect.width, oldRect.height,
               newRect.minX, newRect.minY, newRect.width, newRect.height].allSatisfy(\.isFinite),
              size.width > 0, size.height > 0, oldRect.width > 0, newRect.width > 0,
              oldRect.height > 44, newRect.height > 44,
              CLLocationCoordinate2DIsValid(region.center),
              region.span.latitudeDelta.isFinite, region.span.latitudeDelta > 0, region.span.latitudeDelta < 180,
              region.span.longitudeDelta.isFinite, region.span.longitudeDelta > 0,
              region.span.longitudeDelta < 180 else { return nil }
        let center = MKMapPoint(region.center)
        let width = region.span.longitudeDelta / 360 * MKMapRect.world.width
        let units = width / size.width
        let focus = MKMapPoint(x: center.x + (oldRect.midX - size.width / 2) * units,
                               y: center.y + (oldRect.midY - size.height / 2) * units)
        let widthRatio = oldRect.width / newRect.width
        let heightRatio = oldRect.height / newRect.height
        let ratio = newRect.height < oldRect.height
            ? max(widthRatio, heightRatio) : min(widthRatio, heightRatio)
        let nextUnits = units * ratio
        let nextCenter = MKMapPoint(x: focus.x - (newRect.midX - size.width / 2) * nextUnits,
                                    y: focus.y - (newRect.midY - size.height / 2) * nextUnits)
        let rect = MKMapRect(x: nextCenter.x - size.width * nextUnits / 2,
                             y: nextCenter.y - size.height * nextUnits / 2,
                             width: size.width * nextUnits, height: size.height * nextUnits)
        return MKCoordinateRegion(rect)
    }

    /// Restore the original geographic focus without clipping the place just
    /// closed. A half-sheet may expose pins outside the tighter full-map frame;
    /// widen only enough to keep that pin's tap target inside the exposed map.
    static func restoredRegion(_ region: MKCoordinateRegion, keeping coordinate: CLLocationCoordinate2D?,
                               size: CGSize, exposedRect: CGRect, padding: CGFloat = 30) -> MKCoordinateRegion {
        guard let coordinate, CLLocationCoordinate2DIsValid(coordinate),
              CLLocationCoordinate2DIsValid(region.center),
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              region.span.longitudeDelta.isFinite, region.span.longitudeDelta > 0,
              region.span.longitudeDelta < 180 else { return region }
        let safe = exposedRect.insetBy(dx: padding, dy: padding)
        let centerPoint = CGPoint(x: size.width / 2, y: size.height / 2)
        guard safe.minX < centerPoint.x, safe.maxX > centerPoint.x,
              safe.minY < centerPoint.y, safe.maxY > centerPoint.y else { return region }
        let center = MKMapPoint(region.center), pin = MKMapPoint(coordinate)
        let world = MKMapRect.world.width
        let dx = (pin.x - center.x + world * 1.5).truncatingRemainder(dividingBy: world) - world / 2
        let dy = pin.y - center.y
        let units = region.span.longitudeDelta / 360 * world / size.width
        let horizontalRoom = dx < 0 ? centerPoint.x - safe.minX : safe.maxX - centerPoint.x
        let verticalRoom = dy < 0 ? centerPoint.y - safe.minY : safe.maxY - centerPoint.y
        let scale = max(1, abs(dx) / (units * horizontalRoom), abs(dy) / (units * verticalRoom))
        guard scale.isFinite, scale > 1, region.span.longitudeDelta * scale < 180 else { return region }
        let width = units * size.width * scale, height = units * size.height * scale
        var restored = MKCoordinateRegion(MKMapRect(x: center.x - width / 2, y: center.y - height / 2,
                                                    width: width, height: height))
        restored.center = region.center
        return restored
    }

    static func revealOffset(pin: CGPoint, exposedRect: CGRect, padding: CGFloat = 24) -> CGSize {
        let safe = exposedRect.insetBy(dx: padding, dy: padding)
        guard safe.width > 0, safe.height > 0 else { return .zero }
        // A tapped pin was visible before the card appeared. Move only if its
        // bottom is now covered; don't center pins that are already readable.
        guard pin.y > safe.maxY else { return .zero }
        return CGSize(width: pin.x - min(max(pin.x, safe.minX), safe.maxX), height: pin.y - safe.maxY)
    }
}
