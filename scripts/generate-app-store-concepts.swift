#!/usr/bin/env swift

import AppKit
import Darwin
import Foundation

private enum StoreConcepts {
    static let screenshotSize = NSSize(width: 1320, height: 2868)
    static let phoneRect = NSRect(x: 125, y: -24, width: 1070, height: 2312)
    static let phoneInset: CGFloat = 14
    static let headlineRect = NSRect(x: 92, y: 2348, width: 1136, height: 426)

    static let warm = color(0xF3DFCA)
    static let bone = color(0xFFF7EA)
    static let sun = color(0xF4E8C9)
    static let sky = color(0xDBEAF1)
    static let terracottaTint = color(0xF6E0D2)
    static let terracotta = color(0xD46F4D)
    static let ink = color(0x2C2118)
    static let muted = color(0x7B6555)

    struct Panel {
        let filename: String
        let sourceFilename: String
        let headline: String
        let background: NSColor
    }

    static let panels = [
        Panel(
            filename: "01-your-people-one-map.png",
            sourceFilename: "recme-store-01-map-friends.png",
            headline: "Your people.\nTheir places. One map.",
            background: warm
        ),
        Panel(
            filename: "02-friends-actually-went.png",
            sourceFilename: "recme-store-02-feed-places.png",
            headline: "See where your friends\nactually went.",
            background: sky
        ),
        Panel(
            filename: "03-fits-right-now.png",
            sourceFilename: "recme-store-03-trusted-search.png",
            headline: "Find a place that\nfits right now.",
            background: sun
        ),
        Panel(
            filename: "04-worth-returning-to.png",
            sourceFilename: "recme-store-04-place-detail.png",
            headline: "Remember every place\nworth returning to.",
            background: bone
        ),
        Panel(
            filename: "05-save-before-you-lose-it.png",
            sourceFilename: "recme-store-05-add.png",
            headline: "Save it before\nyou lose it.",
            background: terracottaTint
        ),
        Panel(
            filename: "06-make-plans-together.png",
            sourceFilename: "recme-store-06-lists.png",
            headline: "Make plans\ntogether.",
            background: warm
        ),
    ]

    static func renderPanel(_ panel: Panel, inputDirectory: URL, outputDirectory: URL) throws -> URL {
        let sourceURL = inputDirectory.appendingPathComponent(panel.sourceFilename)
        guard let sourceImage = NSImage(contentsOf: sourceURL) else {
            throw RenderError.missingSource(sourceURL.path)
        }
        let outputURL = outputDirectory.appendingPathComponent(panel.filename)
        try render(size: screenshotSize, to: outputURL) {
            panel.background.setFill()
            NSRect(origin: .zero, size: screenshotSize).fill()

            drawWordmark()
            drawHeadline(panel.headline)
            drawPhone(sourceImage)
        }
        return outputURL
    }

    static func renderBoard(panelURLs: [URL], outputDirectory: URL) throws -> URL {
        let boardSize = NSSize(width: 3320, height: 4300)
        let outputURL = outputDirectory.appendingPathComponent("recme-app-store-storyboard-v1.png")
        let panelWidth: CGFloat = 840
        let panelHeight = panelWidth * screenshotSize.height / screenshotSize.width
        let xPositions: [CGFloat] = [260, 1240, 2220]
        let yPositions: [CGFloat] = [2180, 170]

        let images = try panelURLs.map { url -> NSImage in
            guard let image = NSImage(contentsOf: url) else {
                throw RenderError.missingSource(url.path)
            }
            return image
        }

        try render(size: boardSize, to: outputURL) {
            color(0x19130F).setFill()
            NSRect(origin: .zero, size: boardSize).fill()

            let eyebrow = NSAttributedString(
                string: "REC.ME / APP STORE STORYBOARD",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 34, weight: .bold),
                    .foregroundColor: terracotta,
                    .kern: 2.4,
                ]
            )
            eyebrow.draw(at: NSPoint(x: 150, y: 4210))

            let title = NSAttributedString(
                string: "Warm editorial utility",
                attributes: [
                    .font: editorialFont(size: 76, weight: .black),
                    .foregroundColor: bone,
                ]
            )
            title.draw(at: NSPoint(x: 150, y: 4100))

            let subtitle = NSAttributedString(
                string: "RECOMMENDED  •  REAL PRODUCT UI  •  BENEFIT-FIRST COPY  •  BRAND-TOKEN COLOR RHYTHM",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
                    .foregroundColor: color(0xC9AC8F),
                    .kern: 1.0,
                ]
            )
            subtitle.draw(at: NSPoint(x: 154, y: 4038))

            for (index, image) in images.enumerated() {
                let column = index % 3
                let row = index / 3
                let shadowRect = NSRect(
                    x: xPositions[column] - 12,
                    y: yPositions[row] - 12,
                    width: panelWidth + 24,
                    height: panelHeight + 24
                )
                color(0x000000, alpha: 0.34).setFill()
                NSBezierPath(roundedRect: shadowRect, xRadius: 38, yRadius: 38).fill()

                let imageRect = NSRect(
                    x: xPositions[column],
                    y: yPositions[row],
                    width: panelWidth,
                    height: panelHeight
                )
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: imageRect, xRadius: 28, yRadius: 28).addClip()
                image.draw(in: imageRect, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        return outputURL
    }

    private static func drawWordmark() {
        let wordmark = NSAttributedString(
            string: "rec.me",
            attributes: [
                .font: editorialFont(size: 44, weight: .black),
                .foregroundColor: terracotta,
            ]
        )
        wordmark.draw(at: NSPoint(x: 96, y: 2784))
    }

    private static func drawHeadline(_ value: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = -6
        let headline = NSAttributedString(
            string: value,
            attributes: [
                .font: editorialFont(size: 100, weight: .black),
                .foregroundColor: ink,
                .paragraphStyle: paragraph,
            ]
        )
        headline.draw(
            with: headlineRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }

    private static func drawPhone(_ image: NSImage) {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: phoneRect, xRadius: 112, yRadius: 112).fill()

        let displayRect = phoneRect.insetBy(dx: phoneInset, dy: phoneInset)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: displayRect, xRadius: 98, yRadius: 98).addClip()
        image.draw(
            in: displayRect,
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func render(size: NSSize, to outputURL: URL, drawing: () throws -> Void) throws {
        let width = Int(size.width)
        let height = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let data: Data = try pixels.withUnsafeMutableBytes { bytes in
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
            try drawing()
            cgContext.flush()
            NSGraphicsContext.restoreGraphicsState()

            guard let image = cgContext.makeImage(),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else {
                throw RenderError.couldNotEncodePNG
            }
            return png
        }
        try data.write(to: outputURL, options: .atomic)
    }

    private static func editorialFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        let descriptor = system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor
        return NSFont(descriptor: descriptor, size: size) ?? system
    }

    private static func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    enum RenderError: Error, CustomStringConvertible {
        case couldNotCreateContext
        case couldNotEncodePNG
        case missingSource(String)

        var description: String {
            switch self {
            case .couldNotCreateContext:
                "Could not create the bitmap context"
            case .couldNotEncodePNG:
                "Could not encode the PNG"
            case .missingSource(let path):
                "Missing screenshot source at \(path)"
            }
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    Darwin.exit(2)
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 2 else {
    fail("Usage: scripts/generate-app-store-concepts.swift <input-directory> <output-directory>")
}

let inputDirectory = URL(fileURLWithPath: String(arguments[arguments.startIndex])).standardizedFileURL
let outputDirectory = URL(fileURLWithPath: String(arguments[arguments.index(after: arguments.startIndex)])).standardizedFileURL
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

do {
    let panelURLs = try StoreConcepts.panels.map {
        try StoreConcepts.renderPanel($0, inputDirectory: inputDirectory, outputDirectory: outputDirectory)
    }
    let boardURL = try StoreConcepts.renderBoard(panelURLs: panelURLs, outputDirectory: outputDirectory)
    print("Generated \(panelURLs.count) App Store concepts")
    print(boardURL.path)
} catch {
    fail(String(describing: error))
}
