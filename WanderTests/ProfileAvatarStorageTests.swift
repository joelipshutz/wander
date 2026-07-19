import UIKit
import XCTest
@testable import Wander

@MainActor
final class ProfileAvatarStorageTests: XCTestCase {
    func testImageProcessorProducesSquareBoundedJPEG() throws {
        let sourceImage = makeImage(size: CGSize(width: 800, height: 400))
        let sourceData = try XCTUnwrap(sourceImage.jpegData(compressionQuality: 1))

        let jpegData = try WanderImageProcessor.squareJPEGData(
            from: sourceData,
            pixelSize: 128,
            compressionQuality: 0.85
        )
        let outputImage = try XCTUnwrap(UIImage(data: jpegData))

        XCTAssertEqual(outputImage.size.width, 128, accuracy: 0.5)
        XCTAssertEqual(outputImage.size.height, 128, accuracy: 0.5)
        XCTAssertEqual(outputImage.scale, 1, accuracy: 0.01)
        XCTAssertGreaterThan(jpegData.count, 0)
    }

    func testImageProcessorRejectsInvalidData() {
        XCTAssertThrowsError(
            try WanderImageProcessor.squareJPEGData(from: Data("not an image".utf8))
        ) { error in
            XCTAssertEqual(error as? WanderImageProcessingError, .invalidImageData)
        }
    }

    func testProfileAvatarStorageWritesAndDeletesAvatarFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-avatar-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ProfileAvatarStorage(directoryURL: directory)
        let data = Data([0xFF, 0xD8, 0xFF, 0xD9])

        let url = try storage.writeAvatarData(data)

        XCTAssertEqual(url.lastPathComponent, "current-user-avatar.jpg")
        XCTAssertEqual(try Data(contentsOf: url), data)

        try storage.deleteAvatar()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNoThrow(try storage.deleteAvatar())
    }

    func testAvatarImagePipelineDownsamplesToRequestedPixelSizeAndReusesDecodedImage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("avatar-image-pipeline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("avatar.jpg")
        let sourceData = try XCTUnwrap(
            makeImage(size: CGSize(width: 800, height: 400)).jpegData(compressionQuality: 1)
        )
        try sourceData.write(to: imageURL, options: [.atomic])
        let request = try XCTUnwrap(
            WanderAvatarImageRequest(
                avatarURL: imageURL.absoluteString,
                targetPixelSize: 96
            )
        )
        let pipeline = WanderAvatarImagePipeline(countLimit: 4)

        let firstResult = await pipeline.image(for: request)
        let first = try XCTUnwrap(firstResult)
        let secondResult = await pipeline.image(for: request)
        let second = try XCTUnwrap(secondResult)

        XCTAssertLessThanOrEqual(max(first.pixelSize.width, first.pixelSize.height), 96)
        XCTAssertGreaterThan(min(first.pixelSize.width, first.pixelSize.height), 0)
        XCTAssertTrue(first === second)
    }

    func testAvatarImagePipelineInvalidatesLocalFileWhenRevisionChanges() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("avatar-image-invalidation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("avatar.jpg")
        let originalData = try XCTUnwrap(
            makeImage(size: CGSize(width: 480, height: 240)).jpegData(compressionQuality: 1)
        )
        try originalData.write(to: imageURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: imageURL.path
        )
        let request = try XCTUnwrap(
            WanderAvatarImageRequest(
                avatarURL: imageURL.absoluteString,
                targetPixelSize: 80
            )
        )
        let pipeline = WanderAvatarImagePipeline(countLimit: 4)
        let firstResult = await pipeline.image(for: request)
        let first = try XCTUnwrap(firstResult)

        let replacementData = try XCTUnwrap(
            makeImage(size: CGSize(width: 240, height: 480)).jpegData(compressionQuality: 0.75)
        )
        try replacementData.write(to: imageURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)],
            ofItemAtPath: imageURL.path
        )

        let secondResult = await pipeline.image(for: request)
        let second = try XCTUnwrap(secondResult)

        XCTAssertFalse(first === second)
        XCTAssertNotEqual(first.pixelSize, second.pixelSize)
    }

    func testAvatarImageTaskIdentityChangesWhenLocalFileIsReplacedAtSameURL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("avatar-image-task-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("current-user-avatar.jpg")
        let originalData = try XCTUnwrap(
            makeImage(size: CGSize(width: 480, height: 240)).jpegData(compressionQuality: 1)
        )
        try originalData.write(to: imageURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: imageURL.path
        )
        let originalRequest = try XCTUnwrap(
            WanderAvatarImageRequest(
                avatarURL: imageURL.absoluteString,
                targetPixelSize: 96
            )
        )

        let replacementData = try XCTUnwrap(
            makeImage(size: CGSize(width: 240, height: 480)).jpegData(compressionQuality: 0.75)
        )
        try replacementData.write(to: imageURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)],
            ofItemAtPath: imageURL.path
        )
        let replacementRequest = try XCTUnwrap(
            WanderAvatarImageRequest(
                avatarURL: imageURL.absoluteString,
                targetPixelSize: 96
            )
        )

        XCTAssertEqual(originalRequest.url, replacementRequest.url)
        XCTAssertNotEqual(originalRequest.localFileRevision, replacementRequest.localFileRevision)
        XCTAssertNotEqual(originalRequest, replacementRequest)
    }

    func testAvatarImagePipelineCoalescesConcurrentLoadsForTheSameRequest() async throws {
        let sourceData = try XCTUnwrap(
            makeImage(size: CGSize(width: 800, height: 400)).jpegData(compressionQuality: 1)
        )
        let loader = AvatarImageDataLoaderProbe(data: sourceData)
        let pipeline = WanderAvatarImagePipeline(
            countLimit: 4,
            dataLoader: { url in
                await loader.load(url)
            }
        )
        let request = try XCTUnwrap(
            WanderAvatarImageRequest(
                avatarURL: "https://example.com/avatar.jpg",
                targetPixelSize: 96
            )
        )

        let images = await withTaskGroup(
            of: WanderAvatarDecodedImage?.self,
            returning: [WanderAvatarDecodedImage?].self
        ) { group in
            for _ in 0..<12 {
                group.addTask {
                    await pipeline.image(for: request)
                }
            }
            var values: [WanderAvatarDecodedImage?] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        let loadCount = await loader.loadCount
        XCTAssertEqual(images.compactMap { $0 }.count, 12)
        XCTAssertEqual(loadCount, 1)
    }

    private func makeImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.76, green: 0.31, blue: 0.20, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.19, green: 0.45, blue: 0.38, alpha: 1).setFill()
            context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        }
    }
}

private actor AvatarImageDataLoaderProbe {
    private let data: Data
    private(set) var loadCount = 0

    init(data: Data) {
        self.data = data
    }

    func load(_ url: URL) async -> Data? {
        loadCount += 1
        try? await Task.sleep(for: .milliseconds(75))
        return data
    }
}
