#if DEBUG
import Foundation
import SwiftUI

/// A value snapshot of the profile currently resolved by the store.
/// Recreate it from that profile when its name or avatar changes.
struct CommonGroundPerson: Hashable, Sendable {
    let id: String
    let name: String
    let avatarURL: URL?
    let sampleAvatarTile: Int?

    init(id: String, name: String, avatarURL: URL? = nil, sampleAvatarTile: Int? = nil) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.sampleAvatarTile = sampleAvatarTile
    }

    init(profile: LocalProfile) {
        id = profile.id
        name = profile.displayName
        avatarURL = profile.avatarURL.flatMap(URL.init(string:))
        sampleAvatarTile = nil
    }

    var shortName: String {
        name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }

    var initials: String {
        name.split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    static let previewViewer = Self(id: "preview-ryan", name: "Ryan", sampleAvatarTile: 0)
    static let previewPartner = Self(id: "preview-joe", name: "Joe", sampleAvatarTile: 1)
}

/// Photo lookup metadata only; it contains no user-place notes or opinion data.
struct CommonGroundPlacePhotoReference: Hashable, Sendable {
    let placeID: String?
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let sourceProvider: String?
    let sourceProviderPlaceID: String?

    init(place: VisiblePlace) {
        // VisiblePlace.id identifies a social/save row. Photo fallback needs
        // the canonical server place, while unsynced places use provider lookup.
        placeID = place.place.serverID
        name = place.place.canonicalName
        address = place.place.address
        latitude = place.place.latitude
        longitude = place.place.longitude
        sourceProvider = place.place.sourceProvider
        sourceProviderPlaceID = place.place.sourceProviderPlaceID
    }

    var request: PlacePhotoRequest {
        PlacePhotoRequest(
            placeID: placeID,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: sourceProvider,
            sourceProviderPlaceID: sourceProviderPlaceID,
            renderVariant: .card
        )
    }
}

struct CommonGroundPersonAvatar: View {
    let person: CommonGroundPerson
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let tile = person.sampleAvatarTile {
                CommonGroundAvatar(tile: tile, size: size)
            } else {
                WanderAvatar(
                    initials: person.initials,
                    avatarURL: person.avatarURL?.absoluteString,
                    size: size
                )
            }
        }
        .accessibilityHidden(true)
    }
}

/// Uses the same provider selection, authenticated delivery, and image cache as
/// the existing place card. A failed provider image can fall back once to a
/// visible user photo; missing photos remain a category placeholder.
struct CommonGroundLivePlaceArtwork: View {
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.astirBrandMode) private var brand
    @State private var photo: PlacePhoto?
    @State private var resolvedReference: CommonGroundPlacePhotoReference?
    @State private var userFallbackReference: CommonGroundPlacePhotoReference?

    let reference: CommonGroundPlacePhotoReference
    let systemImage: String
    var providerOnly = false

    private struct LoadRequest: Equatable {
        let reference: CommonGroundPlacePhotoReference
        let usesUserFallback: Bool
    }

    private var loadRequest: LoadRequest {
        LoadRequest(reference: reference, usesUserFallback: userFallbackReference == reference)
    }

    var body: some View {
        ZStack {
            brand.raisedBackground
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(brand.accentText)

            if resolvedReference == reference, let photo {
                PlaceProfilePhotoImage(
                    photo: photo,
                    canonicalPlaceKey: reference.request.canonicalPhotoCacheKey,
                    placeName: reference.name,
                    photoRequest: reference.request,
                    variant: .card,
                    onLoadFailure: handleImageFailure
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
        .task(id: loadRequest) {
            await loadPhoto(for: loadRequest)
        }
    }

    private func loadPhoto(for load: LoadRequest) async {
        photo = nil
        resolvedReference = nil
        do {
            let resolved: PlacePhoto
            if load.usesUserFallback {
                resolved = try await backend.visibleUserPlacePhoto(for: load.reference.request)
            } else {
                resolved = try await backend.placePhoto(for: load.reference.request)
            }
            guard !Task.isCancelled, load == loadRequest else { return }
            guard !providerOnly || resolved.isGooglePlacesPhoto else { return }
            resolvedReference = load.reference
            photo = resolved
        } catch {
            // The repository already tries a visible user photo when provider
            // metadata is unavailable. Do not retry indefinitely on failure.
            guard !Task.isCancelled, load == loadRequest else { return }
            photo = nil
            resolvedReference = nil
        }
    }

    private func handleImageFailure(_ failedPhoto: PlacePhoto) {
        guard resolvedReference == reference, photo?.cacheKey == failedPhoto.cacheKey else { return }
        photo = nil
        guard !providerOnly else { return }
        if failedPhoto.isGooglePlacesPhoto, userFallbackReference != reference {
            userFallbackReference = reference
        }
    }
}
#endif
