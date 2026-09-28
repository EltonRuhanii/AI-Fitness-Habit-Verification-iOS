import Foundation

/// How a participant completes a habit in their experimental condition.
public enum CompletionRequirement: Hashable, Sendable {
    /// Mark complete (self-report).
    case selfReport
    /// Submit photo evidence for automated verification.
    case evidence
}

public enum CompletionPlanError: Error, Equatable, Sendable {
    case notScheduled
    /// A session habit already has its full target logged for this day.
    case alreadyCompletedToday
    case invalidQuantity
    case evidenceRequired
    /// Evidence was submitted for a habit that is self-reported in this condition.
    case evidenceNotApplicable
}

/// Decides whether and how a completion may be logged. Mirrors the Firestore rules so
/// the UI never offers an action the backend would reject.
public enum CompletionPlanner {
    /// In the manual condition evidence is never requested. That's the definition of the
    /// control condition. In the AI-assisted condition, habits that require evidence must
    /// go through verification.
    public static func requirement(for habit: Habit, condition: TrackingCondition) -> CompletionRequirement {
        (condition == .aiAssisted && habit.requiresEvidence) ? .evidence : .selfReport
    }

    /// Maximum session completions per day: the daily target for daily/custom habits,
    /// one per day for weekly habits (a gym session is a day's event).
    public static func maxSessionsPerDay(for habit: Habit) -> Int {
        switch habit.frequency {
        case .daily, .custom: return habit.targetCount
        case .weekly: return 1
        }
    }

    /// Completions for this habit on `day` that still "occupy" a slot (anything not rejected/failed).
    public static func activeCompletions(for habit: Habit, on day: DayKey, in completions: [HabitCompletion]) -> [HabitCompletion] {
        completions.filter {
            $0.habitId == habit.id && $0.day == day && $0.status != .rejected && $0.status != .failed
        }
    }

    public static func canLogSession(for habit: Habit, on day: DayKey, completions: [HabitCompletion], calendar: Calendar) -> Bool {
        guard habit.unit == .sessions, HabitSchedule.isScheduled(habit, on: day, calendar: calendar) else { return false }
        return activeCompletions(for: habit, on: day, in: completions).count < maxSessionsPerDay(for: habit)
    }

    /// Builds a completion awaiting photo verification. Only valid when the participant's
    /// condition requires evidence for this habit; the manual condition never submits evidence.
    /// Uses the same slot rules as self-reports: a rejected attempt frees its slot for a retry.
    public static func makeEvidenceSubmission(
        habit: Habit,
        day: DayKey,
        evidenceId: String,
        quantity: Int = 1,
        condition: TrackingCondition,
        existing: [HabitCompletion],
        calendar: Calendar,
        now: Date = Date(),
        requestId: String = UUID().uuidString
    ) throws -> HabitCompletion {
        guard HabitSchedule.isScheduled(habit, on: day, calendar: calendar) else { throw CompletionPlanError.notScheduled }
        guard requirement(for: habit, condition: condition) == .evidence else { throw CompletionPlanError.evidenceNotApplicable }
        guard activeCompletions(for: habit, on: day, in: existing).count < maxSessionsPerDay(for: habit) else {
            throw CompletionPlanError.alreadyCompletedToday
        }
        if habit.unit != .sessions, !(1...10_000).contains(quantity) { throw CompletionPlanError.invalidQuantity }
        let index = existing.filter { $0.habitId == habit.id && $0.day == day }.count
        return HabitCompletion(
            id: "\(habit.id)_\(day)_\(index)",
            userId: habit.userId,
            habitId: habit.id,
            challengeId: habit.challengeId,
            day: day,
            quantity: habit.unit == .sessions ? 1 : quantity,
            status: .pendingVerification,
            method: .photoVerification,
            trackingCondition: condition,
            evidenceId: evidenceId,
            createdAt: now,
            updatedAt: now,
            clientRequestId: requestId
        )
    }

    /// Builds a self-reported completion, or throws if it isn't allowed.
    ///
    /// Session completions get a deterministic document ID (`habit_day_index`), so a retried
    /// or duplicated offline write lands on the same document instead of creating a second one.
    public static func makeSelfReport(
        habit: Habit,
        day: DayKey,
        quantity: Int,
        condition: TrackingCondition,
        existing: [HabitCompletion],
        calendar: Calendar,
        now: Date = Date(),
        requestId: String = UUID().uuidString
    ) throws -> HabitCompletion {
        guard HabitSchedule.isScheduled(habit, on: day, calendar: calendar) else { throw CompletionPlanError.notScheduled }
        guard requirement(for: habit, condition: condition) == .selfReport else { throw CompletionPlanError.evidenceRequired }

        let id: String
        let amount: Int
        if habit.unit == .sessions {
            guard canLogSession(for: habit, on: day, completions: existing, calendar: calendar) else {
                throw CompletionPlanError.alreadyCompletedToday
            }
            let index = existing.filter { $0.habitId == habit.id && $0.day == day }.count
            id = "\(habit.id)_\(day)_\(index)"
            amount = 1
        } else {
            guard quantity > 0, quantity <= 10_000 else { throw CompletionPlanError.invalidQuantity }
            id = requestId
            amount = quantity
        }

        return HabitCompletion(
            id: id,
            userId: habit.userId,
            habitId: habit.id,
            challengeId: habit.challengeId,
            day: day,
            quantity: amount,
            status: .selfReported,
            method: .selfReport,
            trackingCondition: condition,
            createdAt: now,
            updatedAt: now,
            clientRequestId: requestId
        )
    }
}
