import SwiftUI

enum CheckInTicketNotchEdges {
    case trailing
    case both
}

private struct CheckInTicketSurfaceModifier: ViewModifier {
    let accent: Color
    let surface: Color
    let notchEdges: CheckInTicketNotchEdges
    let castsShadow: Bool
    let borderWidth: CGFloat
    @Environment(\.placeProfileVisualStyle) private var placeProfileVisualStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        if placeProfileVisualStyle == .astir {
            content
                .astirGlassSurface(cornerRadius: 18, castsShadow: castsShadow)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.opacity(0.42), lineWidth: borderWidth)
                }
        } else {
            let ticketShape = CheckInTicketShape(notchEdges: notchEdges)

            content
                .clipShape(ticketShape)
                .background {
                    ticketShape
                        .fill(surface)
                        .shadow(
                            color: castsShadow ? WanderTheme.textInk.color.opacity(0.14) : .clear,
                            radius: castsShadow ? 14 : 0,
                            x: 0,
                            y: castsShadow ? 7 : 0
                        )
                }
                .overlay {
                    ticketShape
                        .strokeBorder(accent.opacity(0.72), lineWidth: borderWidth)
                }
            }
    }
}

struct CheckInTicketShape: InsettableShape {
    let notchEdges: CheckInTicketNotchEdges
    var insetAmount: CGFloat = 0

    func path(in bounds: CGRect) -> Path {
        let rect = bounds.insetBy(dx: insetAmount, dy: insetAmount)
        guard rect.width > 0, rect.height > 0 else { return Path() }

        let cornerRadius = min(
            WanderTheme.radiusMedium,
            min(rect.width, rect.height) / 2
        )
        let notchRadius = min(9, rect.height / 4)
        let bezierControl: CGFloat = 0.552_284_75
        let centerY = rect.midY

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: centerY - notchRadius))
        addTrailingNotch(
            to: &path,
            rect: rect,
            centerY: centerY,
            radius: notchRadius,
            control: bezierControl
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )

        if notchEdges == .both {
            path.addLine(to: CGPoint(x: rect.minX, y: centerY + notchRadius))
            addLeadingNotch(
                to: &path,
                rect: rect,
                centerY: centerY,
                radius: notchRadius,
                control: bezierControl
            )
        }

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> CheckInTicketShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    private func addTrailingNotch(
        to path: inout Path,
        rect: CGRect,
        centerY: CGFloat,
        radius: CGFloat,
        control: CGFloat
    ) {
        path.addCurve(
            to: CGPoint(x: rect.maxX - radius, y: centerY),
            control1: CGPoint(x: rect.maxX - radius * control, y: centerY - radius),
            control2: CGPoint(x: rect.maxX - radius, y: centerY - radius * control)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: centerY + radius),
            control1: CGPoint(x: rect.maxX - radius, y: centerY + radius * control),
            control2: CGPoint(x: rect.maxX - radius * control, y: centerY + radius)
        )
    }

    private func addLeadingNotch(
        to path: inout Path,
        rect: CGRect,
        centerY: CGFloat,
        radius: CGFloat,
        control: CGFloat
    ) {
        path.addCurve(
            to: CGPoint(x: rect.minX + radius, y: centerY),
            control1: CGPoint(x: rect.minX + radius * control, y: centerY + radius),
            control2: CGPoint(x: rect.minX + radius, y: centerY + radius * control)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: centerY - radius),
            control1: CGPoint(x: rect.minX + radius, y: centerY - radius * control),
            control2: CGPoint(x: rect.minX + radius * control, y: centerY - radius)
        )
    }
}

extension View {
    func checkInTicketSurface(
        accent: Color,
        surface: Color = WanderTheme.surfaceBone.color,
        surroundingSurface _: Color = WanderTheme.canvasWarm.color,
        notchEdges: CheckInTicketNotchEdges = .trailing,
        castsShadow: Bool = true,
        borderWidth: CGFloat = 1
    ) -> some View {
        modifier(
            CheckInTicketSurfaceModifier(
                accent: accent,
                surface: surface,
                notchEdges: notchEdges,
                castsShadow: castsShadow,
                borderWidth: borderWidth
            )
        )
    }
}
