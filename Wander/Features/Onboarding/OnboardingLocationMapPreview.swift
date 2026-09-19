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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var isPlaying = true

    private static let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.085, longitude: -118.276),
        span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
    )

    private static let pins = [
        PreviewPin(
            id: "larchmont-noodles",
            name: "Larchmont Noodles",
            systemImage: "fork.knife",
            coordinate: CLLocationCoordinate2D(latitude: 34.073, longitude: -118.323),
            ownership: .social
        ),
        PreviewPin(
            id: "griffith-trail",
            name: "Griffith Observatory Trail",
            systemImage: "figure.hiking",
            coordinate: CLLocationCoordinate2D(latitude: 34.119, longitude: -118.300),
            ownership: .social
        ),
        PreviewPin(
            id: "woodcat-coffee",
            name: "Woodcat Coffee",
            systemImage: "cup.and.saucer.fill",
            coordinate: CLLocationCoordinate2D(latitude: 34.077, longitude: -118.260),
            ownership: .currentUser
        ),
        PreviewPin(
            id: "bar-nido",
            name: "Bar Nido",
            systemImage: "fork.knife",
            coordinate: CLLocationCoordinate2D(latitude: 34.079, longitude: -118.260),
            ownership: .social
        ),
        PreviewPin(
            id: "elysian-picnic",
            name: "Elysian Picnic Steps",
            systemImage: "tree.fill",
            coordinate: CLLocationCoordinate2D(latitude: 34.082, longitude: -118.237),
            ownership: .currentUser
        ),
        PreviewPin(
            id: "circuit-coffee",
            name: "Circuit Coffee",
            systemImage: "cup.and.saucer.fill",
            coordinate: CLLocationCoordinate2D(latitude: 34.094, longitude: -118.273),
            ownership: .currentUser,
            isSelected: true
        )
    ]

    @State private var position = MapCameraPosition.region(Self.region)
    @State private var revealedPinCount = 0
    @State private var cardIsVisible = false

    private var shouldAnimate: Bool {
        isPlaying && scenePhase == .active && !reduceMotion && !voiceOverEnabled
    }

    private static var entranceRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.082, longitude: -118.280),
            span: MKCoordinateSpan(latitudeDelta: 0.052, longitudeDelta: 0.052)
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position, interactionModes: []) {
                ForEach(Array(Self.pins.enumerated()), id: \.element.id) { index, pin in
                    Annotation(pin.name, coordinate: pin.coordinate, anchor: .center) {
                        OnboardingLocationMapPin(pin: pin)
                            .opacity(!shouldAnimate || index < revealedPinCount ? 1 : 0)
                            .scaleEffect(!shouldAnimate || index < revealedPinCount ? 1 : 0.92)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .allowsHitTesting(false)

            OnboardingLocationSelectedPlaceCard()
                .padding(WanderTheme.spacing3)
                .opacity(!shouldAnimate || cardIsVisible ? 1 : 0)
                .offset(y: !shouldAnimate || cardIsVisible ? 0 : 18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "An Astir map with nearby recommendations and Circuit Coffee selected. Maya and two friends rated it 4.7."
        )
        .task(id: shouldAnimate) {
            guard shouldAnimate else {
                settleEntrance()
                return
            }
            await playEntrance()
        }
    }

    @MainActor
    private func playEntrance() async {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position = .region(Self.entranceRegion)
            revealedPinCount = 0
            cardIsVisible = false
        }
        do {
            try await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 2.2)) {
                position = .region(Self.region)
            }
            for index in Self.pins.indices {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.28)) {
                    revealedPinCount = index + 1
                }
                try await Task.sleep(for: .milliseconds(90))
            }
            try await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                cardIsVisible = true
            }
        } catch {
            // SwiftUI cancels on page changes, backgrounding and disappearance.
        }
    }

    @MainActor
    private func settleEntrance() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position = .region(Self.region)
            revealedPinCount = Self.pins.count
            cardIsVisible = true
        }
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
    let systemImage: String
    let coordinate: CLLocationCoordinate2D
    let ownership: Ownership
    var isSelected = false
}

private struct OnboardingLocationMapPin: View {
    let pin: PreviewPin

    var body: some View {
        Image(systemName: pin.systemImage)
            .font(.system(size: pin.isSelected ? 20 : 17, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(pin.ownership.color)
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
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 32, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(WanderTheme.terracotta.color)
                .frame(width: 78, height: 78)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))

            VStack(alignment: .leading, spacing: 4) {
                Text(OnboardingLocationContent.selectedPlaceName)
                    .font(AstirTypography.sheetTitle)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)

                Text("Coffee · Silver Lake")
                    .font(AstirTypography.caption)
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
            .font(AstirTypography.metadata)
            .foregroundStyle(WanderTheme.terracotta.color)
            .lineLimit(1)
    }
}
