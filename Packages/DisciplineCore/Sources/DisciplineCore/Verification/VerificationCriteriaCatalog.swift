import Foundation

/// The versioned catalog of visual criteria per habit category, loaded from
/// `verification-criteria.json`. The same file is bundled into the Cloud Function, so the
/// criteria a participant sees before submitting are exactly the ones the model is asked.
public struct VerificationCriteriaCatalog: Decodable, Sendable {
    public let version: String
    public let defaultConfidenceThreshold: Double
    public let flags: [String]
    public let sharedCriteria: [VerificationCriterion]
    public let categories: [String: [VerificationCriterion]]

    /// Shared criteria first (e.g. "genuine photograph"), then category-specific ones.
    public func criteria(for category: HabitCategory) -> [VerificationCriterion] {
        sharedCriteria + (categories[category.rawValue] ?? categories[HabitCategory.custom.rawValue] ?? [])
    }

    public static func decode(from data: Data) throws -> VerificationCriteriaCatalog {
        try JSONDecoder().decode(VerificationCriteriaCatalog.self, from: data)
    }

    /// The catalog bundled with DisciplineCore.
    public static let bundled: VerificationCriteriaCatalog = {
        guard let url = Bundle.module.url(forResource: "verification-criteria", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? decode(from: data)
        else {
            preconditionFailure("verification-criteria.json is missing or invalid; it is a build-time resource of DisciplineCore.")
        }
        return catalog
    }()
}
