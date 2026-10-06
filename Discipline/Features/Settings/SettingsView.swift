import SwiftUI
import UserNotifications
import DisciplineCore

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(HabitsStore.self) private var store
    @Environment(AppContainer.self) private var container
    @Environment(\.openURL) private var openURL
    @AppStorage("appearance") private var appearance: AppearancePreference = .dark

    @State private var confirmsEvidenceDeletion = false
    @State private var confirmsAccountDeletion = false
    @State private var isWorking = false
    @State private var message: (text: String, isError: Bool)?

    var body: some View {
        @Bindable var preferences = container.notificationPreferences
        Form {
            notificationsSection(preferences: $preferences.preferences)

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }

            Section("Privacy & AI") {
                NavigationLink("How your data is used") { PrivacyInfoView() }
                NavigationLink("About AI verification") { AIVerificationInfoView() }
                NavigationLink("Performance") { PerformanceView() }
                    .accessibilityIdentifier("settings.performance")
            }

            Section {
                Button("Delete my evidence photos", role: .destructive) { confirmsEvidenceDeletion = true }
                    .disabled(isWorking)
                    .accessibilityIdentifier("settings.deleteEvidence")
            } header: {
                Text("Your data")
            } footer: {
                Text("Removes all your evidence photos. Your habit history and verification outcomes (which contain no images) are kept.")
            }

            if let message {
                Section {
                    InlineMessage(text: message.text, style: message.isError ? .error : .success)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                Button("Sign out") { signOut() }
                    .accessibilityIdentifier("settings.signOut")
                Button("Delete account", role: .destructive) { confirmsAccountDeletion = true }
                    .disabled(isWorking)
            } header: {
                Text("Account")
            } footer: {
                Text("Deleting your account permanently removes your profile, habits, evidence photos and research records.")
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await container.notifications.refreshAuthorization() }
        .onChange(of: container.notificationPreferences.preferences) { _, _ in store.scheduleNotifications() }
        .confirmationDialog("Delete all evidence photos?", isPresented: $confirmsEvidenceDeletion, titleVisibility: .visible) {
            Button("Delete photos", role: .destructive) { Task { await deleteEvidence() } }
        } message: {
            Text("This can't be undone.")
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmsAccountDeletion, titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: Notifications

    @ViewBuilder
    private func notificationsSection(preferences: Binding<NotificationPreferences>) -> some View {
        Section {
            if container.notifications.authorization == .denied {
                Button("Notifications are off in iOS Settings. Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(Theme.Typography.callout)
            }
            Toggle("Notifications", isOn: preferences.enabled)
                .onChange(of: preferences.wrappedValue.enabled) { _, enabled in
                    if enabled { Task { await container.notifications.requestAuthorizationIfNeeded() } }
                }
            if preferences.wrappedValue.enabled {
                Toggle("Evening reminder", isOn: preferences.dailyReminder)
                if preferences.wrappedValue.dailyReminder {
                    DatePicker("Reminder time", selection: reminderTime(preferences), displayedComponents: .hourAndMinute)
                }
                Toggle("Accountability deadlines", isOn: preferences.accountabilityDeadlines)
                Toggle("Streak warning", isOn: preferences.streakWarning)
                Toggle("Weekly summary", isOn: preferences.weeklySummary)
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Only when something is still open. At most \(NotificationPlanner.maxPerDay) a day, and never between \(preferences.wrappedValue.quietStartHour):00 and \(String(format: "%02d", preferences.wrappedValue.quietEndHour)):00.")
        }
    }

    private func reminderTime(_ preferences: Binding<NotificationPreferences>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: preferences.wrappedValue.reminderHour,
                                      minute: preferences.wrappedValue.reminderMinute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                preferences.wrappedValue.reminderHour = parts.hour ?? 18
                preferences.wrappedValue.reminderMinute = parts.minute ?? 0
            }
        )
    }

    // MARK: Actions

    private func deleteEvidence() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let count = try await container.evidence.deleteAllEvidence(userId: store.userId)
            message = ("Deleted \(count) evidence photo\(count == 1 ? "" : "s").", false)
        } catch {
            message = (AppError.from(error).localizedDescription, true)
        }
    }

    private func signOut() {
        Task { await container.notifications.cancelAll() }
        do {
            try session.signOut()
        } catch {
            message = (AppError.from(error).localizedDescription, true)
        }
    }

    private func deleteAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            await container.notifications.cancelAll()
            try await session.deleteAccount()
        } catch {
            message = (AppError.from(error).localizedDescription, true)
        }
    }
}
