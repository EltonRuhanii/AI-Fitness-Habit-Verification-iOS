import Foundation

public struct StreakDay: Hashable, Sendable {
    public let resolution: DayResolution
    public let streakBefore: Int
    public let streakAfter: Int
}

public struct StreakSummary: Hashable, Sendable {
    public let current: Int
    public let longest: Int
    /// Oldest first; one entry per day in the evaluated range.
    public let days: [StreakDay]

    public static let empty = StreakSummary(current: 0, longest: 0, days: [])

    public var today: StreakDay? { days.last }

    /// Motivational milestones only. They never feed back into research measures.
    public static let milestones = [3, 7, 14, 30, 60, 75, 100]

    public var nextMilestone: Int? { Self.milestones.first { $0 > current } }
    public var reachedMilestones: [Int] { Self.milestones.filter { $0 <= longest } }
}

/// Folds day outcomes into streaks.
///
/// - successful: +1
/// - failed: reset to 0 (`breakStreak`) or hold (`pauseStreak`)
/// - restDay / pending: neutral. A pending day never breaks a streak; once it resolves the
///   streak is recomputed from the stored data.
public enum StreakCalculator {
    public static func compute(_ resolutions: [DayResolution], missedDayBehavior: MissedDayBehavior = .breakStreak) -> StreakSummary {
        var current = 0
        var longest = 0
        var days: [StreakDay] = []
        for resolution in resolutions.sorted(by: { $0.day < $1.day }) {
            let before = current
            switch resolution.outcome {
            case .successful:
                current += 1
            case .failed:
                if missedDayBehavior == .breakStreak { current = 0 }
            case .pending, .restDay:
                break
            }
            longest = max(longest, current)
            days.append(StreakDay(resolution: resolution, streakBefore: before, streakAfter: current))
        }
        return StreakSummary(current: current, longest: longest, days: days)
    }

    /// Resolves every day from the first habit's start (bounded by `from`) through `today`.
    public static func summarize(
        habits: [Habit],
        completions: [HabitCompletion],
        tasks: [AccountabilityTask],
        rules: ChallengeRules = ChallengeRules(),
        from earliest: DayKey,
        today: DayKey,
        now: Date = Date(),
        calendar: Calendar
    ) -> StreakSummary {
        guard let firstStart = habits.map(\.startDate).min() else { return .empty }
        var day = max(firstStart, earliest)
        var resolutions: [DayResolution] = []
        while day <= today {
            resolutions.append(DayResolver.resolve(day: day, habits: habits, completions: completions, tasks: tasks,
                                                   rules: rules, today: today, now: now, calendar: calendar))
            day = day.adding(days: 1, calendar: calendar)
        }
        return compute(resolutions, missedDayBehavior: rules.missedDayBehavior)
    }
}
