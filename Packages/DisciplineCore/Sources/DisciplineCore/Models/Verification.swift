import Foundation

public enum VerificationStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case verified
    case rejected
    case uncertain
    /// The verification pipeline failed (timeout, malformed response, provider error).
    /// Distinct from `uncertain`, which is a valid assessment with low confidence.
    case error
}

/// A single, explicit visual criterion. The model is asked about these — never the
/// open-ended question "did the person complete the habit?".
public struct VerificationCriterion: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// The yes/no question posed to the model.
    public var question: String
    /// If `true`, failing this criterion rejects the evidence.
    public var isRequired: Bool

    public init(id: String, name: String, question: String, isRequired: Bool = true) {
        self.id = id
        self.name = name
        self.question = question
        self.isRequired = isRequired
    }
}

public struct CriterionResult: Codable, Hashable, Sendable {
    public var criterionId: String
    public var name: String
    public var passed: Bool

    public init(criterionId: String, name: String, passed: Bool) {
        self.criterionId = criterionId
        self.name = name
        self.passed = passed
    }
}

/// Photographic evidence submitted for a habit completion. Stored at `evidence/{id}`;
/// the image itself lives in private Storage at `evidence/{uid}/{evidenceId}.jpg`.
public struct Evidence: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var userId: String
    public var habitId: String
    public var completionId: String
    /// Storage path (not a public download URL). Access is mediated by Storage rules.
    public var storagePath: String
    public var submittedAt: Date
    public var verificationStatus: VerificationStatus
    public var verificationResultId: String?
    public var verificationMethod: VerificationType
    /// `camera` or `library`. Library images are easier to reuse, which matters for analysis.
    public var captureSource: CaptureSource

    public enum CaptureSource: String, Codable, Sendable { case camera, library }

    public init(
        id: String = UUID().uuidString,
        userId: String,
        habitId: String,
        completionId: String,
        storagePath: String,
        submittedAt: Date = Date(),
        verificationStatus: VerificationStatus = .pending,
        verificationResultId: String? = nil,
        verificationMethod: VerificationType = .photoAI,
        captureSource: CaptureSource
    ) {
        self.id = id
        self.userId = userId
        self.habitId = habitId
        self.completionId = completionId
        self.storagePath = storagePath
        self.submittedAt = submittedAt
        self.verificationStatus = verificationStatus
        self.verificationResultId = verificationResultId
        self.verificationMethod = verificationMethod
        self.captureSource = captureSource
    }
}

/// Immutable record of one verification attempt. Written once by the backend at
/// `verifications/{id}` and never updated; re-verification creates a new record.
public struct VerificationResult: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var userId: String
    public var habitId: String
    public var evidenceId: String
    public var timestamp: Date
    public var provider: String
    public var model: String
    /// Version of the prompt/criteria template, so results are reproducible and comparable.
    public var promptVersion: String
    public var criteria: [CriterionResult]
    public var status: VerificationStatus
    /// Model-reported confidence in [0, 1]. `nil` when the pipeline errored.
    public var confidence: Double?
    /// Confidence threshold in effect when the status was decided.
    public var confidenceThreshold: Double
    public var reason: String
    public var flags: [String]
    public var processingTimeMs: Int
    public var errorCode: String?

    public init(
        id: String,
        userId: String,
        habitId: String,
        evidenceId: String,
        timestamp: Date,
        provider: String,
        model: String,
        promptVersion: String,
        criteria: [CriterionResult],
        status: VerificationStatus,
        confidence: Double?,
        confidenceThreshold: Double,
        reason: String,
        flags: [String] = [],
        processingTimeMs: Int,
        errorCode: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.habitId = habitId
        self.evidenceId = evidenceId
        self.timestamp = timestamp
        self.provider = provider
        self.model = model
        self.promptVersion = promptVersion
        self.criteria = criteria
        self.status = status
        self.confidence = confidence
        self.confidenceThreshold = confidenceThreshold
        self.reason = reason
        self.flags = flags
        self.processingTimeMs = processingTimeMs
        self.errorCode = errorCode
    }
}
