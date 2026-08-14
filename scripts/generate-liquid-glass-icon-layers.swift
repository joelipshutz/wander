#!/usr/bin/env swift

import AppKit
import Foundation

private struct Concept {
    let slug: String
    let font: NSFont
    let wordmarkY: CGFloat
    let globeRect: NSRect
    let globeColor: NSColor
    let accentColors: [NSColor]
    let pinColor: NSColor
    let pinHeadY: CGFloat
    let pinRadius: CGFloat
}

private enum Palette {
    static let background = NSColor(srgbRed: 0.95, green: 0.87, blue: 0.79, alpha: 1)
    static let ink = NSColor(srgbRed: 0.08, green: 0.055, blue: 0.07, alpha: 1)
    static let coral = NSColor(srgbRed: 0.96, green: 0.31, blue: 0.16, alpha: 1)
    static let terracotta = NSColor(srgbRed: 0.83, green: 0.31, blue: 0.18, alpha: 1)
    static let cyan = NSColor(srgbRed: 0.08, green: 0.78, blue: 0.94, alpha: 1)
    static let blue = NSColor(srgbRed: 0.08, green: 0.32, blue: 0.88, alpha: 1)
    static let violet = NSColor(srgbRed: 0.45, green: 0.18, blue: 0.86, alpha: 1)
    static let magenta = NSColor(srgbRed: 0.93, green: 0.16, blue: 0.59, alpha: 1)
    static let amber = NSColor(srgbRed: 1.0, green: 0.60, blue: 0.16, alpha: 1)
    static let lime = NSColor(srgbRed: 0.48, green: 0.88, blue: 0.18, alpha: 1)
    static let teal = NSColor(srgbRed: 0.05, green: 0.62, blue: 0.55, alpha: 1)
}

private let canvasSize = NSSize(width: 1024, height: 1024)
private let outputRoot = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/brand/explorations/rec-214-pin-map/liquid-glass/icon-composer")

private func font(design: NSFontDescriptor.SystemDesign, size: CGFloat, weight: NSFont.Weight, italic: Bool = false, condensed: Bool = false) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    var descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
    var traits = descriptor.symbolicTraits
    if italic { traits.insert(.italic) }
    if condensed { traits.insert(.condensed) }
    descriptor = descriptor.withSymbolicTraits(traits)
    return NSFont(descriptor: descriptor, size: size) ?? base
}

private let concepts: [Concept] = [
    Concept(
        slug: "direction-d-aurora-editorial",
        font: font(design: .serif, size: 214, weight: .black),
        wordmarkY: 397,
        globeRect: NSRect(x: -72, y: 80, width: 1168, height: 430),
        globeColor: Palette.cyan,
        accentColors: [Palette.blue, Palette.violet, Palette.magenta, Palette.amber],
        pinColor: Palette.coral,
        pinHeadY: 740,
        pinRadius: 105
    ),
    Concept(
        slug: "direction-e-rounded-gel",
        font: font(design: .rounded, size: 196, weight: .heavy),
        wordmarkY: 400,
        globeRect: NSRect(x: 65, y: 125, width: 894, height: 350),
        globeColor: Palette.cyan,
        accentColors: [Palette.magenta, Palette.lime, Palette.amber, Palette.violet],
        pinColor: Palette.coral,
        pinHeadY: 740,
        pinRadius: 112
    ),
    Concept(
        slug: "direction-f-soft-neo-serif",
        font: font(design: .serif, size: 198, weight: .bold),
        wordmarkY: 404,
        globeRect: NSRect(x: 105, y: 150, width: 814, height: 318),
        globeColor: Palette.blue,
        accentColors: [Palette.teal, Palette.violet, Palette.magenta, Palette.amber],
        pinColor: Palette.terracotta,
        pinHeadY: 754,
        pinRadius: 102
    ),
    Concept(
        slug: "direction-g-fluid-italic",
        font: font(design: .serif, size: 203, weight: .bold, italic: true),
        wordmarkY: 405,
        globeRect: NSRect(x: -45, y: 98, width: 1114, height: 365),
        globeColor: Palette.cyan,
        accentColors: [Palette.blue, Palette.violet, Palette.magenta, Palette.amber],
        pinColor: Palette.coral,
        pinHeadY: 748,
        pinRadius: 100
    ),
    Concept(
        slug: "direction-h-globe-forward",
        font: font(design: .default, size: 188, weight: .bold, condensed: true),
        wordmarkY: 418,
        globeRect: NSRect(x: 78, y: 102, width: 868, height: 560),
        globeColor: Palette.blue,
        accentColors: [Palette.cyan, Palette.teal, Palette.lime, Palette.magenta, Palette.amber],
        pinColor: Palette.coral,
        pinHeadY: 790,
        pinRadius: 92
    )
]

private func render(to url: URL, drawing: (CGContext) -> Void) throws {
    let width = Int(canvasSize.width)
    let height = Int(canvasSize.height)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let data = try pixels.withUnsafeMutableBytes { bytes -> Data in
        guard let address = bytes.baseAddress,
              let context = CGContext(
                data: address,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw CocoaError(.fileWriteUnknown) }

        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        context.clear(NSRect(origin: .zero, size: canvasSize))
        context.setShouldAntialias(true)
        drawing(context)
        context.flush()
        NSGraphicsContext.restoreGraphicsState()

        guard let image = context.makeImage(),
              let encoded = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        return encoded
    }
    try data.write(to: url, options: .atomic)
}

private func wordmarkMetrics(for concept: Concept) -> (attributed: NSAttributedString, origin: NSPoint, periodX: CGFloat, periodY: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: concept.font,
        .foregroundColor: Palette.ink,
        .kern: -2.5
    ]
    let attributed = NSAttributedString(string: "rec.me", attributes: attributes)
    let size = attributed.size()
    let origin = NSPoint(x: (canvasSize.width - size.width) / 2, y: concept.wordmarkY)
    let prefix = NSAttributedString(string: "rec", attributes: attributes).size().width
    let periodWidth = NSAttributedString(string: ".", attributes: attributes).size().width
    let periodX = origin.x + prefix + periodWidth * 0.5
    let periodY = origin.y + concept.font.xHeight * 0.14
    return (attributed, origin, periodX, periodY)
}

private func drawGlobeBase(_ concept: Concept) {
    concept.globeColor.setFill()
    let path = NSBezierPath(ovalIn: concept.globeRect)
    path.fill()
}

private func blob(in rect: NSRect, insetX: CGFloat, insetY: CGFloat, color: NSColor, phase: CGFloat) {
    let r = rect.insetBy(dx: insetX, dy: insetY)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: r.minX + r.width * 0.05, y: r.midY + phase))
    path.curve(to: NSPoint(x: r.minX + r.width * 0.42, y: r.maxY - phase), controlPoint1: NSPoint(x: r.minX + r.width * 0.18, y: r.maxY), controlPoint2: NSPoint(x: r.minX + r.width * 0.30, y: r.maxY))
    path.curve(to: NSPoint(x: r.maxX - r.width * 0.08, y: r.midY - phase), controlPoint1: NSPoint(x: r.minX + r.width * 0.56, y: r.maxY - phase * 0.5), controlPoint2: NSPoint(x: r.maxX, y: r.maxY - phase))
    path.curve(to: NSPoint(x: r.minX + r.width * 0.58, y: r.minY + phase), controlPoint1: NSPoint(x: r.maxX, y: r.minY + phase), controlPoint2: NSPoint(x: r.minX + r.width * 0.72, y: r.minY))
    path.curve(to: NSPoint(x: r.minX + r.width * 0.05, y: r.midY + phase), controlPoint1: NSPoint(x: r.minX + r.width * 0.38, y: r.minY), controlPoint2: NSPoint(x: r.minX, y: r.minY + phase))
    path.close()
    color.setFill()
    path.fill()
}

private func drawGlobeDetails(_ concept: Concept) {
    let colors = concept.accentColors
    blob(in: concept.globeRect, insetX: concept.globeRect.width * 0.06, insetY: concept.globeRect.height * 0.19, color: colors[0], phase: 14)
    blob(in: NSRect(x: concept.globeRect.minX + concept.globeRect.width * 0.42, y: concept.globeRect.minY + 12, width: concept.globeRect.width * 0.52, height: concept.globeRect.height * 0.76), insetX: 8, insetY: 18, color: colors[1], phase: 9)
    blob(in: NSRect(x: concept.globeRect.minX + 26, y: concept.globeRect.minY + 18, width: concept.globeRect.width * 0.42, height: concept.globeRect.height * 0.60), insetX: 8, insetY: 14, color: colors[2], phase: 6)
    if colors.count > 3 {
        blob(in: NSRect(x: concept.globeRect.midX - 85, y: concept.globeRect.midY - 35, width: 255, height: 155), insetX: 12, insetY: 14, color: colors[3], phase: 4)
    }
    if colors.count > 4 {
        blob(in: NSRect(x: concept.globeRect.maxX - 300, y: concept.globeRect.minY + 70, width: 210, height: 155), insetX: 10, insetY: 10, color: colors[4], phase: 5)
    }
}

private func drawPin(_ concept: Concept, periodX: CGFloat, periodY: CGFloat) {
    let center = NSPoint(x: periodX, y: concept.pinHeadY)
    let radius = concept.pinRadius
    concept.pinColor.setFill()
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: center.x - radius * 0.58, y: center.y - radius * 0.42))
    shaft.line(to: NSPoint(x: center.x + radius * 0.58, y: center.y - radius * 0.42))
    shaft.line(to: NSPoint(x: periodX, y: periodY + 18))
    shaft.close()
    shaft.fill()

    let head = NSBezierPath()
    head.appendOval(in: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    head.appendOval(in: NSRect(x: center.x - radius * 0.36, y: center.y - radius * 0.36, width: radius * 0.72, height: radius * 0.72))
    head.windingRule = .evenOdd
    head.fill()
}

try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

for concept in concepts {
    let directory = outputRoot.appendingPathComponent(concept.slug)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let metrics = wordmarkMetrics(for: concept)

    try render(to: directory.appendingPathComponent("00-flat-preview.png")) { _ in
        Palette.background.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()
        drawGlobeBase(concept)
        drawGlobeDetails(concept)
        metrics.attributed.draw(at: metrics.origin)
        drawPin(concept, periodX: metrics.periodX, periodY: metrics.periodY)
    }

    try render(to: directory.appendingPathComponent("01-globe-base.png")) { _ in
        drawGlobeBase(concept)
    }
    try render(to: directory.appendingPathComponent("02-globe-colors.png")) { _ in
        drawGlobeDetails(concept)
    }
    try render(to: directory.appendingPathComponent("03-wordmark.png")) { _ in
        metrics.attributed.draw(at: metrics.origin)
    }
    try render(to: directory.appendingPathComponent("04-pin.png")) { _ in
        drawPin(concept, periodX: metrics.periodX, periodY: metrics.periodY)
    }
}

print("Generated liquid-glass Icon Composer layers at \(outputRoot.path)")
