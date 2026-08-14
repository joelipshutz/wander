import AuthenticationServices
import SwiftUI
import UIKit

struct NativeAuthFlowView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.dismiss) private var dismiss

    let isDismissable: Bool
    let mode: NativeAuthMode

    @State private var emailAddress = ""
    @State private var verificationCode = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case code
    }

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
                Group {
                    if let verificationAddress = auth.emailVerificationAddress {
                        emailCodeForm(address: verificationAddress)
                    } else {
                        methodPicker
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing6)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WanderTheme.surfaceBone.color.ignoresSafeArea())
            .toolbar {
                if isDismissable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .frame(
                                    width: WanderTheme.tapMinimum,
                                    height: WanderTheme.tapMinimum
                                )
                        }
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .accessibilityLabel("Close")
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(auth.isPerformingNativeAuth)
    }

    private var methodPicker: some View {
        VStack(spacing: WanderTheme.spacing4) {
            authHeader

            VStack(spacing: WanderTheme.spacing3) {
                appleButton
                googleButton
            }

            authDivider

            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                Text("Email")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)

                TextField("you@example.com", text: $emailAddress)
                    .font(.system(size: 16, weight: .medium))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .submitLabel(.continue)
                    .focused($focusedField, equals: .email)
                    .padding(.horizontal, WanderTheme.spacing4)
                    .frame(minHeight: 52)
                    .background(WanderTheme.surfaceRaised.color)
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: WanderTheme.radiusMedium,
                            style: .continuous
                        )
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: WanderTheme.radiusMedium,
                            style: .continuous
                        )
                    )
                    .accessibilityIdentifier("auth.email")
                    .onSubmit(sendEmailCode)

                Button(action: sendEmailCode) {
                    ZStack {
                        Text("Continue with email")
                            .font(.system(size: 16, weight: .bold))
                        if auth.isSendingEmailCode {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(WanderTheme.textOnAction.color)
                            }
                        }
                    }
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: WanderTheme.radiusMedium,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .disabled(auth.isPerformingNativeAuth)
                .opacity(auth.isPerformingNativeAuth ? 0.72 : 1)
                .accessibilityIdentifier("auth.continueWithEmail")
            }

            authError

            VStack(spacing: WanderTheme.spacing2) {
                Text("If Apple or Google returns the same verified email, it connects to your existing \(AppBrand.displayName) account.")
                    .accessibilityIdentifier("auth.accountLinkingExplanation")

                Text(.init("By continuing, you agree to the [Terms of Use](https://getrec.me/terms) and [Community Guidelines](https://getrec.me/community), and acknowledge the [Privacy Policy](https://getrec.me/privacy)."))
                    .accessibilityIdentifier("auth.legalAcknowledgement")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(WanderTheme.textMuted.color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var authHeader: some View {
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
    }

    private var appleButton: some View {
        ZStack {
            NativeAppleIDButton(
                type: mode == .signIn ? .signIn : .continue,
                isEnabled: !auth.isPerformingNativeAuth,
                action: { authenticate(with: .apple) }
            )
            .opacity(auth.isPerformingNativeAuth ? 0.72 : 1)

            if auth.activeSocialAuthProvider == .apple {
                ProgressView()
                    .tint(.white)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
        .accessibilityIdentifier("auth.continueWithApple")
    }

    private var googleButton: some View {
        Button {
            authenticate(with: .google)
        } label: {
            ZStack {
                Text(mode == .signIn ? "Sign in with Google" : "Continue with Google")
                    .font(.system(size: 16, weight: .bold))

                HStack {
                    Text("G")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                        .accessibilityHidden(true)
                    Spacer()

                    if auth.activeSocialAuthProvider == .google {
                        ProgressView()
                            .tint(WanderTheme.textInk.color)
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
            }
            .foregroundStyle(WanderTheme.textInk.color)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(WanderTheme.surfaceRaised.color)
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(auth.isPerformingNativeAuth)
        .opacity(auth.isPerformingNativeAuth ? 0.72 : 1)
        .accessibilityIdentifier("auth.continueWithGoogle")
    }

    private var authDivider: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Rectangle()
                .fill(WanderTheme.borderHairline.color)
                .frame(height: 1)
            Text("or")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
            Rectangle()
                .fill(WanderTheme.borderHairline.color)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private func emailCodeForm(address: String) -> some View {
        VStack(spacing: WanderTheme.spacing4) {
            VStack(spacing: WanderTheme.spacing3) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(width: 68, height: 68)
                    .background(WanderTheme.terracottaTint.color)
                    .clipShape(Circle())

                Text("Check your email")
                    .font(WanderTheme.editorialDisplay(size: 30, weight: .bold))

                Text("Enter the verification code sent to \(address).")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, WanderTheme.spacing4)

            TextField("Verification code", text: $verificationCode)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focusedField, equals: .code)
                .padding(.horizontal, WanderTheme.spacing4)
                .frame(minHeight: 56)
                .background(WanderTheme.surfaceRaised.color)
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                )
                .accessibilityIdentifier("auth.emailCode")
                .onAppear { focusedField = .code }

            Button(action: verifyEmailCode) {
                ZStack {
                    Text("Verify and continue")
                        .font(.system(size: 16, weight: .bold))
                    if auth.isVerifyingEmailCode {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(WanderTheme.textOnAction.color)
                        }
                    }
                }
                .foregroundStyle(WanderTheme.textOnAction.color)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(WanderTheme.terracotta.color)
                .clipShape(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(auth.isPerformingNativeAuth)
            .opacity(auth.isPerformingNativeAuth ? 0.72 : 1)
            .accessibilityIdentifier("auth.verifyEmailCode")

            authError

            VStack(spacing: WanderTheme.spacing2) {
                Button("Send a new code") {
                    Task { await auth.sendEmailCode(to: address) }
                }
                .disabled(auth.isPerformingNativeAuth)

                Button("Use another sign-in method") {
                    verificationCode = ""
                    auth.cancelEmailVerification()
                    focusedField = .email
                }
                .disabled(auth.isPerformingNativeAuth)
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(WanderTheme.textInk.color)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var authError: some View {
        if let error = auth.nativeAuthError {
            Text(error)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WanderTheme.stateError.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(WanderTheme.spacing3)
                .frame(maxWidth: .infinity)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                )
                .accessibilityIdentifier("auth.error")
        }
    }

    private func authenticate(with provider: NativeSocialAuthProvider) {
        focusedField = nil
        Task { await auth.authenticate(with: provider) }
    }

    private func sendEmailCode() {
        focusedField = nil
        Task { await auth.sendEmailCode(to: emailAddress) }
    }

    private func verifyEmailCode() {
        focusedField = nil
        Task { await auth.verifyEmailCode(verificationCode) }
    }
}

private struct NativeAppleIDButton: UIViewRepresentable {
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
