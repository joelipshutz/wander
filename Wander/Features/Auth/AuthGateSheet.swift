import SwiftUI
import AuthenticationServices
import UIKit
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
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.dismiss) private var dismiss

    var isDismissable = true
    var mode: NativeAuthMode = .signInOrUp
    @State private var showsAllMethods = false

    var body: some View {
        #if canImport(ClerkKitUI) && canImport(ClerkKit)
        Group {
            if showsAllMethods {
                AuthView(mode: clerkMode, isDismissable: isDismissable)
                    .transition(.opacity)
            } else {
                AppleFirstAuthView(
                    isDismissable: isDismissable,
                    mode: mode,
                    dismiss: { dismiss() },
                    showAllMethods: { showsAllMethods = true }
                )
                .transition(.opacity)
            }
        }
        .environment(Clerk.shared)
        .environment(\.clerkTheme, recmeClerkTheme)
        .background(WanderTheme.surfaceBone.color.ignoresSafeArea())
        .interactiveDismissDisabled(auth.isSigningInWithApple)
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

private struct AppleFirstAuthView: View {
    @EnvironmentObject private var auth: AuthSessionStore

    let isDismissable: Bool
    let mode: NativeAuthMode
    let dismiss: () -> Void
    let showAllMethods: () -> Void

    private var title: String {
        switch mode {
        case .signIn:
            "Welcome back"
        case .signInOrUp:
            "Continue to \(AppBrand.displayName)"
        case .signUp:
            "Create your account"
        }
    }

    private var subtitle: String {
        switch mode {
        case .signIn:
            "Sign in to get back to your saved places and people."
        case .signInOrUp, .signUp:
            "Keep your places synced and discover recommendations from people you trust."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WanderTheme.spacing4) {
                    VStack(spacing: WanderTheme.spacing3) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(WanderTheme.terracotta.color)
                            .frame(width: 72, height: 72)
                            .background(WanderTheme.terracottaTint.color)
                            .clipShape(Circle())

                        VStack(spacing: WanderTheme.spacing2) {
                            Text(title)
                                .font(WanderTheme.editorialDisplay(size: 30, weight: .bold))
                                .multilineTextAlignment(.center)

                            Text(subtitle)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, WanderTheme.spacing4)

                    VStack(spacing: WanderTheme.spacing3) {
                        ZStack {
                            AppleIDButton(
                                type: mode == .signIn ? .signIn : .continue,
                                isEnabled: !auth.isSigningInWithApple,
                                action: startAppleSignIn
                            )
                            .opacity(auth.isSigningInWithApple ? 0.72 : 1)

                            if auth.isSigningInWithApple {
                                ProgressView()
                                    .tint(.white)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
                        .accessibilityIdentifier("auth.continueWithApple")

                        if let error = auth.appleSignInError {
                            Text(error)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WanderTheme.stateError.color)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("auth.appleError")
                        }

                        Button("Use email or Google") {
                            showAllMethods()
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(WanderTheme.surfaceRaised.color)
                        .overlay(
                            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous))
                        .disabled(auth.isSigningInWithApple)
                        .accessibilityIdentifier("auth.useOtherMethod")
                    }

                    Text("Apple can hide your email from \(AppBrand.displayName). Authentication is securely handled by Apple and Clerk.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: WanderTheme.spacing4)
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(WanderTheme.surfaceBone.color.ignoresSafeArea())
            .toolbar {
                if isDismissable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: dismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                        }
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .accessibilityLabel("Close")
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func startAppleSignIn() {
        Task { @MainActor in
            let outcome = await auth.signInWithApple()
            if outcome == .requiresClerkContinuation {
                showAllMethods()
            }
        }
    }
}

private struct AppleIDButton: UIViewRepresentable {
    let type: ASAuthorizationAppleIDButton.ButtonType
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: type, style: .black)
        button.cornerRadius = WanderTheme.radiusMedium
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.didTap),
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        button.isEnabled = isEnabled
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func didTap() {
            action()
        }
    }
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
