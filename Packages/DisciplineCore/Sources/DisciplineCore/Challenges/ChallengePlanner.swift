import Foundation

public enum ChallengePlanError: Error, Equatable, Sendable {
    case emptyName
    case invalidDuration
    case rulesNotAccepted
    case noHabits
    case alreadyActive
    case startInPast
}

/// Everything needed to start a challenge: the challenge and the habits it creates or adopts.
public struct ChallengePlan: Equatable, Sendable {
    public let challenge: Challenge
    /// New habits to create (templates) plus existing habits updated to belong to the challenge.
    public let habits: [Habit]
}

public struct ChallengeProgress: Equatable, Sendable {
    public let dayNumber: Int
    public let durationDays: Int
    public let successfulDays: Int
    public let failedDays: Int
    public let pendingDays: Int

    public var daysRemaining: Int { max(0, durationDays - dayNumber) }
    public var fractionElapsed: Double { Double(min(dayNumber, durationDays)) / Double(max(durationDays, 1)) }
    /// Successful share of decided days (pending and rest days excluded). `nil` before any decided day.
    public var adherence: Double? {
        let decided = successfulDays + failedDays
        return decided > 0 ? Double(successfulDays) / Double(decided) : nil
    }
}

public enum ChallengePlanner {
    public static let durationRange = 7...365

    /// The challenge currently governing the participant, if any.
    public static func activeChallenge(in challenges: [Challenge], today: DayKey) -> Challenge? {
        challenges
            .filter { $0.status == .active && $0.startDate <= today && today <= $0.endDate }
            .max { $0.createdAt < $1.createdAt }
    }

    /// Active challenge that starts in the future (e.g. "starts tomorrow").
    public static func upcomingChallenge(in challenges: [Challenge], today: DayKey) -> Challenge? {
        challenges.filter { $0.status == .active && $0.startDate > today }.min { $0.startDate < $1.startDate }
    }

    /// Active challenges whose last day has passed and should be marked completed.
    public static func finishedChallenges(in challenges: [Challenge], today: DayKey) -> [Challenge] {
        challenges.filter { $0.status == .active && today > $0.endDate }
    }

    /// Builds a challenge after the participant has explicitly accepted its rules.
    ///
    /// - Parameters:
    ///   - newHabits: habits to create for this challenge (e.g. from a template).
    ///   - adoptedHabits: existing habits that become part of the challenge.
    public static func plan(
        name: String,
        description: String,
        durationDays: Int,
        startDate: DayKey,
        rules: ChallengeRules,
        ownerId: String,
        newHabits: [Habit],
        adoptedHabits: [Habit],
        existingChallenges: [Challenge],
        rulesAccepted: Bool,
        today: DayKey,
        templateId: String? = nil,
        now: Date = Date(),
        id: String = UUID().uuidString,
        calendar: Calendar
    ) throws -> ChallengePlan {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChallengePlanError.emptyName }
        guard durationRange.contains(durationDays) else { throw ChallengePlanError.invalidDuration }
        guard rulesAccepted else { throw ChallengePlanError.rulesNotAccepted }
        guard !(newHabits.isEmpty && adoptedHabits.isEmpty) else { throw ChallengePlanError.noHabits }
        guard startDate >= today else { throw ChallengePlanError.startInPast }
        guard activeChallenge(in: existingChallenges, today: today) == nil,
              upcomingChallenge(in: existingChallenges, today: today) == nil else {
            throw ChallengePlanError.alreadyActive
        }

        let challenge = Challenge(
            id: id, ownerId: ownerId, name: trimmed, description: description, durationDays: durationDays,
            startDate: startDate, rules: rules, status: .active, createdAt: now,
            rulesAcceptedAt: now, templateId: templateId, calendar: calendar
        )
        let created = newHabits.map { habit -> Habit in
            var habit = habit
            habit.challengeId = challenge.id
            habit.userId = ownerId
            habit.startDate = startDate
            habit.endDate = challenge.endDate
            return habit
        }
        let adopted = adoptedHabits.map { habit -> Habit in
            var habit = habit
            habit.challengeId = challenge.id
            return habit
        }
        return ChallengePlan(challenge: challenge, habits: created + adopted)
    }

    /// Progress through a challenge from the day outcomes (from `StreakCalculator`).
    public static func progress(of challenge: Challenge, days: [StreakDay], today: DayKey, calendar: Calendar) -> ChallengeProgress {
        let inRange = days.filter { $0.resolution.day >= challenge.startDate && $0.resolution.day <= challenge.endDate }
        func count(_ outcome: DayOutcome) -> Int { inRange.filter { $0.resolution.outcome == outcome }.count }
        let dayNumber = challenge.dayNumber(of: min(today, challenge.endDate), calendar: calendar) ?? 0
        return ChallengeProgress(
            dayNumber: today < challenge.startDate ? 0 : dayNumber,
            durationDays: challenge.durationDays,
            successfulDays: count(.successful),
            failedDays: count(.failed),
            pendingDays: count(.pending)
        )
    }
}

public enum ChallengeTemplates {
    public static let discipline75Id = "75-day-discipline"

    /// The study's reference challenge: the example commitments from the study design plus a
    /// daily progress photo.
    public static func discipline75Habits(userId: String, startDate: DayKey) -> [Habit] {
        HabitTemplates.disciplineStarter(userId: userId, startDate: startDate) + [
            Habit(userId: userId, name: "Progress Photo", description: "A daily photo of your training progress.",
                  category: .fitness, frequency: .daily, unit: .sessions, targetCount: 1, startDate: startDate,
                  requiresEvidence: true, verificationType: .photoAI,
                  skipConsequence: AccountabilityTemplate(type: .pushUps, target: 20))
        ]
    }

    public static let discipline75Description = "75 days. Gym 4× a week, running 2× a week, 100 pages of reading a week, cold plunge 3× a week and a daily progress photo."
}
