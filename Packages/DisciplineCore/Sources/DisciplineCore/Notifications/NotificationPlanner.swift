import Foundation

public struct NotificationPreferences: Codable, Equatable, Sendable {
    public var enabled = true
    public var dailyReminder = true
    public var reminderHour = 18
    public var reminderMinute = 0
    public var accountabilityDeadlines = true
    public var streakWarning = true
    public var weeklySummary = true
    /// Quiet hours: nothing is delivered from `quietStartHour` until `quietEndHour`.
    public var quietStartHour = 22
    public var quietEndHour = 8

    public init() {}
}

public struct PlannedNotification: Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case accountabilityDeadline
        case streakWarning
        case dailyReminder
        case weeklySummary

        /// Lower value = kept first when the daily cap applies.
        var priority: Int {
            switch self {
            case .accountabilityDeadline: return 0
            case .streakWarning: return 1
            case .dailyReminder: return 2
            case .weeklySummary: return 3
            }
        }
    }

    public let id: String
    public let kind: Kind
    public let fireDate: Date
    public let title: String
    public let body: String
}

/// Decides which local notifications to schedule. Pure: the app reschedules the whole plan
/// whenever data changes, so notifications always reflect the current state.
///
/// Deliberately restrained: only when something is actually open, never during quiet hours,
/// and at most `maxPerDay` per day.
public enum NotificationPlanner {
    public static let maxPerDay = 3
    public static let reminderDaysAhead = 6
    static let streakWarningHour = 21
    static let weeklySummaryHour = 19
    static let accountabilityLeadTime: TimeInterval = 2 * 3600

    public static func plan(
        now: Date,
        calendar: Calendar,
        preferences: NotificationPreferences,
        today: DayKey,
        commitments: [TodayCommitment],
        openTasks: [AccountabilityTask],
        streak: StreakSummary,
        streakEnabled: Bool = true
    ) -> [PlannedNotification] {
        guard preferences.enabled else { return [] }
        var planned: [PlannedNotification] = []

        func at(_ day: DayKey, hour: Int, minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day.startDate(calendar: calendar)) ?? day.startDate(calendar: calendar)
        }

        let outstanding = commitments.filter { $0.habit.isRequired && $0.isOutstanding }

        // Evening reminder: today with specifics; following days a generic check-in.
        if preferences.dailyReminder {
            let todayFire = at(today, hour: preferences.reminderHour, minute: preferences.reminderMinute)
            if todayFire > now, !outstanding.isEmpty {
                planned.append(PlannedNotification(
                    id: "reminder.\(today)", kind: .dailyReminder, fireDate: todayFire,
                    title: "\(outstanding.count) commitment\(outstanding.count == 1 ? "" : "s") left today",
                    body: reminderBody(outstanding)
                ))
            }
            for offset in 1...reminderDaysAhead {
                let day = today.adding(days: offset, calendar: calendar)
                planned.append(PlannedNotification(
                    id: "reminder.\(day)", kind: .dailyReminder,
                    fireDate: at(day, hour: preferences.reminderHour, minute: preferences.reminderMinute),
                    title: "Check in on today's commitments",
                    body: "See what's still open and keep your streak going."
                ))
            }
        }

        // Accountability deadlines, two hours before expiry.
        if preferences.accountabilityDeadlines {
            for task in openTasks where task.deadline > now {
                let fire = max(task.deadline.addingTimeInterval(-accountabilityLeadTime), now.addingTimeInterval(60))
                guard fire < task.deadline else { continue }
                planned.append(PlannedNotification(
                    id: "accountability.\(task.id)", kind: .accountabilityDeadline, fireDate: fire,
                    title: "Your accountability task is still incomplete",
                    body: "\(task.title) is due at \(task.deadline.formatted(date: .omitted, time: .shortened))."
                ))
            }
        }

        // Streak warning when a meaningful streak depends on today.
        if preferences.streakWarning, streakEnabled, streak.current >= 3,
           streak.today?.resolution.outcome == .pending, !outstanding.isEmpty {
            let fire = at(today, hour: streakWarningHour)
            if fire > now {
                planned.append(PlannedNotification(
                    id: "streak.\(today)", kind: .streakWarning, fireDate: fire,
                    title: "Your \(streak.current)-day streak is on the line",
                    body: "Resolve today's commitments to keep it going."
                ))
            }
        }

        // Weekly summary on Sunday evening (weekday 1 = Sunday).
        if preferences.weeklySummary {
            let weekStart = today.startOfWeek(calendar: calendar)
            let sunday = weekStart.adding(days: 6, calendar: calendar)
            let fire = at(sunday, hour: weeklySummaryHour)
            if fire > now {
                let week = streak.days.filter { $0.resolution.day >= weekStart && $0.resolution.day <= sunday }
                let successful = week.filter { $0.resolution.outcome == .successful }.count
                let decided = week.filter { $0.resolution.outcome == .successful || $0.resolution.outcome == .failed }.count
                planned.append(PlannedNotification(
                    id: "weekly.\(sunday)", kind: .weeklySummary, fireDate: fire,
                    title: "Your week in Discipline",
                    body: decided > 0
                        ? "\(successful) of \(decided) days successful so far this week. Open the app for the full picture."
                        : "See how your week went and what's next."
                ))
            }
        }

        return applyLimits(planned, preferences: preferences, calendar: calendar)
    }

    private static func reminderBody(_ outstanding: [TodayCommitment]) -> String {
        if let tight = outstanding.first(where: { $0.habit.frequency == .weekly && $0.habit.unit == .sessions && $0.progress.remaining > 0 }) {
            let remaining = tight.progress.remaining
            return "You have \(remaining == 1 ? "one" : "\(remaining)") remaining \(tight.habit.name.lowercased()) session\(remaining == 1 ? "" : "s") this week."
        }
        let names = outstanding.prefix(3).map(\.habit.name).joined(separator: ", ")
        return outstanding.count > 3 ? "\(names) and more are still open." : "Still open: \(names)."
    }

    /// Moves or drops notifications in quiet hours and caps each day at `maxPerDay`.
    static func applyLimits(_ notifications: [PlannedNotification], preferences: NotificationPreferences,
                            calendar: Calendar) -> [PlannedNotification] {
        let adjusted: [PlannedNotification] = notifications.compactMap { note in
            let hour = calendar.component(.hour, from: note.fireDate)
            guard isQuiet(hour: hour, preferences: preferences) else { return note }
            // Deadlines matter: move them before quiet hours begin (if still ahead of the original time).
            guard note.kind == .accountabilityDeadline,
                  let earlier = calendar.date(bySettingHour: max(0, preferences.quietStartHour - 1), minute: 0, second: 0, of: note.fireDate),
                  earlier < note.fireDate, !isQuiet(hour: calendar.component(.hour, from: earlier), preferences: preferences)
            else { return nil }
            return PlannedNotification(id: note.id, kind: note.kind, fireDate: earlier, title: note.title, body: note.body)
        }
        let byDay = Dictionary(grouping: adjusted) { DayKey($0.fireDate, calendar: calendar) }
        return byDay.values
            .flatMap { day in day.sorted { ($0.kind.priority, $0.fireDate) < ($1.kind.priority, $1.fireDate) }.prefix(maxPerDay) }
            .sorted { $0.fireDate < $1.fireDate }
    }

    static func isQuiet(hour: Int, preferences: NotificationPreferences) -> Bool {
        let start = preferences.quietStartHour, end = preferences.quietEndHour
        return start > end ? (hour >= start || hour < end) : (hour >= start && hour < end)
    }
}
