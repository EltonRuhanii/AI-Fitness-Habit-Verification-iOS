import Foundation

/// What the vision model is asked to return: a yes/no answer per defined criterion, an
/// overall confidence, a short reason and optional flags. It does NOT return a verdict;
/// the verdict is derived deterministically by `VerificationPolicy`.
public struct ModelAssessment: Codable, Hashable, Sendable {
    public struct Answer: Codable, Hashable, Sendable {
        public let id: String
        public let passed: Bool

        public init(id: String, passed: Bool) {
            self.id = id
            self.passed = passed
        }
    }

    public let criteria: [Answer]
    public let confidence: Double
    public let reason: String
    public let flags: [String]

    public init(criteria: [Answer], confidence: Double, reason: String, flags: [String]) {
        self.criteria = criteria
        self.confidence = confidence
        self.reason = reason
        self.flags = flags
    }
}

public enum VerificationPolicyError: Error, Equatable, Sendable {
    /// The response wasn't valid JSON of the expected shape, omitted or duplicated a defined
    /// criterion, or reported a confidence outside [0, 1].
    case malformedResponse(String)

    /// Stable code stored in `VerificationResult.errorCode`.
    public var code: String { "malformed_response" }
}

public struct VerificationDecision: Equatable, Sendable {
    public let status: VerificationStatus
    public let confidence: Double
    public let criteria: [CriterionResult]
    public let reason: String
    public let flags: [String]
}

/// Deterministic mapping from a model assessment to verified / rejected / uncertain.
///
///  1. The response must answer every defined criterion exactly once, with confidence in [0, 1].
///  2. If confidence < threshold the result is `uncertain`, regardless of the answers.
///  3. Otherwise `verified` if every required criterion passed, else `rejected`.
///
/// Mirrored in `firebase/functions/src/policy.ts`; both implementations run the shared
/// test vectors in `Tests/DisciplineCoreTests/Fixtures/verification-policy-cases.json`.
public enum VerificationPolicy {
    public static let unexpectedCriterionFlag = "unexpected_criterion"

    public static func parse(_ data: Data) throws -> ModelAssessment {
        do {
            return try JSONDecoder().decode(ModelAssessment.self, from: data)
        } catch {
            throw VerificationPolicyError.malformedResponse("Response is not valid assessment JSON.")
        }
    }

    public static func decide(
        _ assessment: ModelAssessment,
        criteria: [VerificationCriterion],
        threshold: Double
    ) throws -> VerificationDecision {
        guard assessment.confidence.isFinite, (0...1).contains(assessment.confidence) else {
            throw VerificationPolicyError.malformedResponse("Confidence \(assessment.confidence) is outside [0, 1].")
        }

        var answers: [String: Bool] = [:]
        for answer in assessment.criteria {
            if let existing = answers[answer.id], existing != answer.passed {
                throw VerificationPolicyError.malformedResponse("Criterion \(answer.id) was answered inconsistently.")
            }
            answers[answer.id] = answer.passed
        }

        var results: [CriterionResult] = []
        for criterion in criteria {
            guard let passed = answers[criterion.id] else {
                throw VerificationPolicyError.malformedResponse("Criterion \(criterion.id) was not answered.")
            }
            results.append(CriterionResult(criterionId: criterion.id, name: criterion.name, passed: passed))
        }

        var flags = assessment.flags
        let known = Set(criteria.map(\.id))
        if answers.keys.contains(where: { !known.contains($0) }) {
            flags.append(unexpectedCriterionFlag)
        }

        let status: VerificationStatus
        if assessment.confidence < threshold {
            status = .uncertain
        } else {
            let requiredIds = Set(criteria.filter(\.isRequired).map(\.id))
            let allRequiredPassed = results.allSatisfy { !requiredIds.contains($0.criterionId) || $0.passed }
            status = allRequiredPassed ? .verified : .rejected
        }

        return VerificationDecision(
            status: status,
            confidence: assessment.confidence,
            criteria: results,
            reason: assessment.reason,
            flags: flags
        )
    }
}

public extension VerificationStatus {
    /// The completion status that a finished verification leads to. `nil` while pending or
    /// after a pipeline error: the completion stays `pendingVerification` so it can be retried.
    var completionStatus: CompletionStatus? {
        switch self {
        case .verified: return .verified
        case .rejected: return .rejected
        case .uncertain: return .uncertain
        case .pending, .error: return nil
        }
    }
}
