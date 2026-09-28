import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppContainer.self) private var container

    var body: some View {
        ZStack(alignment: .top) {
            content
                .transition(.opacity)

            if container.configuration.backend == .demo {
                DemoModeBadge()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: phaseID)
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .loading:
            LaunchView()
        case .signedOut:
            WelcomeView(auth: container.auth, session: session)
        case .onboarding:
            OnboardingView()
        case .ready(let profile):
            // Identity keyed by user so switching accounts rebuilds all per-user state.
            MainTabView(profile: profile, container: container)
                .id(profile.id)
        case .failed(let error):
            LaunchErrorView(error: error) { session.retry() }
        }
    }

    /// Coarse identity of the phase for animating transitions between flows.
    private var phaseID: Int {
        switch session.phase {
        case .loading: return 0
        case .signedOut: return 1
        case .onboarding: return 2
        case .ready: return 3
        case .failed: return 4
        }
    }
}

private struct LaunchView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            AppMark(size: 88)
            ProgressView()
                .tint(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .accessibilityLabel("Loading")
    }
}

private struct LaunchErrorView: View {
    let error: AppError
    let retry: () -> Void

    var body: some View {
        EmptyStateView(
            systemImage: "wifi.exclamationmark",
            title: "Couldn't load your account",
            message: error.localizedDescription,
            actionTitle: "Try again",
            action: retry
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

/// Always visible in demo mode so demo data is never mistaken for study data.
private struct DemoModeBadge: View {
    var body: some View {
        Text("DEMO MODE · NOT CONNECTED")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1)
            .foregroundStyle(Theme.Palette.warning)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.Palette.warning.opacity(0.15)))
            .allowsHitTesting(false)
            .accessibilityLabel("Demo mode. Not connected to the study backend.")
    }
}
