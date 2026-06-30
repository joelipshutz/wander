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
