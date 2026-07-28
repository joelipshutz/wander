#!/usr/bin/env swift

import AppKit
import Darwin
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
                let symbolSize = NSSize(
                    width: sizing.symbolHeight,
                    height: sizing.symbolHeight
                )
                let symbolRect = NSRect(
                    x: (canvasSize.width - symbolSize.width) / 2,
                    y: wordmarkRect.maxY + sizing.markSpacing,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                drawOriginalLocator(in: symbolRect, context: cgContext)
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

    private static func drawOriginalLocator(in rect: NSRect, context: CGContext) {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + side * x, y: origin.y + side * y)
        }

        context.saveGState()
        context.setStrokeColor(terracotta.cgColor)
        context.setLineWidth(side * 0.065)
        context.setLineCap(.round)
        context.addArc(
            center: point(0.5, 0.53),
            radius: side * 0.43,
            startAngle: .pi * 0.66,
            endAngle: .pi * 1.23,
            clockwise: false
        )
        context.strokePath()
        context.addArc(
            center: point(0.5, 0.53),
            radius: side * 0.43,
            startAngle: -.pi * 0.27,
            endAngle: .pi * 0.14,
            clockwise: false
        )
        context.strokePath()

        let pin = CGMutablePath()
        pin.move(to: point(0.5, 0.08))
        pin.addCurve(
            to: point(0.22, 0.59),
            control1: point(0.47, 0.19),
            control2: point(0.22, 0.36)
        )
        pin.addCurve(
            to: point(0.5, 0.94),
            control1: point(0.22, 0.80),
            control2: point(0.34, 0.94)
        )
        pin.addCurve(
            to: point(0.78, 0.59),
            control1: point(0.66, 0.94),
            control2: point(0.78, 0.80)
        )
        pin.addCurve(
            to: point(0.5, 0.08),
            control1: point(0.78, 0.36),
            control2: point(0.53, 0.19)
        )
        pin.closeSubpath()
        context.addPath(pin)
        context.setFillColor(terracotta.cgColor)
        context.fillPath()

        context.setFillColor(canvas.cgColor)
        context.fillEllipse(in: CGRect(
            x: origin.x + side * 0.395,
            y: origin.y + side * 0.545,
            width: side * 0.21,
            height: side * 0.21
        ))
        context.restoreGState()
    }

    enum RenderError: Error {
        case couldNotCreateContext
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
let usesPreviewOverrides = environment["RECME_ICON_PREVIEW"] == "1"
let canonicalURL = defaultOutput.standardizedFileURL.resolvingSymlinksInPath()
let resolvedOutputURL = outputURL.standardizedFileURL.resolvingSymlinksInPath()

if usesPreviewOverrides && resolvedOutputURL == canonicalURL {
    fail("RECME_ICON_PREVIEW=1 requires an explicit non-canonical output path")
}

func dimension(_ key: String, fallback: CGFloat, range: ClosedRange<Double>) throws -> CGFloat {
    guard usesPreviewOverrides, let rawValue = environment[key] else { return fallback }
    guard let value = Double(rawValue), value.isFinite, range.contains(value) else {
        fail("Invalid preview dimension \(key)=\(rawValue)")
    }
    return CGFloat(value)
}
let sizing = try LoadingMarkIcon.Sizing(
    symbolHeight: dimension(
        "RECME_ICON_SYMBOL_HEIGHT",
        fallback: canonicalSizing.symbolHeight,
        range: 1 ... 1024
    ),
    wordmarkPointSize: dimension(
        "RECME_ICON_WORDMARK_SIZE",
        fallback: canonicalSizing.wordmarkPointSize,
        range: 1 ... 1024
    ),
    markSpacing: dimension(
        "RECME_ICON_SPACING",
        fallback: canonicalSizing.markSpacing,
        range: 0 ... 1024
    ),
    showsSymbol: !usesPreviewOverrides || environment["RECME_ICON_WORDMARK_ONLY"] != "1"
)

try LoadingMarkIcon.render(to: outputURL, sizing: sizing)
print("Generated rec.me loading-mark app icon master at \(outputURL.path)")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    Darwin.exit(2)
}
