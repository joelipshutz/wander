#!/usr/bin/env swift

import AppKit
import Foundation

enum LoadingMarkIcon {
    static let canvas = NSColor(
        srgbRed: 0xF3 / 255,
        green: 0xDF / 255,
        blue: 0xCA / 255,
        alpha: 1
    )
    static let terracotta = NSColor(
        srgbRed: 0xD4 / 255,
        green: 0x6F / 255,
        blue: 0x4D / 255,
        alpha: 1
    )
    static let ink = NSColor.black

    static let canvasSize = NSSize(width: 1024, height: 1024)
    struct Sizing {
        let symbolHeight: CGFloat
        let wordmarkPointSize: CGFloat
        let markSpacing: CGFloat
        let showsSymbol: Bool

        static let canonical = Sizing(
            symbolHeight: 340,
            wordmarkPointSize: 230,
            markSpacing: 24,
            showsSymbol: true
        )
    }

    static func render(to outputURL: URL, sizing: Sizing = .canonical) throws {
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let png: Data = try pixels.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress,
                  let cgContext = CGContext(
                    data: address,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  )
            else {
                throw RenderError.couldNotCreateContext
            }
            let context = NSGraphicsContext(cgContext: cgContext, flipped: false)

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            context.shouldAntialias = true

            canvas.setFill()
            NSRect(origin: .zero, size: canvasSize).fill()

            let wordmark = NSAttributedString(
                string: "rec.me",
                attributes: [
                    .font: editorialFont(size: sizing.wordmarkPointSize),
                    .foregroundColor: ink,
                    // Approved icon-only optical tightening; app UI typography stays untracked.
                    .kern: -2.5
                ]
            )
            let wordmarkSize = wordmark.size()
            let groupHeight = sizing.showsSymbol
                ? sizing.symbolHeight + sizing.markSpacing + wordmarkSize.height
                : wordmarkSize.height
            let groupBottom = (canvasSize.height - groupHeight) / 2
            let wordmarkRect = NSRect(
                x: (canvasSize.width - wordmarkSize.width) / 2,
                y: groupBottom,
                width: wordmarkSize.width,
                height: wordmarkSize.height
            )
            wordmark.draw(in: wordmarkRect)

            if sizing.showsSymbol {
                guard let baseSymbol = NSImage(
                    systemSymbolName: "mappin.and.ellipse",
                    accessibilityDescription: nil
                ) else {
                    NSGraphicsContext.restoreGraphicsState()
                    throw RenderError.missingSystemSymbol
                }
                let configuration = NSImage.SymbolConfiguration(
                    pointSize: sizing.symbolHeight,
                    weight: .bold
                )
                .applying(NSImage.SymbolConfiguration(paletteColors: [terracotta]))
                guard let symbol = baseSymbol.withSymbolConfiguration(configuration) else {
                    NSGraphicsContext.restoreGraphicsState()
                    throw RenderError.couldNotConfigureSystemSymbol
                }
                let aspectRatio = symbol.size.width / symbol.size.height
                let symbolSize = NSSize(
                    width: sizing.symbolHeight * aspectRatio,
                    height: sizing.symbolHeight
                )
                let symbolRect = NSRect(
                    x: (canvasSize.width - symbolSize.width) / 2,
                    y: wordmarkRect.maxY + sizing.markSpacing,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                symbol.draw(in: symbolRect)
            }

            cgContext.flush()
            NSGraphicsContext.restoreGraphicsState()

            guard let image = cgContext.makeImage(),
                  let encoded = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else {
                throw RenderError.couldNotEncodePNG
            }
            return encoded
        }
        try png.write(to: outputURL, options: .atomic)
    }

    private static func editorialFont(size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: .black)
        let descriptor = system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor
        return NSFont(descriptor: descriptor, size: size) ?? system
    }

    enum RenderError: Error {
        case couldNotCreateContext
        case missingSystemSymbol
        case couldNotConfigureSystemSymbol
        case couldNotEncodePNG
    }
}

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let defaultOutput = repoRoot
    .appendingPathComponent("Wander/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png")
let previewOutputPath = CommandLine.arguments.dropFirst().first
let outputURL = previewOutputPath.map {
    URL(fileURLWithPath: $0, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        .standardizedFileURL
} ?? defaultOutput

let environment = ProcessInfo.processInfo.environment
let canonicalSizing = LoadingMarkIcon.Sizing.canonical
func dimension(_ key: String, fallback: CGFloat) -> CGFloat {
    guard previewOutputPath != nil,
          let rawValue = environment[key],
          let value = Double(rawValue)
    else {
        return fallback
    }
    return CGFloat(value)
}
let sizing = LoadingMarkIcon.Sizing(
    symbolHeight: dimension("RECME_ICON_SYMBOL_HEIGHT", fallback: canonicalSizing.symbolHeight),
    wordmarkPointSize: dimension("RECME_ICON_WORDMARK_SIZE", fallback: canonicalSizing.wordmarkPointSize),
    markSpacing: dimension("RECME_ICON_SPACING", fallback: canonicalSizing.markSpacing),
    showsSymbol: previewOutputPath == nil || environment["RECME_ICON_WORDMARK_ONLY"] != "1"
)

try LoadingMarkIcon.render(to: outputURL, sizing: sizing)
print("Generated rec.me loading-mark app icon master at \(outputURL.path)")
