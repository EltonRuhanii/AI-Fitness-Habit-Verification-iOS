import Foundation

public struct WeekBucket: Hashable, Sendable, Identifiable {
    public let weekStart: DayKey
    public let successful: Int
    public let failed: Int
    public var id: DayKey { weekStart }
}

public struct HabitAdherence: Hashable, Sendable, Identifiable {
    public let habitId: String
    public let met: Int
    public let total: Int
    public var id: String { habitId }
    public var rate: Double? { total > 0 ? Double(met) / Double(total) : nil }
}

/// Participant-facing progress over a period: the same numbers the research records contain,
/// computed from the same resolved history.
public struct ProgressSummary: Equatable, Sendable {
    public var successfulDays = 0
    public var failedDays = 0
    public var pendingDays = 0
    public var selfReported = 0
    public var verified = 0
    public var rejected = 0
    public var uncertain = 0
    public var skipped = 0
    public var accountabilityCompleted = 0
    public var accountabilityFailed = 0
    public var accountabilityOpen = 0
    public var habits: [HabitAdherence] = []
    public var weeks: [WeekBucket] = []

    public var daySuccessRate: Double? {
        let decided = successfulDays + failedDays
        return decided > 0 ? Double(successfulDays) / Double(decided) : nil
    }
    /// Verified share of decided AI verifications.
    public var verificationRate: Double? {
        let decided = verified + rejected + uncertain
        return decided > 0 ? Double(verified) / Double(decided) : nil
    }
    public var totalCompleted: Int { selfReported + verified }
}

public enum ProgressCalculator {
    public static func summary(
        days: [StreakDay],
        habits: [Habit],
        completions: [HabitCompletion],
        tasks: [AccountabilityTask],
        from: DayKey,
        through: DayKey,
        today: DayKey,
        weeksInChart: Int = 8,
        now: Date = Date(),
        calendar: Calendar
    ) -> ProgressSummary {
        var summary = ProgressSummary()
        for day in days where day.resolution.day >= from && day.resolution.day <= through {
            switch day.resolution.outcome {
            case .successful: summary.successfulDays += 1
            case .failed: summary.failedDays += 1
            case .pending: summary.pendingDays += 1
            case .restDay: break
            }
        }

        for completion in completions where completion.day >= from && completion.day <= through {
            switch completion.status {
            case .selfReported: summary.selfReported += 1
            case .verified: summary.verified += 1
            case .rejected: summary.rejected += 1
            case .uncertain: summary.uncertain += 1
            default: break
            }
            if completion.method == .accountabilityExercise { summary.skipped += 1 }
        }

        for task in tasks where task.day >= from && task.day <= through {
            switch AccountabilityLifecycle.effectiveStatus(of: task, now: now) {
            case .completed: summary.accountabilityCompleted += 1
            case .failed, .expired: summary.accountabilityFailed += 1
            case .pending, .inProgress: summary.accountabilityOpen += 1
            }
        }

        summary.habits = habits.filter(\.isRequired).compactMap { habit in
            let start = max(from, habit.startDate)
            let end = min(through, habit.endDate ?? through)
            guard start <= end else { return nil }
            let result = HabitSchedule.adherence(for: habit, from: start, through: end, today: today,
                                                 completions: completions, calendar: calendar)
            return HabitAdherence(habitId: habit.id, met: result.met, total: result.total)
        }

        let currentWeek = today.startOfWeek(calendar: calendar)
        summary.weeks = (0..<weeksInChart).reversed().map { offset in
            let weekStart = currentWeek.adding(days: -7 * offset, calendar: calendar)
            let weekEnd = weekStart.adding(days: 6, calendar: calendar)
            let inWeek = days.filter { $0.resolution.day >= weekStart && $0.resolution.day <= weekEnd }
            return WeekBucket(
                weekStart: weekStart,
                successful: inWeek.filter { $0.resolution.outcome == .successful }.count,
                failed: inWeek.filter { $0.resolution.outcome == .failed }.count
            )
        }
        return summary
    }
}
