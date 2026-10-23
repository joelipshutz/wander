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
    @Environment(\.displayScale) private var displayScale
    @State private var loadedPhoto: ListPlaceResolvedPhoto?
    @State private var loadedKey: String?
    private var request: PlacePhotoRequest { PlaceSheetPlace(visiblePlace: place).photoRequest.rendering(.listThumbnail) }
    private var authorizationScopeKey: String {
        "\(store.currentUser.id)|\(backend.photoSessionRevision)|\(backend.photoAccessRevision)|\(scenePhase)"
    }
    private var requestKey: String { "\(request.lookupKey)|\(authorizationScopeKey)" }

    var body: some View {
        ZStack {
            brand.raisedBackground
            Image(systemName: "mappin")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(brand.secondaryText)
            if loadedKey == requestKey, let loadedPhoto {
                Image(uiImage: loadedPhoto.image).resizable().scaledToFill()
            }
        }
        .clipped()
        .task(id: requestKey) {
            loadedPhoto = nil; loadedKey = nil
            guard scenePhase == .active else { return }
            let key = requestKey
            let pixelSize = max(PlacePhotoRenderVariant.listThumbnail.minimumDecodePixelDimension ?? 1,
                                Int(ceil(34 * displayScale)))
            let resolved = await LivePinPhotoResolver.resolveImage(request: request,
                authorizationScopeKey: authorizationScopeKey, backend: backend, targetPixelSize: pixelSize)
            guard !Task.isCancelled, key == requestKey else { return }
            loadedPhoto = resolved; loadedKey = key
        }
        .onDisappear {
            if loadedPhoto?.photo.requiresAccessCheck == true { loadedPhoto = nil; loadedKey = nil }
        }
    }
}

/// Only expanded annotations mount a photo view. Coalesce their metadata lookups
/// through the existing batch infrastructure, while keeping provider-first pins.
@MainActor
enum LivePinPhotoResolver {
    static func resolve(request: PlacePhotoRequest, authorizationScopeKey: String,
                        backend: WanderBackend, batcher: ListPlacePhotoBatcher = .shared,
                        retryDelayNanoseconds: UInt64 = 300_000_000) async -> PlacePhoto? {
        let session = backend.photoSessionRevision, access = backend.photoAccessRevision
        let viewer = backend.photoViewerID
        func isCurrent() -> Bool {
            !Task.isCancelled && session == backend.photoSessionRevision
                && access == backend.photoAccessRevision && viewer == backend.photoViewerID
        }
        for attempt in 0..<2 {
            guard isCurrent() else { return nil }
            let resolution = await batcher.photo(for: request, eligibleUserIDs: [],
                authorizationScopeKey: authorizationScopeKey, backend: backend)
            guard isCurrent(), !resolution.wasCancelled else { return nil }
            if let photo = resolution.photo { return photo }
            // Batch misses include transient provider failures. Retry once;
            // genuinely missing photos retain the honest pin placeholder.
            if attempt == 0 {
                do { try await Task.sleep(nanoseconds: retryDelayNanoseconds) }
                catch { return nil }
            }
        }
        guard isCurrent() else { return nil }
        let fallback = try? await backend.visibleUserPlacePhoto(for: request)
        return isCurrent() ? fallback : nil
    }

    static func resolveImage(request: PlacePhotoRequest, authorizationScopeKey: String,
                             backend: WanderBackend, targetPixelSize: Int,
                             batcher: ListPlacePhotoBatcher = .shared,
                             retryDelayNanoseconds: UInt64 = 300_000_000) async -> ListPlaceResolvedPhoto? {
        let session = backend.photoSessionRevision, access = backend.photoAccessRevision
        let viewer = backend.photoViewerID
        func isCurrent() -> Bool {
            !Task.isCancelled && session == backend.photoSessionRevision
                && access == backend.photoAccessRevision && viewer == backend.photoViewerID
        }
        let primary: PlacePhoto?
        if let cached = backend.cachedPlacePhoto(for: request) { primary = cached }
        else {
            primary = await resolve(request: request, authorizationScopeKey: authorizationScopeKey,
                backend: backend, batcher: batcher, retryDelayNanoseconds: retryDelayNanoseconds)
        }
        guard isCurrent(), let primary else { return nil }
        do {
            if let resolved = try await render(primary, request: request, backend: backend,
                targetPixelSize: targetPixelSize, retryDelayNanoseconds: retryDelayNanoseconds,
                isCurrent: isCurrent) { return resolved }
        } catch { return nil }
        guard isCurrent(), primary.isGooglePlacesPhoto,
              let fallback = try? await backend.visibleUserPlacePhoto(for: request), isCurrent() else { return nil }
        return try? await render(fallback, request: request, backend: backend,
            targetPixelSize: targetPixelSize, retryDelayNanoseconds: retryDelayNanoseconds, isCurrent: isCurrent)
    }

    private static func render(_ photo: PlacePhoto, request: PlacePhotoRequest, backend: WanderBackend,
                               targetPixelSize: Int, retryDelayNanoseconds: UInt64,
                               isCurrent: () -> Bool) async throws -> ListPlaceResolvedPhoto? {
        for attempt in 0..<2 {
            guard isCurrent() else { return nil }
            do {
                // The existing backend validates protected media and bounds all
                // image downloads. Keep that boundary on every retry.
                let data = try await backend.placePhotoImageData(for: photo,
                    canonicalPlaceKey: request.canonicalPhotoCacheKey, variant: .listThumbnail)
                guard isCurrent(),
                      let image = await PlacePhotoImagePipeline.shared.image(from: data,
                        canonicalPlaceKey: request.canonicalPhotoCacheKey, photoKey: photo.cacheKey,
                        targetPixelSize: targetPixelSize), isCurrent() else { return nil }
                return ListPlaceResolvedPhoto(photo: photo, image: image.image)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard isCurrent(), attempt == 0, isTransientImageError(error) else { return nil }
                try await Task.sleep(nanoseconds: retryDelayNanoseconds)
            }
        }
        return nil
    }

    static func isTransientImageError(_ error: Error) -> Bool {
        if let remoteError = error as? WanderRemoteError {
            // Public image HTTP failures currently lose their status code in
            // the repository. Give that exact error one bounded retry too.
            return remoteError == .invalidResponse("Place photo download failed")
        }
        guard let urlError = error as? URLError else { return false }
        return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                .notConnectedToInternet, .resourceUnavailable].contains(urlError.code)
    }

}
