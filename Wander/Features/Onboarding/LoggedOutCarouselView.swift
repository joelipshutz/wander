import SwiftUI

enum OnboardingCarouselTiming {
    static let defaultAutoAdvanceSeconds = 7.0
}

enum OnboardingCarouselLayout {
    static let heroAspectRatio = 1.07
}

struct OnboardingCarouselSlide: Identifiable, Equatable {
    let id: Int
    let imageName: String
    let eyebrow: String
    let title: String
    let body: String

    static let all: [OnboardingCarouselSlide] = [
        OnboardingCarouselSlide(
            id: 0,
            imageName: "OnboardingMapDiary",
            eyebrow: "YOUR PLACE DIARY",
            title: "Keep track of every place you check in",
            body: "Build a map of the places worth remembering — with notes that bring every visit back."
        ),
        OnboardingCarouselSlide(
            id: 1,
            imageName: "OnboardingMapFriends",
            eyebrow: "STAY CONNECTED",
            title: "See the places your friends love",
            body: "Follow the people you know and keep their best finds close at hand."
        ),
        OnboardingCarouselSlide(
            id: 2,
            imageName: "OnboardingMapTrusted",
            eyebrow: "TRUSTED DISCOVERY",
            title: "Find places through people you trust",
            body: "Skip anonymous reviews. Discover the spots that matter to people whose taste you know."
        )
    ]
}

struct LoggedOutCarouselView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    let analytics: AnalyticsClient
    let getStarted: () -> Void
    let logIn: () -> Void

    @State private var selection = 0
    @State private var autoAdvanceGeneration = 0

    private var interval: Duration {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["WANDER_ONBOARDING_AUTO_ADVANCE_SECONDS"],
           let seconds = Double(raw) {
            return .milliseconds(Int(seconds * 1_000))
        }
        #endif
        return .milliseconds(Int(OnboardingCarouselTiming.defaultAutoAdvanceSeconds * 1_000))
    }

    private var accessibilityPausesAutoAdvance: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["WANDER_ONBOARDING_FORCE_AUTO_ADVANCE"] == "1" {
            return false
        }
        #endif
        return reduceMotion || voiceOverEnabled
    }

    var body: some View {
        ZStack {
            WanderTheme.surfaceBone.color.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text(AppBrand.displayName)
                        .font(WanderTheme.editorialDisplay(size: 28, weight: .black))
                    Spacer()
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing2)

                TabView(selection: $selection) {
                    ForEach(OnboardingCarouselSlide.all) { slide in
                        OnboardingCarouselSlideView(slide: slide)
                            .tag(slide.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .accessibilityLabel("What you can do with rec.me")

                HStack(spacing: 7) {
                    ForEach(OnboardingCarouselSlide.all) { slide in
                        Capsule()
                            .fill(slide.id == selection ? WanderTheme.textInk.color : WanderTheme.borderStrong.color)
                            .frame(width: slide.id == selection ? 24 : 7, height: 7)
                            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selection)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Carousel page")
                .accessibilityValue(String(selection + 1))
                .accessibilityIdentifier("onboarding.carouselPage")
                .padding(.bottom, WanderTheme.spacing4)

                VStack(spacing: WanderTheme.spacing2) {
                    WanderPrimaryButton(title: "Get started", systemImage: "arrow.right") {
                        analytics.track(AnalyticsEvent(
                            name: WanderAnalyticsEvents.onboardingAuthStarted,
                            properties: ["mode": "sign_up"]
                        ))
                        getStarted()
                    }
                    .accessibilityIdentifier("onboarding.getStarted")

                    Button("Already have an account? Log in") {
                        analytics.track(AnalyticsEvent(
                            name: WanderAnalyticsEvents.onboardingAuthStarted,
                            properties: ["mode": "sign_in"]
                        ))
                        logIn()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                    .accessibilityIdentifier("onboarding.logIn")
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing2)
            }
        }
        .preferredColorScheme(.light)
        .onAppear { trackViewed() }
        .onChange(of: selection) { _, _ in
            autoAdvanceGeneration += 1
            trackViewed()
        }
        .task(id: AutoAdvanceID(
            generation: autoAdvanceGeneration,
            sceneIsActive: scenePhase == .active,
            accessibilityPaused: accessibilityPausesAutoAdvance
        )) {
            guard scenePhase == .active, !accessibilityPausesAutoAdvance else { return }
            do {
                try await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                let next = (selection + 1) % OnboardingCarouselSlide.all.count
                withAnimation(.snappy(duration: 0.45)) { selection = next }
                analytics.track(AnalyticsEvent(
                    name: WanderAnalyticsEvents.onboardingCarouselAdvanced,
                    properties: ["slide": String(next), "source": "timer"]
                ))
            } catch {}
        }
    }

    private func trackViewed() {
        analytics.track(AnalyticsEvent(
            name: WanderAnalyticsEvents.onboardingCarouselViewed,
            properties: ["slide": String(selection)]
        ))
    }
}

private struct AutoAdvanceID: Equatable {
    let generation: Int
    let sceneIsActive: Bool
    let accessibilityPaused: Bool
}

private struct OnboardingCarouselSlideView: View {
    let slide: OnboardingCarouselSlide

    var body: some View {
        GeometryReader { proxy in
            let heroWidth = proxy.size.width - 32
            let heroHeight = max(280, heroWidth / OnboardingCarouselLayout.heroAspectRatio)

            VStack(spacing: WanderTheme.spacing4) {
                Image(slide.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: heroWidth, height: heroHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                    )
                    .shadow(color: WanderTheme.textInk.color.opacity(0.12), radius: 18, y: 9)

                VStack(spacing: WanderTheme.spacing2) {
                    Text(slide.eyebrow)
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.6)
                        .foregroundStyle(WanderTheme.terracotta.color)

                    Text(slide.title)
                        .font(WanderTheme.editorialDisplay(size: 35, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineSpacing(-2)
                        .minimumScaleFactor(0.82)

                    Text(slide.body)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, WanderTheme.spacing4)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
        }
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingLaunchView: View {
    var body: some View {
        ZStack {
            WanderTheme.canvasWarm.color.ignoresSafeArea()
            VStack(spacing: WanderTheme.spacing2) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(WanderTheme.terracotta.color)
                Text(AppBrand.displayName)
                    .font(WanderTheme.editorialDisplay(size: 42, weight: .black))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opening rec.me")
    }
}
