import SwiftUI
#if canImport(ClerkKit)
import ClerkKit
#endif
#if canImport(ClerkKitUI)
import ClerkKitUI
#endif

struct AuthGateSheet: View {
    @EnvironmentObject private var auth: AuthSessionStore
    let request: AuthGateRequest

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(WanderTheme.terracotta.color)
                .frame(width: 58, height: 58)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text(request.copy.title)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                Text(request.copy.message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .unavailable(let message) = auth.state {
                Text(message)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.stateError.color)
                    .padding(WanderTheme.spacing3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WanderTheme.terracottaTint.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            }

            VStack(spacing: WanderTheme.spacing2) {
                WanderPrimaryButton(title: request.copy.primaryAction, systemImage: "person.crop.circle") {
                    auth.beginSignIn()
                }

                if let secondaryAction = request.copy.secondaryAction {
                    Button(secondaryAction) {
                        auth.dismissGate()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
    }
}

struct ClerkNativeAuthView: View {
    var isDismissable = true
    var mode: NativeAuthMode = .signInOrUp

    var body: some View {
        #if canImport(ClerkKitUI) && canImport(ClerkKit)
        AuthView(mode: clerkMode, isDismissable: isDismissable)
            .environment(Clerk.shared)
            .environment(\.clerkTheme, recmeClerkTheme)
            .background(WanderTheme.surfaceBone.color.ignoresSafeArea())
        #elseif canImport(ClerkKitUI)
        AuthView(mode: clerkMode, isDismissable: isDismissable)
        #else
        VStack(spacing: WanderTheme.spacing3) {
            Text("Sign in is not linked in this build.")
                .font(.system(size: 20, weight: .black))
            Text("ClerkKitUI needs to be available from SwiftPM.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .padding(WanderTheme.spacing4)
        .wanderScreen()
        #endif
    }

    #if canImport(ClerkKitUI)
    private var clerkMode: AuthView.Mode {
        switch mode {
        case .signInOrUp: .signInOrUp
        case .signIn: .signIn
        case .signUp: .signUp
        }
    }

    @MainActor
    private var recmeClerkTheme: ClerkTheme {
        ClerkTheme(
            colors: .init(
                primary: WanderTheme.terracotta.color,
                danger: WanderTheme.stateError.color,
                primaryForeground: WanderTheme.textOnAction.color,
                neutral: WanderTheme.textInk.color,
                muted: WanderTheme.textMuted.color
            ),
            design: .init(borderRadius: WanderTheme.radiusMedium)
        )
    }
    #endif
}

struct ClerkAccountManagementView: View {
    var body: some View {
        #if canImport(ClerkKitUI) && canImport(ClerkKit)
        UserProfileView()
            .environment(Clerk.shared)
        #else
        VStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 30, weight: .bold))
            Text("Account management is not linked in this build.")
                .font(.system(size: 18, weight: .black))
                .multilineTextAlignment(.center)
        }
        .padding(WanderTheme.spacing4)
        .wanderScreen()
        #endif
    }
}
