#if DEBUG
import UIKit
import XCTest
@testable import Wander

final class MapCapturePhotoRepositoryTests: XCTestCase {
    private let scenario = [
        "-WanderMapCapture", "-WanderUseDemoFixtures",
        "-WanderAuthenticatedUITest", "-WanderREC386PhotoFixture"
    ]

    @MainActor
    func testSyntheticProviderAndMemberPhotosLoadThroughBackend() async throws {
        let repository = MapCapturePlacePhotoRepository(launchArguments: [])
        let backend = makeBackend(repository: repository)
        let request = PlacePhotoRequest(
            placeID: "capture-place", name: "Capture Coffee", address: "Fixture address",
            latitude: 34, longitude: -118,
            sourceProvider: "google_maps", sourceProviderPlaceID: "capture-place"
        )
        let providerPhoto = try await repository.photo(for: request)
        let memberPhoto = try await repository.visibleUserPhoto(for: request)
        XCTAssertFalse(providerPhoto.requiresAccessCheck)
        XCTAssertTrue(memberPhoto.requiresAccessCheck)
        for photo in [providerPhoto, memberPhoto] {
            let data = try await backend.placePhotoImageData(
                for: photo, canonicalPlaceKey: "capture-place", variant: .profile
            )
            XCTAssertNotNil(UIImage(data: data))
        }
    }

    @MainActor
    func testREC386GalleryAndCheckInRepresentationsLoadThroughBackend() async throws {
        let repository = MapCapturePlacePhotoRepository(launchArguments: scenario)
        let backend = makeBackend(repository: repository)
        let page = try await repository.visiblePhotoGalleryPage(
            placeIDs: ["50000000-0000-0000-0000-000000000386"], after: nil, limit: 12
        )
        XCTAssertEqual(page.items.count, 1)
        let item = try XCTUnwrap(page.items.first)
        XCTAssertEqual(item.contributor?.userID, "user_ryan")
        XCTAssertEqual(item.contributor?.displayName, "Ryan")
        let checkInPhoto = memberPhoto(
            url: "", localAssetRef: "local_file:55000000-0000-0000-0000-000000000386.png"
        )
        for photo in [item.photo, checkInPhoto] {
            XCTAssertTrue(photo.requiresAccessCheck)
            let data = try await backend.placePhotoImageData(
                for: photo, canonicalPlaceKey: "rec386", variant: .profile
            )
            XCTAssertNotNil(UIImage(data: data))
        }
    }

    @MainActor
    func testREC386RequiresEveryCaptureScenarioArgument() async throws {
        for missingArgument in scenario {
            let repository = MapCapturePlacePhotoRepository(
                launchArguments: scenario.filter { $0 != missingArgument }
            )
            let page = try await repository.visiblePhotoGalleryPage(
                placeIDs: ["50000000-0000-0000-0000-000000000386"], after: nil, limit: 12
            )
            XCTAssertTrue(page.items.isEmpty, missingArgument)
            await assertRejected(memberPhoto(), by: makeBackend(repository: repository))
        }
    }

    @MainActor
    func testCaptureBackendRejectsAlteredProtectedResourceReferences() async {
        let repository = MapCapturePlacePhotoRepository(launchArguments: scenario)
        let backend = makeBackend(repository: repository)
        let invalidPhotos = [
            memberPhoto(id: "55000000-0000-0000-0000-000000000387"),
            memberPhoto(bucket: "unrelated-bucket"),
            memberPhoto(path: "user_other/54000000-0000-0000-0000-000000000386/photo.png"),
            memberPhoto(url: "https://unrelated.invalid/photo.png"),
            memberPhoto(provider: "google_places"),
            memberPhoto(localAssetRef: "local_file:55000000-0000-0000-0000-000000000386.png"),
            memberPhoto(localAssetRef: "local_file:../../unrelated.png"),
            memberPhoto(url: "", localAssetRef: "local_file:55000000-0000-0000-0000-000000000387.png"),
            memberPhoto(url: "", localAssetRef: "local_file:../../unrelated.png"),
            memberPhoto(url: ""),
            memberPhoto(id: "capture-visit-4", bucket: nil, path: nil, url: "capture://place-carousel/4"),
            memberPhoto(id: "capture-visit-03", bucket: nil, path: nil, url: "capture://place-carousel/3"),
            memberPhoto(id: "capture-visit-3", bucket: nil, path: nil, url: "capture://place-carousel/2"),
            memberPhoto(id: "capture-visit-3", bucket: nil, path: nil, url: "https://unrelated.invalid/photo.png")
        ]
        for photo in invalidPhotos {
            XCTAssertTrue(photo.requiresAccessCheck)
            await assertRejected(photo, by: backend)
        }
    }

    @MainActor
    func testSignedOutBackendStillRejectsCaptureMemberPhoto() async {
        let repository = MapCapturePlacePhotoRepository(launchArguments: scenario)
        let session = CapturePhotoTestSession()
        session.state = .signedOut
        let backend = makeBackend(repository: repository, session: session)
        await assertRejected(memberPhoto(), by: backend, expectedError: .notAuthenticated)
    }

    private func memberPhoto(
        id: String = "55000000-0000-0000-0000-000000000386",
        bucket: String? = "visit-photos",
        path: String? = "user_ryan/54000000-0000-0000-0000-000000000386/photo.png",
        url: String = "capture://place-carousel/3",
        provider: String = "visit_photo",
        localAssetRef: String? = nil
    ) -> PlacePhoto {
        PlacePhoto(
            provider: provider, providerPlaceID: id, photoURLString: url,
            width: 1_200, height: 1_200, authorName: nil,
            authorProfileURLString: nil, authorAvatarURLString: nil,
            sourcePhotoURLString: nil, flagContentURLString: nil,
            storageBucket: bucket, storagePath: path, localAssetRef: localAssetRef
        )
    }

    @MainActor
    private func makeBackend(
        repository: MapCapturePlacePhotoRepository,
        session: CapturePhotoTestSession? = nil
    ) -> WanderBackend {
        WanderBackend(
            placePhotoRepository: repository,
            featureFlagDeviceOverrides: FeatureFlagDeviceOverrideSnapshot(),
            photoAuthSession: session ?? CapturePhotoTestSession(),
            placePhotoDataDiskCache: .disabled
        )
    }

    @MainActor
    private func assertRejected(
        _ photo: PlacePhoto,
        by backend: WanderBackend,
        expectedError: WanderRemoteError = .notConfigured,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await backend.placePhotoImageData(
                for: photo, canonicalPlaceKey: "capture-rejection", variant: .profile
            )
            XCTFail("An unauthorized fixture resource must not load", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? WanderRemoteError, expectedError, file: file, line: line)
        }
    }
}

@MainActor
private final class CapturePhotoTestSession: AuthSessionProviding {
    var state: AuthState = .signedIn(AuthSession(userID: "user_joe", displayName: nil, handle: nil))
    let canPresentNativeAuth = false
    func sessionChanges() -> AsyncStream<AuthState> { AsyncStream { $0.finish() } }
    func refreshSession() async {}
    func signOut() async throws { state = .signedOut }
    func deleteAccount() async throws { state = .signedOut }
    func supabaseAccessToken() async throws -> String { "unused-fixture-token" }
    func refreshSupabaseAccessToken() async throws -> String { "unused-fixture-token" }
}
#endif
