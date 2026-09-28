import Foundation

/// How one due commitment stands on a given day.
public enum CommitmentResolution: String, Codable, Sendable {
    /// Done according to the rules (completed, verified, or skipped with accountability done).
    case resolved
    /// Not resolved yet, but still can be: the day isn't over, or verification or an
    /// accountability task is still open.
    case pending
    /// Not resolved and no longer can be.
    case unresolved
}

public struct DueCommitment: Hashable, Sendable {
    public let habitId: String
    public let resolution: CommitmentResolution
}

public struct DayResolution: Hashable, Sendable, Identifiable {
    public var id: DayKey { day }
    public let day: DayKey
    public let outcome: DayOutcome
    /// Required commitments that were due this day (empty on rest days / on-track days).
    public let due: [DueCommitment]
    /// Whether any required habit was in effect this day.
    public let hasCommitments: Bool
}

/// Decides whether a day was successful. Pure and deterministic; versioned for research data.
///
/// - Daily habits are due every day in effect; custom habits on their scheduled weekdays.
/// - **Weekly habits use a feasibility rule**: a weekly target becomes due on a day only when
///   postponing it would make the target unreachable (remaining need ≥ remaining days). Weekly
///   quantity targets (e.g. pages) are due on the last day of the week.
/// - A day with commitments in effect but none due is "on track" and counts as successful.
/// - The day's outcome: failed if any due commitment is unresolved; pending if any is pending;
///   otherwise successful. With `requireAllHabits == false`, one resolved commitment suffices.
public enum DayResolver {
    public static let version = "day-resolver-v1"

    public static func resolve(
        day: DayKey,
        habits: [Habit],
        completions: [HabitCompletion],
        tasks: [AccountabilityTask],
        rules: ChallengeRules = ChallengeRules(),
        today: DayKey,
        now: Date = Date(),
        calendar: Calendar
    ) -> DayResolution {
        let policy = CountingPolicy(rules: rules)
        let inEffect = habits.filter { $0.isRequired && isInEffectForHistory($0, on: day) }
        guard !inEffect.isEmpty else {
            return DayResolution(day: day, outcome: .restDay, due: [], hasCommitments: false)
        }

        let due: [DueCommitment] = inEffect.compactMap { habit in
            guard let needed = neededToday(habit, on: day, completions: completions, policy: policy, calendar: calendar) else {
                return nil
            }
            let todays = completions.filter { $0.habitId == habit.id && $0.day == day }
            let achieved = todays.filter { policy.counts($0.status) }.reduce(0) { $0 + $1.quantity }
            let resolution: CommitmentResolution
            if achieved >= needed {
                resolution = .resolved
            } else if isAwaitingOutcome(todays, tasks: tasks, now: now) || day >= today {
                resolution = .pending
            } else {
                resolution = .unresolved
            }
            return DueCommitment(habitId: habit.id, resolution: resolution)
        }

        let outcome: DayOutcome
        let unresolved = due.contains { $0.resolution == .unresolved }
        let pending = due.contains { $0.resolution == .pending }
        if rules.requireAllHabits || due.isEmpty {
            outcome = unresolved ? .failed : (pending ? .pending : .successful)
        } else if due.contains(where: { $0.resolution == .resolved }) {
            outcome = .successful
        } else {
            outcome = pending ? .pending : .failed
        }
        return DayResolution(day: day, outcome: outcome, due: due, hasCommitments: true)
    }

    // MARK: Due rules

    /// The amount that must be achieved *on this day*, or `nil` if the habit isn't due.
    static func neededToday(_ habit: Habit, on day: DayKey, completions: [HabitCompletion],
                            policy: CountingPolicy, calendar: Calendar) -> Int? {
        switch habit.frequency {
        case .daily:
            return habit.targetCount
        case .custom:
            return habit.scheduledWeekdays.contains(day.weekday(calendar: calendar)) ? habit.targetCount : nil
        case .weekly:
            let weekStart = day.startOfWeek(calendar: calendar)
            var weekEnd = weekStart.adding(days: 6, calendar: calendar)
            if let end = habit.endDate, end < weekEnd { weekEnd = end }
            let counted = completions.filter { $0.habitId == habit.id && policy.counts($0.status) }
            let achievedBefore = counted
                .filter { $0.day >= weekStart && $0.day < day }
                .reduce(0) { $0 + $1.quantity }
            let remainingNeed = habit.targetCount - achievedBefore
            guard remainingNeed > 0 else { return nil }

            if habit.unit != .sessions {
                // Amounts can be caught up any day, so they only fall due on the last day.
                return day == weekEnd ? remainingNeed : nil
            }
            let daysLeft = day.days(to: weekEnd, calendar: calendar) + 1
            guard remainingNeed >= daysLeft else { return nil }
            // One session per day for weekly habits: today's session is required.
            return 1
        }
    }

    /// Habit date range, independent of the current `isActive` flag so archived habits keep
    /// their history. Legacy archived habits without an end date are excluded.
    static func isInEffectForHistory(_ habit: Habit, on day: DayKey) -> Bool {
        guard day >= habit.startDate else { return false }
        if let end = habit.endDate { return day <= end }
        return habit.isActive
    }

    /// Evidence still being verified, or a skip whose accountability task is still open.
    private static func isAwaitingOutcome(_ completions: [HabitCompletion], tasks: [AccountabilityTask], now: Date) -> Bool {
        completions.contains { completion in
            switch completion.status {
            case .pendingVerification:
                return true
            case .accountabilityRequired:
                guard let taskId = completion.accountabilityTaskId,
                      let task = tasks.first(where: { $0.id == taskId }) else { return true }
                return AccountabilityLifecycle.effectiveStatus(of: task, now: now).isOpen
            default:
                return false
            }
        }
    }
}
