#!/usr/bin/env swift

import AppKit
import Darwin
import Foundation

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let sourceURL = repoRoot.appendingPathComponent(
    "Wander/Resources/AppIcon.icon/Assets/recme-liquid-glass-map-ocean-reframe.png"
)
let defaultOutputURL = repoRoot.appendingPathComponent(
    "Wander/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png"
)
let outputURL = CommandLine.arguments.dropFirst().first.map {
    URL(
        fileURLWithPath: $0,
        relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ).standardizedFileURL
} ?? defaultOutputURL

let sourceData: Data
do {
    sourceData = try Data(contentsOf: sourceURL)
} catch {
    fail("Could not read canonical app icon source at \(sourceURL.path): \(error)")
}

guard let bitmap = NSBitmapImageRep(data: sourceData),
      let image = bitmap.cgImage
else {
    fail("Canonical app icon source is not a readable PNG")
}

guard image.width == 1024, image.height == 1024 else {
    fail("Canonical app icon source must be exactly 1024 x 1024 pixels")
}

switch image.alphaInfo {
case .none, .noneSkipFirst, .noneSkipLast:
    break
case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
    fail("Canonical app icon source must be opaque")
@unknown default:
    fail("Canonical app icon source has an unknown alpha configuration")
}

do {
    try sourceData.write(to: outputURL, options: .atomic)
} catch {
    fail("Could not write app icon master to \(outputURL.path): \(error)")
}

print("Generated rec.me liquid-glass app icon master at \(outputURL.path)")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    Darwin.exit(2)
}
