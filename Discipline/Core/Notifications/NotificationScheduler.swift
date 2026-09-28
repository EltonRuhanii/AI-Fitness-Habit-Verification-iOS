import Foundation
import Observation
import UserNotifications
import DisciplineCore

/// Persisted notification preferences (per device).
@MainActor
@Observable
final class NotificationPreferencesStore {
    private static let key = "notifications.preferences"
    private let defaults: UserDefaults

    var preferences: NotificationPreferences {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(NotificationPreferences.self, from: data) {
            preferences = stored
        } else {
            preferences = NotificationPreferences()
        }
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(preferences), forKey: Self.key)
    }
}

/// Schedules the planner's output as local notifications, replacing the previous plan.
@MainActor
@Observable
final class NotificationScheduler {
    private static let prefix = "discipline."
    private let center = UNUserNotificationCenter.current()
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Asks once, in context (after the first habit is created), never at launch.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorization()
        guard authorization == .notDetermined else { return authorization == .authorized || authorization == .provisional }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    func reschedule(_ planned: [PlannedNotification]) async {
        await refreshAuthorization()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard authorization == .authorized || authorization == .provisional else { return }

        let calendar = Calendar.current
        for note in planned {
            let content = UNMutableNotificationContent()
            content.title = note.title
            content.body = note.body
            content.sound = note.kind == .accountabilityDeadline ? .default : nil
            content.threadIdentifier = note.kind.rawValue
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: note.fireDate)
            let request = UNNotificationRequest(
                identifier: Self.prefix + note.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            do {
                try await center.add(request)
            } catch {
                Log.data.error("Couldn't schedule notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
    }
}
