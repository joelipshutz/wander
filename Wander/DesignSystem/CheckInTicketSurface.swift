import SwiftUI

enum CheckInTicketNotchEdges {
    case trailing
    case both
}

private struct CheckInTicketSurfaceModifier: ViewModifier {
    let accent: Color
    let surface: Color
    let surroundingSurface: Color
    let notchEdges: CheckInTicketNotchEdges
    let castsShadow: Bool

    func body(content: Content) -> some View {
        content
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                    .stroke(accent.opacity(0.72), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if notchEdges == .both {
                    notch
                        .offset(x: -8)
                }
            }
            .overlay(alignment: .trailing) {
                notch
                    .offset(x: 8)
            }
            .shadow(
                color: castsShadow ? WanderTheme.textInk.color.opacity(0.14) : .clear,
                radius: castsShadow ? 14 : 0,
                x: 0,
                y: castsShadow ? 7 : 0
            )
    }

    private var notch: some View {
        Circle()
            .fill(surroundingSurface)
            .frame(width: 16, height: 16)
            .overlay {
                Circle()
                    .stroke(accent.opacity(0.36), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

extension View {
    func checkInTicketSurface(
        accent: Color,
        surface: Color = WanderTheme.surfaceBone.color,
        surroundingSurface: Color = WanderTheme.canvasWarm.color,
        notchEdges: CheckInTicketNotchEdges = .trailing,
        castsShadow: Bool = true
    ) -> some View {
        modifier(
            CheckInTicketSurfaceModifier(
                accent: accent,
                surface: surface,
                surroundingSurface: surroundingSurface,
                notchEdges: notchEdges,
                castsShadow: castsShadow
            )
        )
    }
}
