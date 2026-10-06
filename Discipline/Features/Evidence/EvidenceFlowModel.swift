import UIKit
import Observation
import DisciplineCore

/// Drives one evidence submission: choose photo → preview → upload → verify → result.
@MainActor
@Observable
final class EvidenceFlowModel {
    enum Phase: Equatable {
        case choosing
        case preview
        case uploading
        case verifying
        case finished(VerificationResult)
        /// `canRetryVerification`: the upload succeeded, so only verification needs repeating.
        case failed(AppError, canRetryVerification: Bool)
    }

    let habit: Habit
    let criteria: [VerificationCriterion]
    let providerDescription: String

    private(set) var phase: Phase = .choosing
    private(set) var image: UIImage?
    private(set) var captureSource: Evidence.CaptureSource = .camera
    /// Amount for pages/minutes habits (sessions always count 1).
    var quantity: Int

    private let store: HabitsStore
    private let evidenceService: EvidenceService
    private let performance: PerformanceLog
    private let verificationService: AIVerificationService
    private var submittedEvidenceId: String?

    init(habit: Habit, store: HabitsStore, evidence: EvidenceService, verification: AIVerificationService,
         performance: PerformanceLog) {
        self.habit = habit
        self.performance = performance
        self.store = store
        self.evidenceService = evidence
        self.verificationService = verification
        self.criteria = VerificationCriteriaCatalog.bundled.criteria(for: habit.category)
        self.providerDescription = verification.providerDescription
        self.quantity = store.defaultLogAmount(for: habit)
    }

    var isBusy: Bool { phase == .uploading || phase == .verifying }

    func use(_ image: UIImage, source: Evidence.CaptureSource) {
        self.image = image
        captureSource = source
        phase = .preview
    }

    func retake() {
        image = nil
        phase = .choosing
    }

    func submit() async {
        guard let image else { return }
        guard let jpeg = EvidenceImage.prepareJPEG(from: image) else {
            phase = .failed(.validation("This photo couldn't be processed. Try another one."), canRetryVerification: false)
            return
        }
        phase = .uploading
        do {
            let evidenceId = UUID().uuidString
            let completion = try store.makeEvidenceSubmission(for: habit, evidenceId: evidenceId, quantity: quantity)
            let evidence = Evidence(
                id: evidenceId,
                userId: store.userId,
                habitId: habit.id,
                completionId: completion.id,
                storagePath: "evidence/\(store.userId)/\(evidenceId).jpg",
                captureSource: captureSource
            )
            try await performance.measure(.evidenceUpload, context: "\(jpeg.count / 1024) KB") {
                try await evidenceService.submit(jpeg: jpeg, evidence: evidence, completion: completion)
            }
            submittedEvidenceId = evidenceId
            await verify()
        } catch {
            phase = .failed(AppError.from(error), canRetryVerification: false)
        }
    }

    func verify() async {
        guard let evidenceId = submittedEvidenceId else { return }
        phase = .verifying
        do {
            let result = try await performance.measure(.aiVerification, context: providerDescription) {
                try await verificationService.verify(evidenceId: evidenceId)
            }
            phase = .finished(result)
            if result.status == .verified { store.noteCompletionEvent() }
        } catch {
            phase = .failed(AppError.from(error), canRetryVerification: true)
        }
    }
}
