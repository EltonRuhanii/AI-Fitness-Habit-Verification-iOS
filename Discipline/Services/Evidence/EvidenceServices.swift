import Foundation
import DisciplineCore

/// Stores evidence photos and their records.
@MainActor
protocol EvidenceService: AnyObject {
    /// Uploads the JPEG, then atomically records the evidence and its pending completion.
    /// Needs a connection: nothing is recorded if the upload fails, so a slot is never
    /// occupied by evidence the server can't see.
    func submit(jpeg: Data, evidence: Evidence, completion: HabitCompletion) async throws
    func fetchVerification(id: String) async throws -> VerificationResult?
}

/// Requests an automated assessment of submitted evidence.
///
/// The client never talks to an AI provider directly. The Firebase implementation calls the
/// `verifyEvidence` Cloud Function, which holds the provider key, builds the criteria prompt,
/// applies the decision policy and writes the immutable result. The provider itself is
/// replaceable server-side (`firebase/functions/src/providers`).
@MainActor
protocol AIVerificationService: AnyObject {
    /// Short description shown to participants, e.g. "Claude (Anthropic) via secure server".
    var providerDescription: String { get }
    func verify(evidenceId: String) async throws -> VerificationResult
}
