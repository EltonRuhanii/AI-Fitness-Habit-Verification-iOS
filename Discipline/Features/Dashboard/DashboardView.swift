import SwiftUI

/// Today's commitments. Phase 1 shell — habits and progress arrive in Phases 2–3.
struct DashboardView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    SectionEyebrow(title: "Today")
                    EmptyStateView(
                        systemImage: "checklist",
                        title: "No commitments yet",
                        message: "Create your first habit or join a challenge to see today's commitments here."
                    )
                    .card()
                }
                .padding(Theme.Spacing.md)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(Theme.Typography.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.Palette.textSecondary)
            Text("Hi, \(session.profile?.displayName ?? "there")")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.top, Theme.Spacing.md)
    }
}
