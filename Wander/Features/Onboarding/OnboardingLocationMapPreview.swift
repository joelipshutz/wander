import MapKit
import SwiftUI

enum OnboardingLocationContent {
    static let eyebrow = "AROUND YOU"
    static let title = "Find the good stuff nearby"
    static let message = "See places your friends recommend and save spots around you without searching for an address."
    static let privacyMessage = "Your location is never shown to friends."
    static let selectedPlaceName = "Circuit Coffee"
}

struct OnboardingLocationMapPreview: View {
    private static let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.085, longitude: -118.276),
        span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
    )

    private static let pins = [
        PreviewPin(
            id: "larchmont-noodles",
            name: "Larchmont Noodles",
            emoji: "🍜",
            coordinate: CLLocationCoordinate2D(latitude: 34.073, longitude: -118.323),
            ownership: .social
        ),
        PreviewPin(
            id: "griffith-trail",
            name: "Griffith Observatory Trail",
            emoji: "🥾",
            coordinate: CLLocationCoordinate2D(latitude: 34.119, longitude: -118.300),
            ownership: .social
        ),
        PreviewPin(
            id: "woodcat-coffee",
            name: "Woodcat Coffee",
            emoji: "☕️",
            coordinate: CLLocationCoordinate2D(latitude: 34.077, longitude: -118.260),
            ownership: .currentUser
        ),
        PreviewPin(
            id: "bar-nido",
            name: "Bar Nido",
            emoji: "🍝",
            coordinate: CLLocationCoordinate2D(latitude: 34.079, longitude: -118.260),
            ownership: .social
        ),
        PreviewPin(
            id: "elysian-picnic",
            name: "Elysian Picnic Steps",
            emoji: "🌳",
            coordinate: CLLocationCoordinate2D(latitude: 34.082, longitude: -118.237),
            ownership: .currentUser
        ),
        PreviewPin(
            id: "circuit-coffee",
            name: "Circuit Coffee",
            emoji: "☕️",
            coordinate: CLLocationCoordinate2D(latitude: 34.094, longitude: -118.273),
            ownership: .currentUser,
            isSelected: true
        )
    ]

    @State private var position = MapCameraPosition.region(Self.region)

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position, interactionModes: []) {
                ForEach(Self.pins) { pin in
                    Annotation(pin.name, coordinate: pin.coordinate, anchor: .center) {
                        OnboardingLocationMapPin(pin: pin)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .allowsHitTesting(false)

            OnboardingLocationSelectedPlaceCard()
                .padding(WanderTheme.spacing3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "A rec.me map with nearby recommendations and Circuit Coffee selected. Maya and two friends rated it 4.7."
        )
    }
}

private struct PreviewPin: Identifiable {
    enum Ownership {
        case currentUser
        case social

        var color: Color {
            switch self {
            case .currentUser: WanderTheme.pinYou.color
            case .social: WanderTheme.pinSocial.color
            }
        }
    }

    let id: String
    let name: String
    let emoji: String
    let coordinate: CLLocationCoordinate2D
    let ownership: Ownership
    var isSelected = false
}

private struct OnboardingLocationMapPin: View {
    let pin: PreviewPin

    var body: some View {
        Text(pin.emoji)
            .font(.system(size: pin.isSelected ? 20 : 17))
            .frame(width: pin.isSelected ? 48 : 40, height: pin.isSelected ? 48 : 40)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(Circle())
            .background {
                if pin.isSelected {
                    Circle()
                        .fill(WanderTheme.surfaceBone.color.opacity(0.98))
                        .padding(-7)
                        .overlay(
                            Circle()
                                .stroke(WanderTheme.textInk.color.opacity(0.14), lineWidth: 1)
                                .padding(-7)
                        )
                }
            }
            .overlay(Circle().stroke(pin.ownership.color, lineWidth: pin.isSelected ? 4 : 3))
            .shadow(
                color: WanderTheme.textInk.color.opacity(0.22),
                radius: pin.isSelected ? 8 : 5,
                x: 0,
                y: 2
            )
            .accessibilityHidden(true)
    }
}

private struct OnboardingLocationSelectedPlaceCard: View {
    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Text("☕️")
                .font(.system(size: 38))
                .frame(width: 78, height: 78)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))

            VStack(alignment: .leading, spacing: 4) {
                Text(OnboardingLocationContent.selectedPlaceName)
                    .font(WanderTypography.editorialTitle)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)

                Text("Coffee · Silver Lake")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)

                HStack(spacing: 5) {
                    HStack(spacing: -5) {
                        previewAvatar("M", color: WanderTheme.avatarAndrew.color)
                        previewAvatar("R", color: WanderTheme.avatarSofia.color)
                    }
                    ViewThatFits(in: .horizontal) {
                        socialProof("Maya + 2 friends · ★ 4.7")
                        socialProof("3 friends · ★ 4.7")
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "plus")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .frame(width: 42, height: 42)
                .background(WanderTheme.surfaceRaised.color)
                .clipShape(Circle())
                .overlay(Circle().stroke(WanderTheme.terracotta.color, lineWidth: 1.5))
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusSheet, style: .continuous)
                .stroke(WanderTheme.terracotta.color.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: WanderTheme.textInk.color.opacity(0.14), radius: 12, x: 0, y: 5)
    }

    private func previewAvatar(_ initial: String, color: Color) -> some View {
        Text(initial)
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color)
            .clipShape(Circle())
            .overlay(Circle().stroke(WanderTheme.surfaceBone.color, lineWidth: 2))
    }

    private func socialProof(_ copy: String) -> some View {
        Text(copy)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(WanderTheme.terracotta.color)
            .lineLimit(1)
    }
}
