import Foundation

/// A habit as it appears on today's dashboard.
public struct TodayCommitment: Hashable, Sendable, Identifiable {
    public enum State: Hashable, Sendable {
        /// Target for the current period is met.
        case done
        /// Evidence submitted, waiting for verification.
        case awaitingVerification
        /// Skipped today; the accepted accountability task isn't done yet.
        case accountabilityDue
        /// Some progress, target not met yet.
        case inProgress
        /// Nothing logged yet in the current period.
        case open
    }

    public var id: String { habit.id }
    public let habit: Habit
    public let progress: HabitProgress
    public let todayCompletions: [HabitCompletion]
    public let state: State
    public let requirement: CompletionRequirement

    public var isOutstanding: Bool { state == .open || state == .inProgress }
}

public enum TodayCommitments {
    /// Required habits first, then outstanding before done, then by name.
    public static func build(
        habits: [Habit],
        completions: [HabitCompletion],
        today: DayKey,
        condition: TrackingCondition,
        policy: CountingPolicy = CountingPolicy(),
        calendar: Calendar
    ) -> [TodayCommitment] {
        habits.compactMap { habit -> TodayCommitment? in
            guard let progress = HabitSchedule.progress(for: habit, on: today, completions: completions, policy: policy, calendar: calendar) else {
                return nil
            }
            let todays = completions.filter { $0.habitId == habit.id && $0.day == today }
            let isAwaiting = todays.contains { $0.status == .pendingVerification }
            let isAccountabilityDue = todays.contains { $0.status == .accountabilityRequired }
            let state: TodayCommitment.State
            if progress.isMet {
                state = .done
            } else if isAccountabilityDue {
                state = .accountabilityDue
            } else if isAwaiting {
                state = .awaitingVerification
            } else if progress.achieved > 0 {
                state = .inProgress
            } else {
                state = .open
            }
            return TodayCommitment(
                habit: habit,
                progress: progress,
                todayCompletions: todays.sorted { $0.createdAt < $1.createdAt },
                state: state,
                requirement: CompletionPlanner.requirement(for: habit, condition: condition)
            )
        }
        .sorted { lhs, rhs in
            if lhs.habit.isRequired != rhs.habit.isRequired { return lhs.habit.isRequired }
            let lhsDone = lhs.state == .done, rhsDone = rhs.state == .done
            if lhsDone != rhsDone { return !lhsDone }
            return lhs.habit.name.localizedCaseInsensitiveCompare(rhs.habit.name) == .orderedAscending
        }
    }
}

/// Starter habits matching the example commitments in the study design.
public enum HabitTemplates {
    public static func disciplineStarter(userId: String, startDate: DayKey) -> [Habit] {
        [
            Habit(userId: userId, name: "Gym", description: "Strength training session.", category: .gym,
                  frequency: .weekly, unit: .sessions, targetCount: 4, startDate: startDate,
                  requiresEvidence: true, verificationType: .photoAI,
                  skipConsequence: AccountabilityTemplate(type: .pushUps, target: 50)),
            Habit(userId: userId, name: "Running", description: "Outdoor or treadmill run.", category: .running,
                  frequency: .weekly, unit: .sessions, targetCount: 2, startDate: startDate,
                  requiresEvidence: true, verificationType: .photoAI,
                  skipConsequence: AccountabilityTemplate(type: .pushUps, target: 40)),
            Habit(userId: userId, name: "Reading", description: "Non-fiction or personal development.", category: .reading,
                  frequency: .weekly, unit: .pages, targetCount: 100, startDate: startDate,
                  requiresEvidence: false, verificationType: .manual),
            Habit(userId: userId, name: "Cold Plunge", description: "Cold water immersion.", category: .recovery,
                  frequency: .weekly, unit: .sessions, targetCount: 3, startDate: startDate,
                  requiresEvidence: true, verificationType: .photoAI,
                  skipConsequence: AccountabilityTemplate(type: .pushUps, target: 30))
        ]
    }
}
