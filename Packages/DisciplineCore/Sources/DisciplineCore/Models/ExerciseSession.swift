import Foundation

public enum ExerciseKind: String, Codable, CaseIterable, Sendable {
    case pushUps, squats, sitUps, lunges

    public init?(taskType: AccountabilityTaskType) {
        switch taskType {
        case .pushUps: self = .pushUps
        case .squats: self = .squats
        case .sitUps: self = .sitUps
        case .lunges: self = .lunges
        default: return nil
        }
    }
}

public enum ExerciseVerificationMethod: String, Codable, Sendable {
    /// Apple Vision `VNDetectHumanBodyPoseRequest`, processed on device.
    case visionBodyPose2D
}

public enum ExerciseSessionOutcome: String, Codable, Sendable {
    case inProgress
    /// Target number of valid repetitions reached.
    case completed
    /// Participant ended the session before reaching the target.
    case abandoned
    /// Tracking was lost for too long (participant left the frame, camera interrupted).
    case interrupted
}

/// One attempt at an exercise in front of the camera. Stored at `exerciseSessions/{id}`.
/// Individual repetition events are kept so rep validity can be audited later.
public struct ExerciseSession: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var userId: String
    public var accountabilityTaskId: String
    public var exercise: ExerciseKind
    public var startedAt: Date
    public var completedAt: Date?
    public var targetReps: Int
    public var validReps: Int
    public var invalidReps: Int
    public var verificationMethod: ExerciseVerificationMethod
    /// Version of the thresholds used by the repetition state machine.
    public var engineVersion: String
    public var outcome: ExerciseSessionOutcome
    public var repetitions: [RepetitionEvent]

    public init(
        id: String = UUID().uuidString,
        userId: String,
        accountabilityTaskId: String,
        exercise: ExerciseKind,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        targetReps: Int,
        validReps: Int = 0,
        invalidReps: Int = 0,
        verificationMethod: ExerciseVerificationMethod = .visionBodyPose2D,
        engineVersion: String,
        outcome: ExerciseSessionOutcome = .inProgress,
        repetitions: [RepetitionEvent] = []
    ) {
        self.id = id
        self.userId = userId
        self.accountabilityTaskId = accountabilityTaskId
        self.exercise = exercise
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.targetReps = targetReps
        self.validReps = validReps
        self.invalidReps = invalidReps
        self.verificationMethod = verificationMethod
        self.engineVersion = engineVersion
        self.outcome = outcome
        self.repetitions = repetitions
    }
}

/// Reason a repetition was not counted.
public enum RepetitionFault: String, Codable, Sendable {
    case insufficientDepth
    case incompleteLockout
    case bodyNotStraight
    case trackingLost
}

public struct RepetitionEvent: Codable, Hashable, Sendable {
    public var index: Int
    public var timestamp: Date
    public var isValid: Bool
    public var fault: RepetitionFault?
    /// Smallest elbow (or knee) angle reached during the repetition, in degrees.
    public var minimumAngle: Double
    /// Largest angle reached at the top of the repetition, in degrees.
    public var maximumAngle: Double

    public init(index: Int, timestamp: Date, isValid: Bool, fault: RepetitionFault?, minimumAngle: Double, maximumAngle: Double) {
        self.index = index
        self.timestamp = timestamp
        self.isValid = isValid
        self.fault = fault
        self.minimumAngle = minimumAngle
        self.maximumAngle = maximumAngle
    }
}
