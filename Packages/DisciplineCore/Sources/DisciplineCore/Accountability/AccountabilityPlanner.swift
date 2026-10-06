import Foundation

public enum SkipPlanError: Error, Equatable, Sendable {
    case notScheduled
    /// Skipping is disabled by the challenge rules.
    case skippingNotAllowed
    /// Weekly amount targets (e.g. 100 pages a week) can't be skipped: they can be caught up any day.
    case notSkippable
    /// Today's slot is already used by a completion, submission or earlier skip.
    case alreadyResolvedToday
}

/// A skip the participant has explicitly accepted: the skipped occurrence plus its task.
public struct SkipPlan: Equatable, Sendable {
    public let completion: HabitCompletion
    public let task: AccountabilityTask
}

/// Accountability rules: what skipping costs, and when a task counts as done or expired.
///
/// The participant defines commitments and agrees to their consequences in advance. A skip
/// replaces one occurrence of a habit with a pre-agreed, safety-capped exercise task. When the
/// task is completed the occurrence becomes `resolved`; if it expires, `failed`.
public enum AccountabilityPlanner {
    /// Consequence types that can currently be verified. Push-ups are the first exercise
    /// with a camera repetition engine; others will be added as engines are implemented.
    public static let supportedTypes: Set<AccountabilityTaskType> = [.pushUps]

    public static let fallbackConsequence = AccountabilityTemplate(type: .pushUps, target: 50)

    /// The consequence for skipping `habit`, or `nil` if skipping isn't allowed. Sessions and
    /// daily/set-day amounts (e.g. 60 minutes of guitar) can be skipped; weekly amounts can't.
    public static func consequence(for habit: Habit, rules: ChallengeRules = ChallengeRules()) -> AccountabilityTemplate? {
        guard rules.allowSkipping, habit.unit == .sessions || habit.frequency != .weekly else { return nil }
        let template = habit.skipConsequence ?? rules.defaultSkipConsequence ?? fallbackConsequence
        return supportedTypes.contains(template.type) ? template : fallbackConsequence
    }

    public static func canSkip(_ habit: Habit, on day: DayKey, completions: [HabitCompletion],
                               rules: ChallengeRules = ChallengeRules(), calendar: Calendar) -> Bool {
        (try? validateSkip(habit, on: day, completions: completions, rules: rules, calendar: calendar)) != nil
    }

    private static func validateSkip(_ habit: Habit, on day: DayKey, completions: [HabitCompletion],
                                     rules: ChallengeRules, calendar: Calendar) throws -> AccountabilityTemplate {
        guard HabitSchedule.isScheduled(habit, on: day, calendar: calendar) else { throw SkipPlanError.notScheduled }
        guard rules.allowSkipping else { throw SkipPlanError.skippingNotAllowed }
        guard let template = consequence(for: habit, rules: rules) else { throw SkipPlanError.notSkippable }
        let active = CompletionPlanner.activeCompletions(for: habit, on: day, in: completions)
        if habit.unit == .sessions {
            guard active.count < CompletionPlanner.maxSessionsPerDay(for: habit) else { throw SkipPlanError.alreadyResolvedToday }
        } else {
            // An amount habit can be skipped once per day, for whatever isn't logged yet.
            guard !active.contains(where: { $0.method == .accountabilityExercise }),
                  remainingAmount(habit, on: day, completions: completions) > 0 else {
                throw SkipPlanError.alreadyResolvedToday
            }
        }
        return template
    }

    /// Amount still open today for an amount habit (logged or submitted entries count).
    public static func remainingAmount(_ habit: Habit, on day: DayKey, completions: [HabitCompletion]) -> Int {
        let logged = CompletionPlanner.activeCompletions(for: habit, on: day, in: completions).reduce(0) { $0 + $1.quantity }
        return max(0, habit.targetCount - logged)
    }

    /// Builds the skip. Call only after the participant has explicitly accepted the consequence;
    /// `acceptedAt` is recorded as that moment and starts the deadline.
    public static func planSkip(
        habit: Habit,
        day: DayKey,
        condition: TrackingCondition,
        existing: [HabitCompletion],
        rules: ChallengeRules = ChallengeRules(),
        calendar: Calendar,
        acceptedAt: Date = Date(),
        taskId: String = UUID().uuidString
    ) throws -> SkipPlan {
        let template = try validateSkip(habit, on: day, completions: existing, rules: rules, calendar: calendar)
        let index = existing.filter { $0.habitId == habit.id && $0.day == day }.count
        let completionId = habit.unit == .sessions ? "\(habit.id)_\(day)_\(index)" : "\(habit.id)_\(day)_skip"
        // A skip stands in for one session, or for the rest of today's amount.
        let quantity = habit.unit == .sessions ? 1 : remainingAmount(habit, on: day, completions: existing)
        let deadline = acceptedAt.addingTimeInterval(TimeInterval(template.deadlineHours) * 3600)

        let task = AccountabilityTask(
            id: taskId,
            userId: habit.userId,
            sourceHabitId: habit.id,
            sourceCompletionId: completionId,
            day: day,
            title: template.title,
            description: "Accountability for skipping \(habit.name) on \(day).",
            type: template.type,
            target: template.target,
            status: .pending,
            createdAt: acceptedAt,
            acceptedAt: acceptedAt,
            deadline: deadline
        )
        let completion = HabitCompletion(
            id: completionId,
            userId: habit.userId,
            habitId: habit.id,
            challengeId: habit.challengeId,
            day: day,
            quantity: quantity,
            status: .accountabilityRequired,
            method: .accountabilityExercise,
            trackingCondition: condition,
            accountabilityTaskId: taskId,
            createdAt: acceptedAt,
            updatedAt: acceptedAt
        )
        return SkipPlan(completion: completion, task: task)
    }
}

/// Deterministic task lifecycle, shared by the demo backend and mirrored by the server.
public enum AccountabilityLifecycle {
    /// Status as of `now`: open tasks past their deadline are expired even before the
    /// server has written it, so the UI never shows an overdue task as still doable.
    public static func effectiveStatus(of task: AccountabilityTask, now: Date) -> AccountabilityTaskStatus {
        if task.status.isOpen && now > task.deadline { return .expired }
        return task.status
    }

    /// Valid repetitions from sessions of this task that finished before the deadline.
    public static func validRepetitions(for task: AccountabilityTask, sessions: [ExerciseSession]) -> Int {
        sessions
            .filter { $0.accountabilityTaskId == task.id && ($0.completedAt ?? .distantFuture) <= task.deadline }
            .reduce(0) { $0 + $1.validReps }
    }

    /// Resolution after a session is recorded or time passes. Terminal states are final.
    public static func evaluate(_ task: AccountabilityTask, sessions: [ExerciseSession], now: Date) -> AccountabilityTaskStatus {
        guard task.status.isOpen else { return task.status }
        if validRepetitions(for: task, sessions: sessions) >= task.target { return .completed }
        if now > task.deadline { return .expired }
        return task.status
    }

    /// The completion status that follows from a task's status.
    public static func completionStatus(for taskStatus: AccountabilityTaskStatus) -> CompletionStatus {
        switch taskStatus {
        case .completed: return .resolved
        case .failed, .expired: return .failed
        case .pending, .inProgress: return .accountabilityRequired
        }
    }
}
