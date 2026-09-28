import Foundation

/// A resolved day plus the context that produced it.
public struct ResolvedDay: Hashable, Sendable {
    public let resolution: DayResolution
    /// The challenge in effect that day, if any.
    public let challengeId: String?
    public let rules: ChallengeRules
}

/// The single definition of a participant's day history, used by both the app (streak) and
/// the research records (mirrored in `firebase/functions/src/research/resolver.ts`; both run
/// `Tests/DisciplineCoreTests/Fixtures/history-resolution-cases.json`).
///
/// Each day is resolved in the context of the challenge covering it (its habits and rules),
/// or, outside any challenge, all of the participant's habits under the default rules.
public enum HistoryResolver {
    /// The non-draft challenge whose date range contains `day` (latest created wins).
    public static func challenge(covering day: DayKey, in challenges: [Challenge]) -> Challenge? {
        challenges
            .filter { $0.status != .draft && $0.startDate <= day && day <= $0.endDate }
            .max { $0.createdAt < $1.createdAt }
    }

    public static func resolve(
        habits: [Habit],
        completions: [HabitCompletion],
        tasks: [AccountabilityTask],
        challenges: [Challenge],
        from earliest: DayKey,
        today: DayKey,
        now: Date = Date(),
        calendar: Calendar
    ) -> [ResolvedDay] {
        guard let firstStart = habits.map(\.startDate).min() else { return [] }
        var day = max(firstStart, earliest)
        var result: [ResolvedDay] = []
        while day <= today {
            let challenge = challenge(covering: day, in: challenges)
            let scoped = challenge.map { current in habits.filter { $0.challengeId == current.id } } ?? habits
            let rules = challenge?.rules ?? ChallengeRules()
            let resolution = DayResolver.resolve(day: day, habits: scoped, completions: completions, tasks: tasks,
                                                 rules: rules, today: today, now: now, calendar: calendar)
            result.append(ResolvedDay(resolution: resolution, challengeId: challenge?.id, rules: rules))
            day = day.adding(days: 1, calendar: calendar)
        }
        return result
    }
}

public extension StreakCalculator {
    /// Streaks over resolved history; each day's own challenge rules decide whether a failure
    /// breaks or pauses the streak.
    static func compute(_ days: [ResolvedDay]) -> StreakSummary {
        var current = 0
        var longest = 0
        var output: [StreakDay] = []
        for day in days.sorted(by: { $0.resolution.day < $1.resolution.day }) {
            let before = current
            switch day.resolution.outcome {
            case .successful: current += 1
            case .failed: if day.rules.missedDayBehavior == .breakStreak { current = 0 }
            case .pending, .restDay: break
            }
            longest = max(longest, current)
            output.append(StreakDay(resolution: day.resolution, streakBefore: before, streakAfter: current, challengeId: day.challengeId))
        }
        return StreakSummary(current: current, longest: longest, days: output)
    }

    static func summarizeHistory(
        habits: [Habit],
        completions: [HabitCompletion],
        tasks: [AccountabilityTask],
        challenges: [Challenge],
        from earliest: DayKey,
        today: DayKey,
        now: Date = Date(),
        calendar: Calendar
    ) -> StreakSummary {
        compute(HistoryResolver.resolve(habits: habits, completions: completions, tasks: tasks, challenges: challenges,
                                        from: earliest, today: today, now: now, calendar: calendar))
    }
}
