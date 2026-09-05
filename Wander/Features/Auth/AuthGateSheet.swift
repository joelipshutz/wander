import SwiftUI
#if canImport(ClerkKit)
import ClerkKit
#endif
#if canImport(ClerkKitUI)
import ClerkKitUI
#endif

struct AuthGateSheet: View {
    @Environment(\.astirBrandMode) private var brandMode
    @EnvironmentObject private var auth: AuthSessionStore
    let request: AuthGateRequest

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(brandMode.accentText)
                .frame(width: 58, height: 58)
                .background(brandMode.accentWash)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text(request.copy.title)
                    .font(AstirTypography.sheetTitle)
                Text(request.copy.message)
                    .font(AstirTypography.body)
                    .foregroundStyle(brandMode.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .unavailable(let message) = auth.state {
                Text(message)
                    .font(AstirTypography.caption)
                    .foregroundStyle(WanderTheme.stateError.color)
                    .padding(WanderTheme.spacing3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(brandMode.accentWash)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous))
            }

            VStack(spacing: WanderTheme.spacing2) {
                WanderPrimaryButton(title: request.copy.primaryAction, systemImage: "person.crop.circle") {
                    auth.beginSignIn()
                }

                if let secondaryAction = request.copy.secondaryAction {
                    Button(secondaryAction) {
                        auth.dismissGate()
                    }
                    .font(AstirTypography.control)
                    .foregroundStyle(brandMode.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(brandMode.primaryText)
        .background(brandMode.background.ignoresSafeArea())
    }
}

/// Keeps the existing call-site name while rec.me owns the full login UI.
/// Clerk remains the identity backend, but its generic AuthView is intentionally
/// not presented from the logged-out flow.
struct ClerkNativeAuthView: View {
    var isDismissable = true
    var mode: NativeAuthMode = .signInOrUp

    var body: some View {
        NativeAuthFlowView(isDismissable: isDismissable, mode: mode)
    }
}

struct ClerkAccountManagementView: View {
    @Environment(\.astirBrandMode) private var brandMode

    var body: some View {
        #if canImport(ClerkKitUI) && canImport(ClerkKit)
        UserProfileView()
            .environment(Clerk.shared)
            .tint(brandMode.accent)
            .foregroundStyle(brandMode.primaryText)
            .background(brandMode.background.ignoresSafeArea())
        #else
        VStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 30, weight: .bold))
            Text("Account management is not linked in this build.")
                .font(AstirTypography.sectionTitle)
                .multilineTextAlignment(.center)
        }
        .padding(WanderTheme.spacing4)
        .astirScreen()
        #endif
    }
}
