import UIKit

/// The complete stage-light mark, rasterized once at the display's native scale.
/// Its 23-point ink height and one-point insets match the paper Lists tab icon.
enum EventsTabSymbol {
    @MainActor static let tabImage: UIImage = {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 35.5, height: 25)).image { renderer in
            let context = renderer.cgContext
            context.setFillColor(UIColor.black.cgColor)
            context.setStrokeColor(UIColor.black.cgColor)
            context.translateBy(x: 1.02, y: 1)
            context.scaleBy(x: 23 / 374, y: 23 / 374)
            draw(in: context)
        }
        return image.withRenderingMode(.alwaysTemplate)
    }()

    private static func draw(in context: CGContext) {
        // Both lamps and all four beams are part of the icon, including the cross.
        context.setLineWidth(12)
        context.setLineCap(.butt)
        for (start, end) in [
            (CGPoint(x: 37, y: 81), CGPoint(x: 124, y: 316)),
            (CGPoint(x: 80, y: 54), CGPoint(x: 334, y: 258)),
            (CGPoint(x: 507, y: 81), CGPoint(x: 420, y: 316)),
            (CGPoint(x: 464, y: 54), CGPoint(x: 210, y: 258))
        ] {
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }

        let lamp = CGMutablePath()
        lamp.move(to: CGPoint(x: 5, y: 22))
        lamp.addCurve(to: CGPoint(x: 41, y: 0), control1: CGPoint(x: 14, y: 7), control2: CGPoint(x: 27, y: 0))
        lamp.addCurve(to: CGPoint(x: 64, y: 12), control1: CGPoint(x: 52, y: 0), control2: CGPoint(x: 59, y: 4))
        lamp.addLine(to: CGPoint(x: 85, y: 48))
        lamp.addCurve(to: CGPoint(x: 75, y: 79), control1: CGPoint(x: 94, y: 60), control2: CGPoint(x: 86, y: 72))
        lamp.addCurve(to: CGPoint(x: 35, y: 88), control1: CGPoint(x: 61, y: 89), control2: CGPoint(x: 44, y: 93))
        lamp.addLine(to: CGPoint(x: 3, y: 41))
        lamp.addCurve(to: CGPoint(x: 5, y: 22), control1: CGPoint(x: -2, y: 34), control2: CGPoint(x: 1, y: 28))
        lamp.closeSubpath()

        let aperture = CGMutablePath()
        aperture.move(to: CGPoint(x: 42, y: 72))
        aperture.addCurve(to: CGPoint(x: 74, y: 57), control1: CGPoint(x: 44, y: 59), control2: CGPoint(x: 63, y: 51))
        aperture.addCurve(to: CGPoint(x: 42, y: 72), control1: CGPoint(x: 70, y: 71), control2: CGPoint(x: 50, y: 82))
        aperture.closeSubpath()

        for mirrored in [false, true] {
            context.saveGState()
            if mirrored {
                context.translateBy(x: 544, y: 0)
                context.scaleBy(x: -1, y: 1)
            }
            context.addPath(lamp)
            context.fillPath()
            context.setBlendMode(.clear)
            context.addPath(aperture)
            context.fillPath()
            context.restoreGState()
        }

        let sidePerson = CGMutablePath()
        sidePerson.move(to: CGPoint(x: 126, y: 354))
        sidePerson.addCurve(to: CGPoint(x: 164, y: 304), control1: CGPoint(x: 126, y: 328), control2: CGPoint(x: 139, y: 312))
        sidePerson.addCurve(to: CGPoint(x: 180, y: 252), control1: CGPoint(x: 140, y: 289), control2: CGPoint(x: 149, y: 252))
        sidePerson.addCurve(to: CGPoint(x: 196, y: 304), control1: CGPoint(x: 212, y: 252), control2: CGPoint(x: 220, y: 289))
        sidePerson.addCurve(to: CGPoint(x: 234, y: 354), control1: CGPoint(x: 221, y: 312), control2: CGPoint(x: 234, y: 328))
        sidePerson.closeSubpath()
        context.addPath(sidePerson)
        context.fillPath()
        var mirror = CGAffineTransform(translationX: 544, y: 0).scaledBy(x: -1, y: 1)
        if let rightPerson = sidePerson.copy(using: &mirror) {
            context.addPath(rightPerson)
            context.fillPath()
        }

        let frontPerson = CGMutablePath()
        frontPerson.move(to: CGPoint(x: 203, y: 374))
        frontPerson.addCurve(to: CGPoint(x: 251, y: 313), control1: CGPoint(x: 203, y: 341), control2: CGPoint(x: 219, y: 321))
        frontPerson.addCurve(to: CGPoint(x: 273, y: 246), control1: CGPoint(x: 222, y: 294), control2: CGPoint(x: 227, y: 246))
        frontPerson.addCurve(to: CGPoint(x: 295, y: 313), control1: CGPoint(x: 319, y: 246), control2: CGPoint(x: 324, y: 294))
        frontPerson.addCurve(to: CGPoint(x: 342, y: 374), control1: CGPoint(x: 327, y: 321), control2: CGPoint(x: 342, y: 341))
        frontPerson.closeSubpath()
        // Transparent separation keeps all three silhouettes legible in either tint.
        context.setBlendMode(.clear)
        context.setLineWidth(10)
        context.setLineJoin(.round)
        context.addPath(frontPerson)
        context.drawPath(using: .fillStroke)
        context.setBlendMode(.normal)
        context.addPath(frontPerson)
        context.fillPath()
    }
}
