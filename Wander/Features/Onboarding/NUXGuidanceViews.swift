import SwiftUI

enum NUXCoachMotion: String, CaseIterable {
    case pop, slide

    static var selected: Self {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-WanderNUXSlide") || (args.contains("-WanderNUXReview")
            && UserDefaults.standard.string(forKey: "nux.review.motion") == "slide") ? .slide : .pop
        #else
        return .pop
        #endif
    }

    var transition: AnyTransition {
        switch self {
        case .pop: .asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity),
                              removal: .offset(y: -10).combined(with: .opacity))
        case .slide: .asymmetric(insertion: .offset(y: 18).combined(with: .opacity),
                                removal: .offset(y: -14).combined(with: .opacity))
        }
    }
}

/// Native coach chrome shared by the production tour and simulator review.
/// Decorative elements never intercept touches to the real app underneath.
struct NUXGuidanceOverlay: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var entered = false
    let step: WalkthroughStep
    let target: CGRect
    let additionalTargets: [WalkthroughTargetID: CGRect]
    let size: CGSize
    let safeTop: CGFloat
    let next: () -> Void

    private var handwritten: Bool { step.target == .addNearby || step.target == .placeSaveActions }
    private var ink: Color { brand.prefersDarkInterface ? .white : .black }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if handwritten {
                    annotations
                } else {
                    if step.surface == .map {
                        RoundedRectangle(cornerRadius: min(24, target.height / 2))
                            .stroke(brand.accentText.opacity(entered ? 0.5 : 0.9), lineWidth: 2)
                            .frame(width: target.width + 8, height: target.height + 8)
                            .scaleEffect(entered ? 1 : 1.12)
                            .position(x: target.midX, y: target.midY)
                    }
                    coach
                }
            }
            .allowsHitTesting(false)

            Button(action: next) {
                HStack(spacing: 5) {
                    Text("Next")
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
                }
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(brand.primaryText)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(brand.border.opacity(0.6), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("walkthrough.next.\(step.id)")
            .position(x: size.width - (step.surface == .add ? 104 : 55),
                      y: step.surface == .add ? max(32, safeTop + 24) : step.surface == .placeDetail ? max(126, safeTop + 70) : max(82, safeTop + 26))
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walkthrough.\(step.id)")
        .task {
            withAnimation(reduceMotion || handwritten ? nil : .spring(duration: 0.42, bounce: 0.18)) {
                entered = true
            }
        }
    }

    private var coach: some View {
        let isUpper = target.midY < size.height * 0.46
        let normalTop = isUpper ? min(target.maxY + 24, size.height * 0.46) : max(150, target.minY - 164)
        let top = step.target == .mapMoreFilters ? min(target.maxY + 16, size.height - 224) : normalTop
        let width = min(size.width - 40, typeSize.isAccessibilitySize ? 370 : 320)
        return VStack(alignment: .leading, spacing: 9) {
            if step.surface == .map {
                Text("A QUICK LOOK AROUND · DEMO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(brand.accentText)
            }
            Text(step.title)
                .font(AstirTypography.cardTitle)
                .foregroundStyle(brand.primaryText)
            Text(step.message)
                .font(AstirTypography.bodySmall)
                .foregroundStyle(brand.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(19)
        .frame(width: width, alignment: .leading)
        .background(brand.raisedBackground.opacity(0.96), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(brand.border.opacity(0.7), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.09), radius: 18, y: 8)
        .scaleEffect(reduceMotion || entered || NUXCoachMotion.selected == .slide ? 1 : 0.94)
        .offset(x: min(max(target.midX - width / 2, 20), size.width - width - 20),
                y: top + (reduceMotion || entered ? 0 : 16))
        .opacity(entered ? 1 : 0)
    }

    @ViewBuilder
    private var annotations: some View {
        if step.target == .placeSaveActions {
            if let checkIn = additionalTargets[.placeCheckIn] {
                annotation("Places you’ve\nbeen", target: checkIn, side: -1)
            }
            if let wanna = additionalTargets[.placeWanna] {
                annotation("Places you\nwant to go", target: wanna, side: 1)
            }
        } else {
            annotation("Your nearby places\nwill show up here", target: target, side: 1)
        }
    }

    private func annotation(_ text: String, target: CGRect, side: CGFloat) -> some View {
        let nearby = step.target == .addNearby
        let width: CGFloat = nearby ? min(182, size.width * 0.46) : min(150, size.width * 0.40)
        let x = nearby ? size.width - width / 2 - 18 : size.width * (side < 0 ? 0.25 : 0.75)
        let y = nearby ? target.midY - 13 : max(136, target.minY - 100)
        let start = nearby ? CGPoint(x: x - width / 2 + 6, y: y - 2) : CGPoint(x: x, y: y + 32)
        let end = nearby ? CGPoint(x: target.maxX + 8, y: target.midY - 4) : CGPoint(x: target.midX, y: target.minY - 7)
        return ZStack(alignment: .topLeading) {
            NUXHandDrawnOval()
                .stroke(ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: target.width + 14, height: target.height + 12)
                .position(x: target.midX, y: target.midY)
            NUXHandDrawnArrow(start: start, end: end, bend: nearby ? -10 : side * 22)
                .stroke(ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            Text(text)
                .font(.custom("Noteworthy-Bold", size: nearby ? 18 : 20, relativeTo: .title3))
                .multilineTextAlignment(.center)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width)
                .rotationEffect(.degrees(side * -3))
                .position(x: x, y: y)
        }
        .shadow(color: brand.background.opacity(0.95), radius: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.replacingOccurrences(of: "\n", with: " "))
    }

}

struct NUXHandDrawnOval: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.19, y: rect.height * 0.09))
        path.addCurve(to: CGPoint(x: rect.width * 0.88, y: rect.height * 0.12),
                      control1: CGPoint(x: rect.width * 0.4, y: -3),
                      control2: CGPoint(x: rect.width * 0.76, y: 0))
        path.addCurve(to: CGPoint(x: rect.width * 0.89, y: rect.height * 0.87),
                      control1: CGPoint(x: rect.width + 10, y: rect.height * 0.25),
                      control2: CGPoint(x: rect.width + 3, y: rect.height * 0.71))
        path.addCurve(to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.89),
                      control1: CGPoint(x: rect.width * 0.69, y: rect.height + 3),
                      control2: CGPoint(x: rect.width * 0.27, y: rect.height + 5))
        path.addCurve(to: CGPoint(x: rect.width * 0.28, y: rect.height * 0.045),
                      control1: CGPoint(x: -12, y: rect.height * 0.74),
                      control2: CGPoint(x: -3, y: rect.height * 0.03))
        return path
    }
}

struct NUXHandDrawnArrow: Shape {
    let start: CGPoint
    let end: CGPoint
    let bend: CGFloat
    func path(in rect: CGRect) -> Path {
        let control = CGPoint(x: start.x + bend, y: (start.y + end.y) / 2)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        let angle = atan2(end.y - control.y, end.x - control.x)
        for offset in [-0.55, 0.55] {
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x - 10 * cos(angle + offset), y: end.y - 10 * sin(angle + offset)))
        }
        return path
    }
}

struct NUXConnectionFinale: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    let step: WalkthroughStep
    let size: CGSize
    let finish: () -> Void

    private var usesOriginalQuote: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-WanderNUXOriginalFinale")
            || (ProcessInfo.processInfo.arguments.contains("-WanderNUXReview")
                && UserDefaults.standard.bool(forKey: "nux.review.originalQuote"))
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle().fill(.ultraThinMaterial).opacity(0.88)
            VStack(spacing: 22) {
                Text("ASTIR")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2).foregroundStyle(brand.accentText)
                Text(usesOriginalQuote ? step.message : "Life happens\nbetween us.")
                    .font(.system(size: usesOriginalQuote ? min(30, size.width * 0.075) : min(48, size.width * 0.115), weight: .medium, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(brand.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(usesOriginalQuote ? "Your map is yours now." : "Your people. Your places.\nA little more connected.")
                    .font(AstirTypography.body)
                    .foregroundStyle(brand.secondaryText)
                    .multilineTextAlignment(.center)
                Button("Enjoy") { finish() }
                    .font(AstirTypography.control)
                    .foregroundStyle(brand.accentText)
                    .frame(minWidth: 100, minHeight: 44)
                    .accessibilityIdentifier("nux.finale.enjoy")
            }
            .frame(width: size.width - 48)
            .position(x: size.width / 2, y: size.height * 0.45)
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 14)
            Button("Skip", action: finish)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(brand.primaryText)
                .frame(width: 72, height: 44)
                .padding(.top, 62).padding(.trailing, 16)
                .accessibilityIdentifier("walkthrough.next.\(step.id)")
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walkthrough.\(step.id)")
        .task(id: scenePhase) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { visible = true }
            guard scenePhase == .active, !FirstVisitWalkthroughContent.holdsAutomaticAdvanceForCapture,
                  !UIAccessibility.isVoiceOverRunning, !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(FirstVisitWalkthroughContent.finaleAutoAdvanceMilliseconds))
            guard !Task.isCancelled else { return }
            finish()
        }
    }
}
