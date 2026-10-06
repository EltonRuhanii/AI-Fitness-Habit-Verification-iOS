import Foundation

/// The System Usability Scale (Brooke, 1996): ten statements answered on a five-point scale
/// from 1 (strongly disagree) to 5 (strongly agree), "system" worded as "app".
public enum SUSQuestionnaire {
    public static let version = "sus-v1"

    public static let statements: [String] = [
        "I think that I would like to use this app frequently.",
        "I found the app unnecessarily complex.",
        "I thought the app was easy to use.",
        "I think that I would need the support of a technical person to be able to use this app.",
        "I found the various functions in this app were well integrated.",
        "I thought there was too much inconsistency in this app.",
        "I would imagine that most people would learn to use this app very quickly.",
        "I found the app very cumbersome to use.",
        "I felt very confident using the app.",
        "I needed to learn a lot of things before I could get going with this app."
    ]

    public static let scale = 1...5

    /// 0–100. Odd statements (positive) contribute `answer - 1`, even statements (negative)
    /// contribute `5 - answer`; the sum is multiplied by 2.5. Nil unless all ten are answered.
    public static func score(_ responses: [Int]) -> Double? {
        guard responses.count == statements.count, responses.allSatisfy({ scale.contains($0) }) else { return nil }
        let sum = responses.enumerated().reduce(0) { total, item in
            total + (item.offset.isMultiple(of: 2) ? item.element - 1 : 5 - item.element)
        }
        return Double(sum) * 2.5
    }

    /// Commonly used adjective bands (Bangor, Kortum & Miller, 2009), for display only.
    public static func rating(for score: Double) -> String {
        switch score {
        case ..<51: return "Poor"
        case ..<68: return "OK"
        case ..<80.3: return "Good"
        case ..<90: return "Excellent"
        default: return "Best imaginable"
        }
    }
}

/// One completed questionnaire. Pseudonymous: linked to the participant ID, never the account.
public struct SUSResponse: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var participantId: String
    public var trackingCondition: TrackingCondition
    public var questionnaireVersion: String
    /// The ten answers in statement order, each 1…5.
    public var responses: [Int]
    /// Computed on the device for display; the study export recomputes it from `responses`.
    public var score: Double
    /// Day of the challenge when answered (nil outside a challenge).
    public var challengeDay: Int?
    public var submittedAt: Date

    public init(id: String = UUID().uuidString, participantId: String, trackingCondition: TrackingCondition,
                questionnaireVersion: String = SUSQuestionnaire.version, responses: [Int], score: Double,
                challengeDay: Int?, submittedAt: Date = Date()) {
        self.id = id
        self.participantId = participantId
        self.trackingCondition = trackingCondition
        self.questionnaireVersion = questionnaireVersion
        self.responses = responses
        self.score = score
        self.challengeDay = challengeDay
        self.submittedAt = submittedAt
    }

    /// Validates the answers and builds the response.
    public static func make(participantId: String, condition: TrackingCondition, responses: [Int],
                            challengeDay: Int?, now: Date = Date()) -> SUSResponse? {
        guard let score = SUSQuestionnaire.score(responses) else { return nil }
        return SUSResponse(participantId: participantId, trackingCondition: condition, responses: responses,
                           score: score, challengeDay: challengeDay, submittedAt: now)
    }
}

extension ResearchCSV {
    public static let usabilityHeader = ["participant_id", "condition", "questionnaire", "submitted_at", "challenge_day"]
        + (1...10).map { "q\($0)" } + ["sus_score"]

    public static func usability(_ responses: [SUSResponse]) -> String {
        let iso = ISO8601DateFormatter()
        let rows = responses
            .sorted { ($0.participantId, $0.submittedAt) < ($1.participantId, $1.submittedAt) }
            .map { r -> [String] in
                [r.participantId, r.trackingCondition.rawValue, r.questionnaireVersion, iso.string(from: r.submittedAt),
                 r.challengeDay.map(String.init) ?? ""]
                    + r.responses.map(String.init)
                    + [SUSQuestionnaire.score(r.responses).map { String(format: "%.1f", $0) } ?? ""]
            }
        return encode(header: usabilityHeader, rows: rows)
    }
}
