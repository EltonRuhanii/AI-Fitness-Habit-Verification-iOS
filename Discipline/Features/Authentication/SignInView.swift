import SwiftUI

struct SignInView: View {
    @Bindable var viewModel: AuthViewModel
    @Binding var path: [AuthRoute]

    var body: some View {
        AuthFormScaffold(title: "Welcome back", subtitle: "Sign in to continue your streak.") {
            FormField(title: "Email", systemImage: "envelope", text: $viewModel.email, kind: .email)
                .accessibilityIdentifier("signIn.email")
            FormField(title: "Password", systemImage: "lock", text: $viewModel.password, kind: .password)
                .accessibilityIdentifier("signIn.password")

            HStack {
                Spacer()
                Button("Forgot password?") {
                    viewModel.clearMessages()
                    path.append(.resetPassword)
                }
                .font(Theme.Typography.callout)
            }

            if let error = viewModel.errorMessage {
                InlineMessage(text: error)
            }
        } footer: {
            Button("Sign in") {
                Task { await viewModel.signIn() }
            }
            .buttonStyle(.primary(isLoading: viewModel.isLoading))
            .disabled(!viewModel.canSignIn)
            .accessibilityIdentifier("signIn.submit")
        }
        .onSubmit { Task { await viewModel.signIn() } }
    }
}

/// Shared layout for the authentication forms: title block, scrolling fields, pinned action.
struct AuthFormScaffold<Fields: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var fields: Fields
    @ViewBuilder var footer: Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(subtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .padding(.bottom, Theme.Spacing.sm)

                fields
            }
            .padding(Theme.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            footer
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Palette.background)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}
