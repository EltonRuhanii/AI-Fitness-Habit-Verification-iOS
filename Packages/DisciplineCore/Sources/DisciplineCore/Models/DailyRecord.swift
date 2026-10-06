import Foundation

public enum DayOutcome: String, Codable, Sendable {
    /// All required commitments resolved according to the challenge rules.
    case successful
    /// At least one required commitment was not resolved.
    case failed
    /// The day is still in progress or awaiting verification/accountability.
    case pending
    /// No commitments were due on this day.
    case restDay
}

/// Research snapshot of one participant-day. Stored at `dailyRecords/{participantId}_{day}`.
///
/// Keyed by the pseudonymous `participantId`, not the auth uid, and contains only counts, so it
/// can be exported without further de-identification. Written by the server (participants
/// can't edit their own research record) and recomputed while the day is still pending.
///
/// Field definitions (all for this participant-local day, within the habits in scope: the
/// challenge's habits during a challenge, otherwise all habits):
/// - `requiredHabits`: required commitments due this day (see `DayResolver`).
/// - `completedHabits`: of those, how many were resolved.
/// - `selfReportedHabits` / `verifiedHabits` / `rejectedHabits` / `uncertainHabits`: completion
///   events by status, including habits not due that day.
/// - `skippedHabits`: skips (occurrences replaced by an accountability task).
/// - `accountabilityTasks*`: tasks for skips of this day, and how they ended.
/// - `verificationCount` / `verificationConfidenceSum`: decided AI verifications of this day's
///   evidence, for computing mean confidence without exposing individual results.
public struct DailyRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(participantId)_\(day)" }
    public var participantId: String
    public var challengeId: String?
    public var day: DayKey
    public var trackingCondition: TrackingCondition
    public var requiredHabits: Int
    public var completedHabits: Int
    public var skippedHabits: Int
    public var verifiedHabits: Int
    public var rejectedHabits: Int
    public var uncertainHabits: Int
    public var selfReportedHabits: Int
    public var accountabilityTasks: Int
    public var accountabilityTasksCompleted: Int
    public var accountabilityTasksFailed: Int
    public var verificationCount: Int
    public var verificationConfidenceSum: Double
    public var outcome: DayOutcome
    public var streakBefore: Int
    public var streakAfter: Int
    /// Version of the day-resolution algorithm that produced this record.
    public var resolverVersion: String

    public var daySuccessful: Bool { outcome == .successful }

    public init(
        participantId: String,
        challengeId: String?,
        day: DayKey,
        trackingCondition: TrackingCondition,
        requiredHabits: Int,
        completedHabits: Int,
        skippedHabits: Int,
        verifiedHabits: Int,
        rejectedHabits: Int,
        uncertainHabits: Int,
        selfReportedHabits: Int,
        accountabilityTasks: Int,
        accountabilityTasksCompleted: Int,
        accountabilityTasksFailed: Int,
        verificationCount: Int = 0,
        verificationConfidenceSum: Double = 0,
        outcome: DayOutcome,
        streakBefore: Int,
        streakAfter: Int,
        resolverVersion: String
    ) {
        self.participantId = participantId
        self.challengeId = challengeId
        self.day = day
        self.trackingCondition = trackingCondition
        self.requiredHabits = requiredHabits
        self.completedHabits = completedHabits
        self.skippedHabits = skippedHabits
        self.verifiedHabits = verifiedHabits
        self.rejectedHabits = rejectedHabits
        self.uncertainHabits = uncertainHabits
        self.selfReportedHabits = selfReportedHabits
        self.accountabilityTasks = accountabilityTasks
        self.accountabilityTasksCompleted = accountabilityTasksCompleted
        self.accountabilityTasksFailed = accountabilityTasksFailed
        self.verificationCount = verificationCount
        self.verificationConfidenceSum = verificationConfidenceSum
        self.outcome = outcome
        self.streakBefore = streakBefore
        self.streakAfter = streakAfter
        self.resolverVersion = resolverVersion
    }
}

/// Firestore collection names, shared by the app, rules and Cloud Functions documentation.
public enum Collections {
    public static let users = "users"
    public static let habits = "habits"
    public static let habitCompletions = "habitCompletions"
    public static let challenges = "challenges"
    public static let evidence = "evidence"
    public static let verifications = "verifications"
    public static let accountabilityTasks = "accountabilityTasks"
    public static let exerciseSessions = "exerciseSessions"
    public static let dailyRecords = "dailyRecords"
    public static let usabilityResponses = "usabilityResponses"
}
