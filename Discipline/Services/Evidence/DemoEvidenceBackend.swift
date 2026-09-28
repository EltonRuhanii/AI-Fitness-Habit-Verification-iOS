import Foundation
import Vision
import DisciplineCore

/// Demo-mode evidence storage and verification, entirely on device.
///
/// Verification uses Apple's built-in image classifier (`VNClassifyImageRequest`) and simple
/// keyword matching per criterion, then applies the *same* `VerificationPolicy` as the study
/// backend. It is labelled as a demo classifier everywhere and is not the study's AI. It exists
/// so the full flow can be demonstrated without Firebase or an AI provider key.
@MainActor
final class DemoEvidenceBackend: EvidenceService, AIVerificationService {
    let providerDescription = "On-device demo classifier (not the study AI)"

    private static let promptVersion = "\(VerificationCriteriaCatalog.bundled.version)/demo-keywords-v1"

    private let completions: CompletionRepository
    private let habits: DemoHabitRepository
    private let evidence = DemoCollection<Evidence>(fileName: "demo-evidence.json")
    private let verifications = DemoCollection<VerificationResult>(fileName: "demo-verifications.json")
    /// Copies of submitted completions, so verification can update them after an app restart.
    private let submittedCompletions = DemoCollection<HabitCompletion>(fileName: "demo-evidence-completions.json")
    private let imageDirectory: URL

    /// - Parameter habits: used to look up the category of submitted evidence.
    init(completions: CompletionRepository, habits: DemoHabitRepository) {
        self.completions = completions
        self.habits = habits
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        imageDirectory = base.appendingPathComponent("Demo/evidence", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    }

    // MARK: EvidenceService

    func submit(jpeg: Data, evidence item: Evidence, completion: HabitCompletion) async throws {
        try jpeg.write(to: imageURL(for: item.id), options: [.atomic, .completeFileProtection])
        try evidence.upsert(item)
        try submittedCompletions.upsert(completion)
        try completions.save(completion)
    }

    func fetchVerification(id: String) async throws -> VerificationResult? {
        verifications.snapshot().first { $0.id == id }
    }

    // MARK: AIVerificationService

    func verify(evidenceId: String) async throws -> VerificationResult {
        guard var item = evidence.snapshot().first(where: { $0.id == evidenceId }) else {
            throw AppError.notFound
        }
        guard let habit = habits.all().first(where: { $0.id == item.habitId }) else { throw AppError.notFound }

        let catalog = VerificationCriteriaCatalog.bundled
        let criteria = catalog.criteria(for: habit.category)
        let threshold = catalog.defaultConfidenceThreshold
        let started = Date()
        let url = imageURL(for: evidenceId)

        var result: VerificationResult
        do {
            let labels = try await Task.detached(priority: .userInitiated) { try Self.classify(imageAt: url) }.value
            let assessment = Self.assess(labels: labels, criteria: criteria)
            let decision = try VerificationPolicy.decide(assessment, criteria: criteria, threshold: threshold)
            result = VerificationResult(
                id: UUID().uuidString, userId: item.userId, habitId: habit.id, evidenceId: evidenceId,
                timestamp: Date(), provider: "apple-vision-demo", model: "VNClassifyImageRequest",
                promptVersion: Self.promptVersion, criteria: decision.criteria, status: decision.status,
                confidence: decision.confidence, confidenceThreshold: threshold, reason: decision.reason,
                flags: decision.flags, processingTimeMs: Int(Date().timeIntervalSince(started) * 1000)
            )
        } catch {
            result = VerificationResult(
                id: UUID().uuidString, userId: item.userId, habitId: habit.id, evidenceId: evidenceId,
                timestamp: Date(), provider: "apple-vision-demo", model: "VNClassifyImageRequest",
                promptVersion: Self.promptVersion, criteria: [], status: .error, confidence: nil,
                confidenceThreshold: threshold, reason: "The on-device classifier couldn't process this image.",
                processingTimeMs: Int(Date().timeIntervalSince(started) * 1000), errorCode: "classifier_error"
            )
        }

        try verifications.upsert(result)
        item.verificationStatus = result.status
        item.verificationResultId = result.id
        try evidence.upsert(item)

        if var completion = submittedCompletions.snapshot().first(where: { $0.id == item.completionId }) {
            completion.verificationId = result.id
            completion.updatedAt = Date()
            if let status = result.status.completionStatus { completion.status = status }
            try submittedCompletions.upsert(completion)
            try completions.save(completion)
        }
        return result
    }

    // MARK: Classification

    private func imageURL(for evidenceId: String) -> URL {
        imageDirectory.appendingPathComponent("\(evidenceId).jpg")
    }

    nonisolated private static func classify(imageAt url: URL) throws -> [(label: String, confidence: Double)] {
        let request = VNClassifyImageRequest()
        try VNImageRequestHandler(url: url, options: [:]).perform([request])
        return (request.results ?? [])
            .filter { $0.confidence > 0.05 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(12)
            .map { ($0.identifier.lowercased(), Double($0.confidence)) }
    }

    /// Keywords matched against classifier labels, per criterion id.
    private static let keywords: [String: [String]] = [
        "workout_environment": ["gym", "fitness", "exercise", "weight", "sport", "bench", "treadmill"],
        "equipment_visible": ["dumbbell", "barbell", "weight", "kettlebell", "machine", "equipment", "treadmill", "bench"],
        "exercise_context": ["gym", "fitness", "exercise", "sport", "yoga", "weight", "running", "athlet"],
        "running_context": ["run", "jog", "track", "road", "trail", "path", "shoe", "sneaker", "park", "treadmill"],
        "reading_material_visible": ["book", "text", "document", "paper", "page", "publication", "magazine", "library"],
        "recovery_setup_visible": ["water", "pool", "ice", "bath", "tub", "lake", "sea", "ocean", "sauna", "snow", "yoga"],
        "food_visible": ["food", "meal", "dish", "plate", "salad", "fruit", "vegetable", "dessert", "bread", "meat", "breakfast"]
    ]

    nonisolated private static func assess(labels: [(label: String, confidence: Double)], criteria: [VerificationCriterion]) -> ModelAssessment {
        func match(_ id: String) -> Double? {
            guard let words = keywords[id] else { return nil }
            return labels.first { entry in words.contains { entry.label.contains($0) } }?.confidence
        }
        let specificIds = criteria.map(\.id).filter { keywords[$0] != nil }
        let matched = specificIds.compactMap(match)
        let anySpecificMatch = !matched.isEmpty || specificIds.isEmpty

        let answers = criteria.map { criterion -> ModelAssessment.Answer in
            switch criterion.id {
            case "authentic_photo": return .init(id: criterion.id, passed: true) // the demo classifier can't judge this
            case "relevant_to_activity": return .init(id: criterion.id, passed: anySpecificMatch)
            default: return .init(id: criterion.id, passed: match(criterion.id) != nil)
            }
        }
        let confidence = min(1, max(matched.max() ?? labels.first?.confidence ?? 0, 0))
        let top = labels.prefix(3).map { "\($0.label.replacingOccurrences(of: "_", with: " ")) (\(Int($0.confidence * 100))%)" }
        let reason = top.isEmpty
            ? "The demo classifier found no recognizable content."
            : "Demo classifier detected: \(top.joined(separator: ", "))."
        return ModelAssessment(criteria: answers, confidence: confidence, reason: reason, flags: [])
    }
}
