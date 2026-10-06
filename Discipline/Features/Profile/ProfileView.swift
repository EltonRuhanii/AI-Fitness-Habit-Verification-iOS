import SwiftUI
import DisciplineCore

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(HabitsStore.self) private var store
    @Environment(AppContainer.self) private var container
    @State private var isResearcher = false

    var body: some View {
        NavigationStack {
            List {
                if let profile = session.profile {
                    Section {
                        ProfileHeader(profile: profile)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    Section {
                        statisticsGrid
                    } header: {
                        Text("Statistics")
                    } footer: {
                        Text("Over the last \(HabitsStore.historyDays) days.")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    Section("Study") {
                        LabeledContent("Participant ID") {
                            Text(profile.participantId)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        LabeledContent("Tracking mode", value: profile.trackingCondition.displayName)
                        NavigationLink {
                            UsabilityQuestionnaireView()
                        } label: {
                            Label("Usability questionnaire", systemImage: "list.bullet.clipboard")
                        }
                        .accessibilityIdentifier("profile.sus")
                    }
                }

                Section("Challenge") {
                    NavigationLink {
                        ChallengeHubView()
                    } label: {
                        LabeledContent("Current challenge", value: store.activeChallenge?.name ?? store.upcomingChallenge?.name ?? "None")
                    }
                    .accessibilityIdentifier("profile.challenge")
                }

                if isResearcher || container.configuration.backend == .demo {
                    Section {
                        NavigationLink {
                            ResearchDashboardView(service: researchService)
                        } label: {
                            Label("Research dashboard", systemImage: "chart.bar.doc.horizontal")
                        }
                        .accessibilityIdentifier("profile.research")
                    } header: {
                        Text("Research")
                    } footer: {
                        Text(isResearcher ? "Visible to study researchers only." : "Demo preview of the research views using your local data.")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("profile.settings")
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Profile")
            .task { isResearcher = await container.auth.isResearcher() }
        }
    }

    private var statisticsGrid: some View {
        let stats = store.statistics
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
            stat("Current streak", "\(store.streak.current)", unit: "days")
            stat("Longest streak", "\(store.streak.longest)", unit: "days")
            stat("Completed", "\(stats.totalCompleted)", unit: "habits")
            stat("Verified", "\(stats.verified)", unit: "by AI")
            stat("Accountability done", "\(stats.accountabilityCompleted)", unit: "tasks")
            stat("Accountability missed", "\(stats.accountabilityFailed)", unit: "tasks")
        }
    }

    private func stat(_ title: String, _ value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(Theme.Typography.eyebrow)
                .tracking(1)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.Typography.title2.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(unit)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .card(padding: Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    private var researchService: ResearchService {
        if container.configuration.backend == .firebase {
            return FirebaseResearchService()
        }
        let participantId = session.profile?.participantId ?? "P-DEMO"
        return LocalResearchService(
            records: { [store] in store.localResearchRecords(participantId: participantId) },
            usability: { [container] in container.usability.localResponses() ?? [] }
        )
    }
}

private struct ProfileHeader: View {
    let profile: UserProfile

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(initials)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(Circle().fill(Theme.Palette.emberGradient))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(profile.displayName)
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(profile.email)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var initials: String {
        let parts = profile.displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
