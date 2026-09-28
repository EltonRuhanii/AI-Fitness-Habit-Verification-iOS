import Foundation

public enum MissedDayBehavior: String, Codable, CaseIterable, Sendable {
    /// A failed day resets the current streak to zero.
    case breakStreak
    /// A failed day is recorded but the streak is held (not incremented, not reset).
    case pauseStreak
}

/// How an `uncertain` AI verification counts towards resolving a day.
/// This is a research-relevant choice, so it is explicit and stored with the challenge.
public enum UncertainVerificationPolicy: String, Codable, CaseIterable, Sendable {
    /// Benefit of the doubt: uncertain evidence resolves the commitment.
    case countsAsResolved
    /// Uncertain evidence does not resolve the commitment; the participant must resubmit or skip.
    case requiresResubmission
}

public struct ChallengeRules: Codable, Hashable, Sendable {
    public var streakEnabled: Bool
    /// If `true`, every required habit must be resolved for a day to succeed.
    public var requireAllHabits: Bool
    public var allowSkipping: Bool
    /// Applied when a habit has no specific `skipConsequence` of its own.
    public var defaultSkipConsequence: AccountabilityTemplate?
    public var aiVerificationEnabled: Bool
    public var exerciseVerificationEnabled: Bool
    public var missedDayBehavior: MissedDayBehavior
    public var uncertainPolicy: UncertainVerificationPolicy
    /// Minimum model confidence for a verified/rejected decision; below it the result is `uncertain`.
    public var confidenceThreshold: Double

    public init(
        streakEnabled: Bool = true,
        requireAllHabits: Bool = true,
        allowSkipping: Bool = true,
        defaultSkipConsequence: AccountabilityTemplate? = AccountabilityTemplate(type: .pushUps, target: 50),
        aiVerificationEnabled: Bool = true,
        exerciseVerificationEnabled: Bool = true,
        missedDayBehavior: MissedDayBehavior = .breakStreak,
        uncertainPolicy: UncertainVerificationPolicy = .countsAsResolved,
        confidenceThreshold: Double = 0.7
    ) {
        self.streakEnabled = streakEnabled
        self.requireAllHabits = requireAllHabits
        self.allowSkipping = allowSkipping
        self.defaultSkipConsequence = defaultSkipConsequence
        self.aiVerificationEnabled = aiVerificationEnabled
        self.exerciseVerificationEnabled = exerciseVerificationEnabled
        self.missedDayBehavior = missedDayBehavior
        self.uncertainPolicy = uncertainPolicy
        self.confidenceThreshold = min(max(confidenceThreshold, 0.5), 0.99)
    }
}

public enum ChallengeStatus: String, Codable, CaseIterable, Sendable {
    case draft, active, completed, abandoned
}

public struct Challenge: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var ownerId: String
    public var name: String
    public var description: String
    public var durationDays: Int
    public var startDate: DayKey
    public var endDate: DayKey
    public var rules: ChallengeRules
    public var status: ChallengeStatus
    public var createdAt: Date
    /// When the participant explicitly accepted the rules (required before starting).
    public var rulesAcceptedAt: Date?
    /// Template the challenge was created from (e.g. `75-day-discipline`), if any.
    public var templateId: String?

    public init(
        id: String = UUID().uuidString,
        ownerId: String,
        name: String,
        description: String,
        durationDays: Int,
        startDate: DayKey,
        rules: ChallengeRules,
        status: ChallengeStatus = .active,
        createdAt: Date = Date(),
        rulesAcceptedAt: Date? = nil,
        templateId: String? = nil,
        calendar: Calendar = .disciplineCalendar()
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.description = description
        self.durationDays = max(1, durationDays)
        self.startDate = startDate
        self.endDate = startDate.adding(days: max(1, durationDays) - 1, calendar: calendar)
        self.rules = rules
        self.status = status
        self.createdAt = createdAt
        self.rulesAcceptedAt = rulesAcceptedAt
        self.templateId = templateId
    }

    /// 1-based day number within the challenge, or `nil` outside its range.
    public func dayNumber(of day: DayKey, calendar: Calendar = .disciplineCalendar()) -> Int? {
        guard day >= startDate, day <= endDate else { return nil }
        return startDate.days(to: day, calendar: calendar) + 1
    }
}
