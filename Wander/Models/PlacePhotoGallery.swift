import Foundation

struct PlacePhotoGalleryCursor: Equatable {
    let createdAt: Date
    let sortOrder: Int
    let photoID: String
}

struct PlacePhotoContributor: Equatable {
    let userID: String
    let displayName: String
    let handle: String
    let avatarURLString: String?

    var avatarURL: URL? {
        avatarURLString.flatMap(URL.init(string:))
    }

    var initials: String {
        let parts = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let value = String(parts)
        return value.isEmpty ? "?" : value.uppercased()
    }
}

struct PlacePhotoGalleryItem: Identifiable, Equatable {
    let photo: PlacePhoto
    let contributor: PlacePhotoContributor?
    let capturedAt: Date?
    let status: PlaceStatus?

    var id: String {
        "\(photo.provider)|\(photo.providerPlaceID)"
    }

    var isGooglePlacesPhoto: Bool {
        photo.isGooglePlacesPhoto
    }

    static func google(_ photo: PlacePhoto) -> PlacePhotoGalleryItem {
        PlacePhotoGalleryItem(
            photo: photo,
            contributor: nil,
            capturedAt: nil,
            status: nil
        )
    }
}

struct PlacePhotoGalleryPage: Equatable {
    let items: [PlacePhotoGalleryItem]
    let nextCursor: PlacePhotoGalleryCursor?
    let hasMore: Bool
}

enum PlacePhotoGalleryPresenter {
    static func items(
        providerPhoto: PlacePhoto?,
        userPhotos: [PlacePhotoGalleryItem]
    ) -> [PlacePhotoGalleryItem] {
        var seen = Set<String>()
        var result: [PlacePhotoGalleryItem] = []

        if let providerPhoto, providerPhoto.isGooglePlacesPhoto {
            let item = PlacePhotoGalleryItem.google(providerPhoto)
            seen.insert(item.id)
            result.append(item)
        }

        for item in userPhotos where item.contributor != nil {
            guard !seen.contains(item.id) else { continue }
            seen.insert(item.id)
            result.append(item)
        }

        return result
    }

    static func merging(
        existing: [PlacePhotoGalleryItem],
        incoming: [PlacePhotoGalleryItem]
    ) -> [PlacePhotoGalleryItem] {
        var seen = Set(existing.map(\.id))
        var result = existing
        for item in incoming where !seen.contains(item.id) {
            seen.insert(item.id)
            result.append(item)
        }
        return result
    }

    static func shouldLoadMore(
        visibleItemID: String,
        items: [PlacePhotoGalleryItem],
        threshold: Int = 6
    ) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == visibleItemID }) else {
            return false
        }
        return index >= max(0, items.count - max(1, threshold))
    }

    static func positionLabel(selectedID: String?, items: [PlacePhotoGalleryItem]) -> String? {
        guard !items.isEmpty else { return nil }
        let selectedIndex = selectedID
            .flatMap { selectedID in items.firstIndex(where: { $0.id == selectedID }) }
            ?? 0
        return "\(selectedIndex + 1) of \(items.count)"
    }
}
