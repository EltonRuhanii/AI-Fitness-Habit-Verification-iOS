import SwiftUI

/// Signed-out entry point.
struct WelcomeView: View {
    @Environment(AppContainer.self) private var container
    @Environment(SessionStore.self) private var session
    @State private var viewModel: AuthViewModel?
    @State private var path: [AuthRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Spacer()
                hero
                Spacer()
                actions
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
            .screenBackground()
            .navigationDestination(for: AuthRoute.self) { route in
                if let viewModel {
                    switch route {
                    case .signIn: SignInView(viewModel: viewModel, path: $path)
                    case .register: RegisterView(viewModel: viewModel)
                    case .resetPassword: PasswordResetView(viewModel: viewModel)
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = AuthViewModel(auth: container.auth, session: session)
            }
        }
    }

    private var hero: some View {
        VStack(spacing: Theme.Spacing.lg) {
            AppMark(size: 96)
            VStack(spacing: Theme.Spacing.xs) {
                Text("Discipline")
                    .font(Theme.Typography.hero)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Commit. Show up. Stay accountable.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                FeatureRow(systemImage: "checkmark.seal.fill", text: "Track habits with evidence you can stand behind")
                FeatureRow(systemImage: "figure.strengthtraining.traditional", text: "Skip a day? Earn it back with a verified workout")
                FeatureRow(systemImage: "flame.fill", text: "Build a streak that means something")
            }
            .padding(.top, Theme.Spacing.md)
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button("Create account") { navigate(to: .register) }
                .buttonStyle(.primary)
                .accessibilityIdentifier("welcome.register")
            Button("I already have an account") { navigate(to: .signIn) }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("welcome.signIn")
        }
    }

    private func navigate(to route: AuthRoute) {
        viewModel?.clearMessages()
        path.append(route)
    }
}

enum AuthRoute: Hashable {
    case signIn, register, resetPassword
}

private struct FeatureRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

#Preview {
    WelcomeView()
        .environment(AppContainer.preview)
        .environment(SessionStore(auth: AppContainer.preview.auth, users: AppContainer.preview.users))
        .preferredColorScheme(.dark)
}
