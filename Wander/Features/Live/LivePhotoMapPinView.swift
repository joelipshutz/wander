import SwiftUI

/// Uses the place's primary image, never an actor avatar. Dense pins stay cheap
/// dots until they have room; image resolution uses the shared authorized cache.
struct LivePhotoMapPinView: View {
    let place: VisiblePlace
    let kind: LivePinKind
    let selected: Bool
    let viewed: Bool
    let compact: Bool
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color { kind == .list ? WanderTheme.stateInfo.color : brand.accent }
    private var diameter: CGFloat { selected ? 34 : 28 }

    var body: some View {
        ZStack {
            if compact && !selected {
                Circle().fill(viewed ? brand.secondaryText : color)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(brand.raisedBackground, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.24), radius: 2, y: 1)
            } else {
                LivePinPrimaryPhoto(place: place)
                    .frame(width: diameter, height: diameter)
                    .background(brand.raisedBackground)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(brand.raisedBackground, lineWidth: 1.5))
                    .overlay(Circle().stroke(brand.accent, lineWidth: selected ? 2 : 0).padding(-3))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(kind == .wanna ? color : Color.white)
                            .frame(width: 12, height: 12)
                            .background(kind == .wanna ? brand.raisedBackground : color, in: Circle())
                            .overlay(Circle().strokeBorder(kind == .wanna ? color : brand.raisedBackground, lineWidth: 1))
                            .offset(x: 3, y: -3)
                    }
                    .saturation(viewed && !selected ? 0.2 : 1)
                    .opacity(viewed && !selected ? 0.72 : 1)
                    .shadow(color: .black.opacity(selected ? 0.3 : 0.2), radius: selected ? 5 : 3, y: 2)
            }
        }
        .frame(width: 44, height: 44).contentShape(Circle())
        .accessibilityHidden(true) // The annotation button supplies its place/activity label.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: compact)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.7), value: selected)
    }
}

private struct LivePinPrimaryPhoto: View {
    let place: VisiblePlace
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var store: WanderStore
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.scenePhase) private var scenePhase
    @State private var photo: PlacePhoto?
    @State private var failedGooglePhotoID: String?
    private var request: PlacePhotoRequest { PlaceSheetPlace(visiblePlace: place).photoRequest.rendering(.listThumbnail) }
    private var requestKey: String {
        "\(PlaceSheetPlace(visiblePlace: place).photoLookupKey)|\(store.currentUser.id)|\(backend.photoSessionRevision)|\(backend.photoAccessRevision)|\(scenePhase)|\(failedGooglePhotoID ?? "ready")"
    }

    var body: some View {
        ZStack {
            brand.raisedBackground
            Image(systemName: "mappin")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(brand.secondaryText)
            if let photo {
                PlaceProfilePhotoImage(photo: photo, canonicalPlaceKey: request.canonicalPhotoCacheKey,
                    placeName: place.place.canonicalName, photoRequest: request,
                    variant: .listThumbnail, onLoadFailure: { failed in
                        if failed.isGooglePlacesPhoto { failedGooglePhotoID = failed.providerPlaceID }
                        else { self.photo = nil }
                    })
            }
        }
        .task(id: requestKey) {
            photo = nil
            guard scenePhase == .active else { return }
            let key = requestKey
            do {
                let resolved: PlacePhoto
                if let cached = backend.cachedPlacePhoto(for: request) {
                    resolved = cached
                } else {
                    resolved = try await backend.placePhoto(for: request)
                }
                let usable: PlacePhoto
                if resolved.isGooglePlacesPhoto && resolved.providerPlaceID == failedGooglePhotoID {
                    usable = try await backend.visibleUserPlacePhoto(for: request)
                } else { usable = resolved }
                try Task.checkCancellation()
                guard key == requestKey else { return }
                photo = usable
            } catch {
                guard !Task.isCancelled, key == requestKey else { return }
                photo = nil
            }
        }
    }
}
