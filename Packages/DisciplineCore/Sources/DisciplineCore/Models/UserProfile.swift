import Foundation

/// The experimental condition a participant is assigned to.
///
/// This is the independent variable of the study. It is stored on the participant *and*
/// copied onto every completion and daily record at the time of the event, so the
/// analysis never has to reconstruct which condition applied on a given day.
public enum TrackingCondition: String, Codable, CaseIterable, Sendable {
    /// Participant marks habits complete (self-report). No evidence is requested.
    case manual
    /// Participant submits evidence that is assessed by automated verification.
    case aiAssisted

    public var displayName: String {
        switch self {
        case .manual: return "Manual tracking"
        case .aiAssisted: return "AI-assisted tracking"
        }
    }
}

/// Private account profile. Stored at `users/{uid}`; readable only by its owner.
public struct UserProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var email: String
    public var displayName: String
    public var profileImageURL: URL?
    public var createdAt: Date
    public var onboardingCompleted: Bool
    /// When the participant accepted the challenge/accountability rules. `nil` until accepted.
    public var rulesAcceptedAt: Date?
    /// When the participant consented to pseudonymous research data collection.
    public var researchConsentAt: Date?
    /// Random pseudonymous identifier used in all research data instead of the auth uid.
    public var participantId: String
    public var trackingCondition: TrackingCondition
    public var activeChallengeId: String?

    public init(
        id: String,
        email: String,
        displayName: String,
        profileImageURL: URL? = nil,
        createdAt: Date = Date(),
        onboardingCompleted: Bool = false,
        rulesAcceptedAt: Date? = nil,
        researchConsentAt: Date? = nil,
        participantId: String = ParticipantID.generate(),
        trackingCondition: TrackingCondition = .aiAssisted,
        activeChallengeId: String? = nil
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.profileImageURL = profileImageURL
        self.createdAt = createdAt
        self.onboardingCompleted = onboardingCompleted
        self.rulesAcceptedAt = rulesAcceptedAt
        self.researchConsentAt = researchConsentAt
        self.participantId = participantId
        self.trackingCondition = trackingCondition
        self.activeChallengeId = activeChallengeId
    }
}

public enum ParticipantID {
    /// `P-` followed by 10 characters from an unambiguous alphabet. Not derived from any
    /// personal data, so it cannot be reversed into an identity.
    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    public static func generate<G: RandomNumberGenerator>(using generator: inout G) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let suffix = (0..<10).map { _ in alphabet[Int(generator.next(upperBound: UInt64(alphabet.count)))] }
        return "P-" + String(suffix)
    }
}
