import SwiftUI
import UIKit
import XCTest
@testable import Wander

final class PlaceProfilePresentationTests: XCTestCase {
    func testLegacyBeenActivityUsesVisitedDateThenSavedDateInsteadOfLastEdit() {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let place = place(id: "place_coffee", category: "coffee")
        let summary = summary(owner: currentUser, place: place, ratingScore: 4, tags: [])
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let visitedAt = Date(timeIntervalSince1970: 1_700_100_000)
        summary.visiblePlace.userPlace.savedAt = savedAt
        summary.visiblePlace.userPlace.updatedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let savedFallback = PlaceActivityEntry(
            summary: summary,
            visit: nil,
            kind: .legacyBeenSummary,
            currentUserID: currentUser.id
        )
        XCTAssertEqual(savedFallback.timestamp, savedAt)

        summary.visiblePlace.userPlace.visitedAt = visitedAt
        let explicitVisitDate = PlaceActivityEntry(
            summary: summary,
            visit: nil,
            kind: .legacyBeenSummary,
            currentUserID: currentUser.id
        )
        XCTAssertEqual(explicitVisitDate.timestamp, visitedAt)
    }

    @MainActor
    func testPlacePhotoImageStartsRemoteLoadFromEmptyState() async throws {
        let loadStarted = expectation(description: "Place photo load started")
        let renderedImage = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let repository = RecordingPlacePhotoRenderingRepository(
            imageData: try XCTUnwrap(renderedImage.pngData()),
            loadStarted: loadStarted
        )
        let backend = WanderBackend(placePhotoRepository: repository)
        let photo = PlacePhoto(
            provider: "google_places",
            providerPlaceID: "test-google-place",
            photoURLString: "https://lh3.googleusercontent.com/test-photo",
            width: 1600,
            height: 1200,
            authorName: "Test Photographer",
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: "https://www.google.com/maps/test-photo",
            flagContentURLString: nil,
            storageBucket: nil,
            storagePath: nil,
            localAssetRef: nil
        )
        let host = UIHostingController(
            rootView: PlaceProfilePhotoImage(photo: photo, placeName: "Test Place")
                .environmentObject(backend)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        await fulfillment(of: [loadStarted], timeout: 1.0)

        XCTAssertEqual(repository.requestedPhotos, [photo])
        window.isHidden = true
    }

    @MainActor
    func testBackendCachesRepeatedPlacePhotoMetadataAndImageLoads() async throws {
        let photo = PlacePhoto(
            provider: "google_places",
            providerPlaceID: "cached-google-place",
            photoURLString: "https://lh3.googleusercontent.com/cached-photo",
            width: 400,
            height: 300,
            authorName: nil,
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: "https://www.google.com/maps/cached-photo",
            flagContentURLString: nil,
            storageBucket: nil,
            storagePath: nil,
            localAssetRef: nil
        )
        let repository = CachingPlacePhotoRepository(photo: photo, data: Data([0x01, 0x02]))
        let backend = WanderBackend(placePhotoRepository: repository)
        let request = PlacePhotoRequest(
            name: "One Cedar",
            address: "Los Angeles, CA",
            latitude: 34.05,
            longitude: -118.24,
            sourceProvider: "google_maps",
            sourceProviderPlaceID: "cached-google-place"
        )

        let firstPhoto = try await backend.placePhoto(for: request)
        let secondPhoto = try await backend.placePhoto(for: request)
        let firstData = try await backend.placePhotoImageData(for: photo)
        let secondData = try await backend.placePhotoImageData(for: photo)

        XCTAssertEqual(firstPhoto, photo)
        XCTAssertEqual(secondPhoto, photo)
        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(repository.metadataRequestCount, 1)
        XCTAssertEqual(repository.imageRequestCount, 1)
    }

    @MainActor
    func testPlacePhotoImageReportsRemoteDecodeFailureForUserPhotoFallback() async throws {
        let failureReported = expectation(description: "Place photo failure reported")
        let repository = FailingPlacePhotoRenderingRepository()
        let backend = WanderBackend(placePhotoRepository: repository)
        let photo = PlacePhoto(
            provider: "google_places",
            providerPlaceID: "failed-google-place",
            photoURLString: "https://lh3.googleusercontent.com/failed-photo",
            width: 1600,
            height: 1200,
            authorName: nil,
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: "https://www.google.com/maps/failed-photo",
            flagContentURLString: nil,
            storageBucket: nil,
            storagePath: nil,
            localAssetRef: nil
        )
        let host = UIHostingController(
            rootView: PlaceProfilePhotoImage(
                photo: photo,
                placeName: "Failed Test Place",
                onLoadFailure: { failedPhoto in
                    XCTAssertEqual(failedPhoto, photo)
                    failureReported.fulfill()
                }
            )
            .environmentObject(backend)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()

        await fulfillment(of: [failureReported], timeout: 1.0)
        window.isHidden = true
    }

    @MainActor
    func testWidePlacePhotoKeepsHeaderControlsInsidePhoneWidth() async throws {
        let loadStarted = expectation(description: "Wide place photo load started")
        let renderedImage = UIGraphicsImageRenderer(size: CGSize(width: 2_400, height: 600)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2_400, height: 600))
        }
        let repository = RecordingPlacePhotoRenderingRepository(
            imageData: try XCTUnwrap(renderedImage.jpegData(compressionQuality: 0.8)),
            loadStarted: loadStarted
        )
        let backend = WanderBackend(placePhotoRepository: repository)
        let photo = PlacePhoto(
            provider: "google_places",
            providerPlaceID: "wide-google-place",
            photoURLString: "https://lh3.googleusercontent.com/wide-photo",
            width: 2_400,
            height: 600,
            authorName: "Test Photographer",
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: "https://www.google.com/maps/wide-photo",
            flagContentURLString: nil,
            storageBucket: nil,
            storagePath: nil,
            localAssetRef: nil
        )
        let recorder = PlacePhotoControlFrameRecorder()
        let host = UIHostingController(
            rootView: PlacePhotoControlLayoutProbe(photo: photo, recorder: recorder)
                .environmentObject(backend)
        )
        let phoneWidth: CGFloat = 393
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: phoneWidth, height: 268))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        await fulfillment(of: [loadStarted], timeout: 1.0)
        try await Task.sleep(for: .milliseconds(350))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let trailingControlFrame = try XCTUnwrap(recorder.frames.last)
        XCTAssertGreaterThanOrEqual(trailingControlFrame.minX, 0)
        XCTAssertLessThanOrEqual(trailingControlFrame.maxX, phoneWidth)
        window.isHidden = true
    }

    func testCommonTagsRequireUserAndTrustedOrTwoTrustedSupports() {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let ryan = profile(id: "user_ryan", handle: "ryan")
        let place = place(id: "place_coffee", category: "coffee")

        let summaries = [
            summary(owner: currentUser, place: place, ratingScore: 4, tags: ["quiet", "laptop time"]),
            summary(owner: maya, place: place, ratingScore: 5, tags: ["quiet", "patio"]),
            summary(owner: ryan, place: place, ratingScore: 4, tags: ["patio"])
        ]

        let tags = PlaceProfilePresenter.commonTags(from: summaries, currentUserID: currentUser.id)

        XCTAssertEqual(tags.map(\.title), ["quiet", "patio"])
        XCTAssertEqual(tags.first?.hasOwnSupport, true)
        XCTAssertFalse(tags.contains { $0.title == "laptop time" })
    }

    func testCommonTagsIgnoreInterestSignals() {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let place = place(id: "place_noodles", category: "restaurant")

        let summaries = [
            summary(owner: currentUser, place: place, ratingScore: nil, interestSignal: "must go", tags: ["cozy"]),
            summary(owner: maya, place: place, ratingScore: nil, interestSignal: "must go", tags: ["cozy"])
        ]

        let tags = PlaceProfilePresenter.commonTags(from: summaries, currentUserID: currentUser.id)

        XCTAssertEqual(tags.map(\.title), ["cozy"])
        XCTAssertFalse(tags.contains { $0.title == "must go" })
    }

    func testRatingsSeparateCurrentUserRatingFromOverallRating() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let place = place(id: "place_bar", category: "bar")
        let summaries = [
            summary(owner: currentUser, place: place, ratingScore: 3, tags: []),
            summary(owner: maya, place: place, ratingScore: 5, tags: [])
        ]

        let overallRating = try XCTUnwrap(PlaceProfilePresenter.overallRating(from: summaries, currentUserID: currentUser.id))
        let ownRating = try XCTUnwrap(PlaceProfilePresenter.ownRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertEqual(overallRating.source, .trusted)
        XCTAssertEqual(overallRating.score, 5)
        XCTAssertEqual(overallRating.count, 1)
        XCTAssertEqual(ownRating.source, .own)
        XCTAssertEqual(ownRating.score, 3)
        XCTAssertEqual(ownRating.count, 1)
    }

    func testOwnRatingUsesAggregatedRatedVisitCount() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let place = place(id: "place_alibi", category: "bar")
        let summaries = [
            summary(owner: currentUser, place: place, ratingScore: 4.7, recommendedCount: 3, tags: [])
        ]

        let ownRating = try XCTUnwrap(PlaceProfilePresenter.ownRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertEqual(ownRating.source, .own)
        XCTAssertEqual(ownRating.displayScore, "4.7")
        XCTAssertEqual(ownRating.count, 3)
        XCTAssertEqual(ownRating.subtitle, "3 visits")
    }

    func testOverallRatingAveragesTrustedRatingsWhenUnsaved() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let ryan = profile(id: "user_ryan", handle: "ryan")
        let place = place(id: "place_hike", category: "hike")
        let summaries = [
            summary(owner: maya, place: place, ratingScore: 4, tags: []),
            summary(owner: ryan, place: place, ratingScore: 5, tags: [])
        ]

        let rating = try XCTUnwrap(PlaceProfilePresenter.overallRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertEqual(rating.source, .trusted)
        XCTAssertEqual(rating.score, 4.5)
        XCTAssertEqual(rating.count, 2)
    }

    func testOverallRatingUsesAggregatedTrustedRatingCounts() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let ryan = profile(id: "user_ryan", handle: "ryan")
        let place = place(id: "place_tacos", category: "restaurant")
        let summaries = [
            summary(owner: maya, place: place, ratingScore: 4, recommendedCount: 2, tags: []),
            summary(owner: ryan, place: place, ratingScore: 5, recommendedCount: 1, tags: [])
        ]

        let rating = try XCTUnwrap(PlaceProfilePresenter.overallRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertEqual(rating.source, .trusted)
        XCTAssertEqual(rating.score, 4.333333333333333, accuracy: 0.0001)
        XCTAssertEqual(rating.count, 3)
        XCTAssertEqual(rating.subtitle, "3 ratings")
    }

    func testCurrentUserWannaSaveCanShowTrustedOverallButNoOwnRating() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let place = place(id: "place_want", category: "restaurant")
        let summaries = [
            summary(owner: currentUser, place: place, status: .wannaGo, ratingScore: 4, tags: []),
            summary(owner: maya, place: place, ratingScore: 5, tags: [])
        ]

        let overallRating = try XCTUnwrap(PlaceProfilePresenter.overallRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertNil(PlaceProfilePresenter.ownRating(from: summaries, currentUserID: currentUser.id))
        XCTAssertEqual(overallRating.source, .trusted)
        XCTAssertEqual(overallRating.score, 5)
    }

    func testOverallRatingDoesNotFallbackToCurrentUsersOwnAggregate() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let place = place(id: "place_solo", category: "coffee")
        let summaries = [
            summary(owner: currentUser, place: place, ratingScore: 5, tags: [])
        ]

        let ownRating = try XCTUnwrap(PlaceProfilePresenter.ownRating(from: summaries, currentUserID: currentUser.id))

        XCTAssertNil(PlaceProfilePresenter.overallRating(from: summaries, currentUserID: currentUser.id))
        XCTAssertEqual(ownRating.score, 5)
    }

    func testFitRatingIsNilWhenEvidenceIsThin() {
        let currentUser = profile(id: "user_joe", handle: "joe")

        let presentation = PlaceProfilePresenter.presentation(
            placeID: "place_unknown",
            category: "coffee",
            saves: [],
            tasteSaves: [],
            currentUserID: currentUser.id
        )

        XCTAssertNil(presentation.fitRating)
        XCTAssertNil(presentation.overallRating)
        XCTAssertNil(presentation.ownRating)
        XCTAssertTrue(presentation.commonTags.isEmpty)
    }

    func testFitRatingUsesTrustedRatingsCategoryAndTagHistory() throws {
        let currentUser = profile(id: "user_joe", handle: "joe")
        let maya = profile(id: "user_maya", handle: "maya")
        let ryan = profile(id: "user_ryan", handle: "ryan")
        let selectedPlace = place(id: "place_selected", category: "coffee")
        let likedPlace = place(id: "place_liked", category: "coffee")

        let selectedSaves = [
            summary(owner: maya, place: selectedPlace, ratingScore: 5, tags: ["quiet", "wifi solid"]),
            summary(owner: ryan, place: selectedPlace, ratingScore: 4, tags: ["quiet"])
        ]
        let tasteSaves = [
            summary(owner: currentUser, place: likedPlace, ratingScore: 5, tags: ["quiet", "outlets"])
        ]

        let presentation = PlaceProfilePresenter.presentation(
            placeID: selectedPlace.id,
            category: selectedPlace.category,
            saves: selectedSaves,
            tasteSaves: tasteSaves,
            currentUserID: currentUser.id
        )

        let fit = try XCTUnwrap(presentation.fitRating)
        XCTAssertEqual(presentation.overallRating?.score, 4.5)
        XCTAssertNil(presentation.ownRating)
        XCTAssertGreaterThanOrEqual(fit.score, 8)
        XCTAssertEqual(presentation.commonTags.map(\.title), ["quiet"])
        XCTAssertTrue(fit.reasons.contains { $0.contains("coffee, tea, & sweets") })
        XCTAssertTrue(fit.reasons.contains { $0.contains("quiet") })
    }

    private func profile(id: String, handle: String) -> LocalProfile {
        LocalProfile(
            localID: "local_\(id)",
            serverID: id,
            handle: handle,
            displayName: handle.capitalized,
            syncState: .synced
        )
    }

    private func place(id: String, category: String) -> LocalPlace {
        LocalPlace(
            localID: "local_\(id)",
            serverID: id,
            canonicalName: id.replacingOccurrences(of: "_", with: " ").capitalized,
            category: category,
            locality: "Los Angeles",
            latitude: 34.05,
            longitude: -118.25,
            sourceProvider: "mapkit",
            syncState: .synced
        )
    }

    private func summary(
        owner: LocalProfile,
        place: LocalPlace,
        status: PlaceStatus? = nil,
        ratingScore: Double?,
        recommendedCount: Int? = nil,
        interestSignal: String? = nil,
        tags: [String]
    ) -> PlaceSaveSummary {
        let resolvedStatus = status ?? (ratingScore == nil ? .wannaGo : .been)
        let userPlace = LocalUserPlace(
            localID: "local_up_\(owner.id)_\(place.id)",
            serverID: "up_\(owner.id)_\(place.id)",
            userID: owner.id,
            placeID: place.id,
            status: resolvedStatus,
            visibility: .followers,
            note: nil,
            ratingScore: ratingScore,
            recommendedScore: ratingScore,
            recommendedCount: recommendedCount ?? (ratingScore == nil ? 0 : 1),
            sourceType: "test",
            syncState: .synced
        )
        userPlace.ratingScore = ratingScore
        userPlace.recommendedScore = ratingScore
        let visiblePlace = VisiblePlace(id: userPlace.id, place: place, userPlace: userPlace, owner: owner)
        var attributes: [LocalPlaceAttribute] = []

        if let interestSignal {
            attributes.append(attribute(userPlaceID: userPlace.id, key: "interest_signal", valueType: "emoji_scale", value: interestSignal))
        }

        if !tags.isEmpty {
            attributes.append(attribute(userPlaceID: userPlace.id, key: "\(place.category)_tags", valueType: "multi_tag", values: tags))
        }

        return PlaceSaveSummary(visiblePlace: visiblePlace, attributes: attributes)
    }

    private func attribute(userPlaceID: String, key: String, valueType: String, value: String) -> LocalPlaceAttribute {
        LocalPlaceAttribute(
            localID: "local_attr_\(userPlaceID)_\(key)",
            serverID: nil,
            userPlaceID: userPlaceID,
            questionKey: key,
            valueType: valueType,
            valueJSON: json(value),
            syncState: .synced
        )
    }

    private func attribute(userPlaceID: String, key: String, valueType: String, values: [String]) -> LocalPlaceAttribute {
        LocalPlaceAttribute(
            localID: "local_attr_\(userPlaceID)_\(key)",
            serverID: nil,
            userPlaceID: userPlaceID,
            questionKey: key,
            valueType: valueType,
            valueJSON: json(values),
            syncState: .synced
        )
    }

    private func json<T: Encodable>(_ value: T) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!
    }
}

@MainActor
private final class RecordingPlacePhotoRenderingRepository: PlacePhotoRepository {
    let imageData: Data
    let loadStarted: XCTestExpectation
    private(set) var requestedPhotos: [PlacePhoto] = []

    init(imageData: Data, loadStarted: XCTestExpectation) {
        self.imageData = imageData
        self.loadStarted = loadStarted
    }

    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        throw WanderRemoteError.invalidResponse("Unexpected metadata request")
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        throw WanderRemoteError.invalidResponse("Unexpected fallback metadata request")
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        requestedPhotos.append(photo)
        loadStarted.fulfill()
        return imageData
    }
}

@MainActor
private final class FailingPlacePhotoRenderingRepository: PlacePhotoRepository {
    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        throw WanderRemoteError.invalidResponse("Unexpected metadata request")
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        throw WanderRemoteError.invalidResponse("Unexpected fallback metadata request")
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        Data([0x00, 0x01, 0x02])
    }
}

@MainActor
private final class CachingPlacePhotoRepository: PlacePhotoRepository {
    let resolvedPhoto: PlacePhoto
    let data: Data
    private(set) var metadataRequestCount = 0
    private(set) var imageRequestCount = 0

    init(photo: PlacePhoto, data: Data) {
        resolvedPhoto = photo
        self.data = data
    }

    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        metadataRequestCount += 1
        return resolvedPhoto
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        resolvedPhoto
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        imageRequestCount += 1
        return data
    }
}

@MainActor
private final class PlacePhotoControlFrameRecorder {
    var frames: [CGRect] = []
}

private struct PlacePhotoControlLayoutProbe: View {
    let photo: PlacePhoto
    let recorder: PlacePhotoControlFrameRecorder

    var body: some View {
        ZStack {
            Color.clear

            PlaceProfilePhotoImage(photo: photo, placeName: "Wide Test Place")

            HStack {
                Color.blue
                    .frame(width: 42, height: 42)

                Spacer()

                Color.green
                    .frame(width: 42, height: 42)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: PlacePhotoTrailingControlFrameKey.self,
                                value: proxy.frame(in: .global)
                            )
                        }
                    }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 268)
        .clipped()
        .onPreferenceChange(PlacePhotoTrailingControlFrameKey.self) { frame in
            recorder.frames.append(frame)
        }
    }
}

private struct PlacePhotoTrailingControlFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
