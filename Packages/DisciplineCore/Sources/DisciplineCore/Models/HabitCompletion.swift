import Foundation

/// Lifecycle state of a single habit occurrence. Deliberately richer than a Boolean so the
/// research data can distinguish *how* a commitment was (or was not) met.
public enum CompletionStatus: String, Codable, CaseIterable, Sendable {
    /// Created but nothing has happened yet.
    case pending
    /// Participant marked the habit complete without evidence (manual condition or evidence optional).
    case selfReported
    /// Evidence submitted, automated verification not yet returned.
    case pendingVerification
    /// Verification indicates the evidence satisfies the defined criteria.
    case verified
    /// Verification indicates the evidence does not satisfy the defined criteria.
    case rejected
    /// Verification could not reach the confidence threshold.
    case uncertain
    /// Participant explicitly skipped; no consequence configured.
    case skipped
    /// Participant skipped and accepted an accountability task that is not yet complete.
    case accountabilityRequired
    /// Skipped, and the accountability task was completed.
    case resolved
    /// The occurrence was not resolved before the end of its day.
    case failed

    /// Whether this status counts as the habit being done for progress purposes.
    /// `uncertain` is intentionally excluded here; whether it resolves a day is a challenge rule.
    public var countsAsCompleted: Bool {
        switch self {
        case .selfReported, .verified: return true
        default: return false
        }
    }

    /// Terminal states cannot transition further (except `pendingVerification` re-submission).
    public var isTerminal: Bool {
        switch self {
        case .selfReported, .verified, .rejected, .resolved, .failed: return true
        default: return false
        }
    }
}

/// How the completion was established. Stored with every completion so manual and
/// AI-assisted data can be separated during analysis even within one participant.
public enum CompletionMethod: String, Codable, Sendable {
    case selfReport
    case photoVerification
    case accountabilityExercise
}

public struct HabitCompletion: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var userId: String
    public var habitId: String
    public var challengeId: String?
    /// Participant-local day this completion belongs to.
    public var day: DayKey
    /// Amount contributed towards the target (1 for sessions, N for pages/minutes).
    public var quantity: Int
    public var status: CompletionStatus
    public var method: CompletionMethod
    /// Condition in effect at the time of this event.
    public var trackingCondition: TrackingCondition
    public var evidenceId: String?
    /// Most recent verification for this completion. Earlier attempts remain in `verifications`.
    public var verificationId: String?
    public var accountabilityTaskId: String?
    public var createdAt: Date
    public var updatedAt: Date
    /// Client-generated idempotency key; prevents duplicate completions from offline retries.
    public var clientRequestId: String

    public init(
        id: String = UUID().uuidString,
        userId: String,
        habitId: String,
        challengeId: String? = nil,
        day: DayKey,
        quantity: Int = 1,
        status: CompletionStatus,
        method: CompletionMethod,
        trackingCondition: TrackingCondition,
        evidenceId: String? = nil,
        verificationId: String? = nil,
        accountabilityTaskId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        clientRequestId: String = UUID().uuidString
    ) {
        self.id = id
        self.userId = userId
        self.habitId = habitId
        self.challengeId = challengeId
        self.day = day
        self.quantity = max(0, quantity)
        self.status = status
        self.method = method
        self.trackingCondition = trackingCondition
        self.evidenceId = evidenceId
        self.verificationId = verificationId
        self.accountabilityTaskId = accountabilityTaskId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.clientRequestId = clientRequestId
    }
}
