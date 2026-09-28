import Foundation

public enum HabitCategory: String, Codable, CaseIterable, Sendable {
    case fitness, gym, running, nutrition, reading, recovery, discipline, custom

    public var displayName: String {
        switch self {
        case .fitness: return "Fitness"
        case .gym: return "Gym"
        case .running: return "Running"
        case .nutrition: return "Nutrition"
        case .reading: return "Reading"
        case .recovery: return "Recovery"
        case .discipline: return "Discipline"
        case .custom: return "Custom"
        }
    }

    /// SF Symbol name. Kept in the core package so every surface uses the same icon.
    public var symbolName: String {
        switch self {
        case .fitness: return "figure.strengthtraining.functional"
        case .gym: return "dumbbell.fill"
        case .running: return "figure.run"
        case .nutrition: return "fork.knife"
        case .reading: return "book.fill"
        case .recovery: return "snowflake"
        case .discipline: return "flame.fill"
        case .custom: return "star.fill"
        }
    }
}

public enum HabitFrequency: String, Codable, CaseIterable, Sendable {
    /// Target must be met every day.
    case daily
    /// Target must be met within each Monday–Sunday week.
    case weekly
    /// Target must be met on specific weekdays (see `Habit.scheduledWeekdays`).
    case custom
}

/// What a habit's `targetCount` counts.
public enum HabitUnit: String, Codable, CaseIterable, Sendable {
    /// Discrete occurrences, e.g. 4 gym sessions.
    case sessions
    /// Pages read.
    case pages
    /// Minutes of activity.
    case minutes

    public var displayName: String {
        switch self {
        case .sessions: return "sessions"
        case .pages: return "pages"
        case .minutes: return "minutes"
        }
    }
}

/// How a completion of this habit is established.
public enum VerificationType: String, Codable, CaseIterable, Sendable {
    /// Self-report only.
    case manual
    /// A photo is submitted and assessed against the habit's visual criteria.
    case photoAI
}

public struct Habit: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var userId: String
    public var challengeId: String?
    public var name: String
    public var description: String
    public var category: HabitCategory
    public var frequency: HabitFrequency
    public var unit: HabitUnit
    /// Per day for `.daily`, per week for `.weekly`, per scheduled day for `.custom`.
    public var targetCount: Int
    /// Weekdays (1 = Sunday … 7 = Saturday) for `.custom` frequency.
    public var scheduledWeekdays: [Int]
    public var startDate: DayKey
    public var endDate: DayKey?
    public var requiresEvidence: Bool
    public var verificationType: VerificationType
    /// Required habits count towards daily success and streaks.
    public var isRequired: Bool
    /// Accountability task created when the participant skips this habit, if skipping is allowed.
    public var skipConsequence: AccountabilityTemplate?
    public var createdAt: Date
    public var isActive: Bool

    public init(
        id: String = UUID().uuidString,
        userId: String,
        challengeId: String? = nil,
        name: String,
        description: String = "",
        category: HabitCategory,
        frequency: HabitFrequency,
        unit: HabitUnit = .sessions,
        targetCount: Int,
        scheduledWeekdays: [Int] = [],
        startDate: DayKey,
        endDate: DayKey? = nil,
        requiresEvidence: Bool = false,
        verificationType: VerificationType = .manual,
        isRequired: Bool = true,
        skipConsequence: AccountabilityTemplate? = nil,
        createdAt: Date = Date(),
        isActive: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.challengeId = challengeId
        self.name = name
        self.description = description
        self.category = category
        self.frequency = frequency
        self.unit = unit
        self.targetCount = max(1, targetCount)
        self.scheduledWeekdays = scheduledWeekdays
        self.startDate = startDate
        self.endDate = endDate
        self.requiresEvidence = requiresEvidence
        self.verificationType = verificationType
        self.isRequired = isRequired
        self.skipConsequence = skipConsequence
        self.createdAt = createdAt
        self.isActive = isActive
    }

    /// Whether the habit is in effect on the given day (active and within its date range).
    public func isInEffect(on day: DayKey) -> Bool {
        guard isActive, day >= startDate else { return false }
        if let endDate, day > endDate { return false }
        return true
    }

    /// Human-readable target, e.g. "4x / week" or "100 pages / week".
    public var targetDescription: String {
        let amount = unit == .sessions ? "\(targetCount)x" : "\(targetCount) \(unit.displayName)"
        switch frequency {
        case .daily: return "\(amount) / day"
        case .weekly: return "\(amount) / week"
        case .custom: return "\(amount) on \(scheduledWeekdays.count) days / week"
        }
    }
}
