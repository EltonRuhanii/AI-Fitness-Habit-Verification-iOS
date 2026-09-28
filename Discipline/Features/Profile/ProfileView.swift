import SwiftUI
import DisciplineCore

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(HabitsStore.self) private var store
    @AppStorage("appearance") private var appearance: AppearancePreference = .dark

    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let profile = session.profile {
                    Section {
                        ProfileHeader(profile: profile)
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

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        InlineMessage(text: errorMessage)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    Button("Sign out") { signOut() }
                        .accessibilityIdentifier("profile.signOut")
                    Button("Delete account", role: .destructive) { confirmsDeletion = true }
                        .disabled(isDeleting)
                } footer: {
                    Text("Deleting your account permanently removes your profile, habits, evidence photos and research records.")
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Profile")
            .confirmationDialog(
                "Delete your account?",
                isPresented: $confirmsDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete permanently", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func signOut() {
        do {
            try session.signOut()
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await session.deleteAccount()
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
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
