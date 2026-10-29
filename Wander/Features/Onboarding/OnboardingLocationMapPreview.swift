import MapKit
import SwiftUI

enum OnboardingLocationContent {
    static let eyebrow = "AROUND YOU"
    static let title = "Find places nearby"
    static let message = "See places your friends recommend and save spots around you without searching for an address."
    static let privacyMessage = "Your location is yours."
    static let selectedPlaceName = "Hotchkiss Park"
}

/// The production selected-place surface with its complete photo and actions.
/// A bundled response from the real place-photo service keeps this usable offline.
struct OnboardingLocationMapPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var previewBackend = WanderBackend(placePhotoRepository: OnboardingPlacePhotoRepository())
    @StateObject private var store = WanderStore(fixtures: .empty())
    @State private var position = MapCameraPosition.region(Self.region)
    private let candidate = FirstVisitParkSuggestionPolicy.hotchkissPark
    private static let coordinate = CLLocationCoordinate2D(latitude: 34.00585, longitude: -118.4842)
    private static let region = MKCoordinateRegion(center: coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006))

    var body: some View {
        ZStack {
            Map(position: $position, interactionModes: []) {
                Marker(candidate.name, coordinate: Self.coordinate).tint(AstirTheme.signal.color)
            }
            .mapStyle(.standard(elevation: .flat))
            PlaceProfileMapSurface(
                place: PlaceSheetPlace(candidate: candidate), saves: [], tasteSaves: [],
                currentUserID: store.currentUser.id, viewerLocation: nil, action: .add,
                onOpen: {}, onAction: {}, onAddToList: {}, onReady: {}
            )
            .environmentObject(store)
            .environmentObject(previewBackend)
            .padding(.bottom, 12)
        }
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example Astir map with Hotchkiss Park selected and its full place photo")
        .accessibilityIdentifier("onboarding.location.map")
        .task(id: scenePhase) {
            guard scenePhase == .active, !reduceMotion else { return }
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 3.5)) {
                position = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 34.00545, longitude: -118.4842),
                    span: MKCoordinateSpan(latitudeDelta: 0.0045, longitudeDelta: 0.0045)))
            }
        }
    }
}
