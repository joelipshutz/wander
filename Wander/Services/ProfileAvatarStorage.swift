import Foundation
import UIKit

enum WanderImageProcessingError: LocalizedError, Equatable {
    case invalidImageData
    case invalidImageSize
    case jpegEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            "The selected file is not a readable image."
        case .invalidImageSize:
            "The selected image has an invalid size."
        case .jpegEncodingFailed:
            "The selected image could not be prepared."
        }
    }
}

enum WanderImageProcessor {
    static func squareJPEGData(
        from data: Data,
        pixelSize: CGFloat = 512,
        compressionQuality: CGFloat = 0.85
    ) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw WanderImageProcessingError.invalidImageData
        }

        return try squareJPEGData(
            from: image,
            pixelSize: pixelSize,
            compressionQuality: compressionQuality
        )
    }

    static func squareJPEGData(
        from image: UIImage,
        pixelSize: CGFloat = 512,
        compressionQuality: CGFloat = 0.85
    ) throws -> Data {
        guard image.size.width > 0,
              image.size.height > 0,
              pixelSize > 0
        else {
            throw WanderImageProcessingError.invalidImageSize
        }

        let outputSize = CGSize(width: pixelSize, height: pixelSize)
        let shortestSide = min(image.size.width, image.size.height)
        let scale = pixelSize / shortestSide
        let scaledSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let drawRect = CGRect(
            x: (pixelSize - scaledSize.width) / 2,
            y: (pixelSize - scaledSize.height) / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let jpegData = renderer.jpegData(withCompressionQuality: compressionQuality) { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            image.draw(in: drawRect)
        }

        guard !jpegData.isEmpty else {
            throw WanderImageProcessingError.jpegEncodingFailed
        }

        return jpegData
    }
}

struct ProfileAvatarStorage {
    private static let fileName = "current-user-avatar.jpg"

    let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    static var live: ProfileAvatarStorage {
        let applicationSupportURL = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let baseURL = applicationSupportURL ?? FileManager.default.temporaryDirectory
        return ProfileAvatarStorage(
            directoryURL: baseURL
                .appendingPathComponent("Wander", isDirectory: true)
                .appendingPathComponent("ProfileAvatars", isDirectory: true)
        )
    }

    var avatarFileURL: URL {
        directoryURL.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    @discardableResult
    func writeAvatarData(_ data: Data) throws -> URL {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try data.write(to: avatarFileURL, options: [.atomic])
        return avatarFileURL
    }

    func deleteAvatar() throws {
        guard fileManager.fileExists(atPath: avatarFileURL.path) else { return }
        try fileManager.removeItem(at: avatarFileURL)
    }
}
