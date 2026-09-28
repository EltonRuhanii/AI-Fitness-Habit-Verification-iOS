import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import DisciplineCore

@MainActor
final class FirebaseEvidenceService: EvidenceService {
    private let db: Firestore
    private let storage: Storage

    init(db: Firestore = Firestore.firestore(), storage: Storage = Storage.storage()) {
        self.db = db
        self.storage = storage
    }

    func submit(jpeg: Data, evidence: Evidence, completion: HabitCompletion) async throws {
        do {
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await storage.reference(withPath: evidence.storagePath).putDataAsync(jpeg, metadata: metadata)

            // Both documents in one batch: either the participant has a pending submission the
            // verifier can find, or nothing was recorded at all.
            let batch = db.batch()
            batch.setData(try Firestore.Encoder().encode(completion),
                          forDocument: db.collection(Collections.habitCompletions).document(completion.id))
            batch.setData(try Firestore.Encoder().encode(evidence),
                          forDocument: db.collection(Collections.evidence).document(evidence.id))
            try await batch.commit()
        } catch {
            throw AppError.from(error)
        }
    }

    func fetchVerification(id: String) async throws -> VerificationResult? {
        do {
            let snapshot = try await db.collection(Collections.verifications).document(id).getDocument()
            return snapshot.exists ? try snapshot.data(as: VerificationResult.self) : nil
        } catch {
            throw AppError.from(error)
        }
    }
}

@MainActor
final class FirebaseVerificationService: AIVerificationService {
    private let functions: Functions

    init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    let providerDescription = "Claude (Anthropic) via the study's secure server"

    func verify(evidenceId: String) async throws -> VerificationResult {
        let callable = functions.httpsCallable("verifyEvidence")
        callable.timeoutInterval = 130
        do {
            let result = try await callable.call(["evidenceId": evidenceId])
            let json = try JSONSerialization.data(withJSONObject: result.data)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return try decoder.decode(VerificationResult.self, from: json)
        } catch let error as DecodingError {
            Log.data.error("Unexpected verification payload: \(String(describing: error), privacy: .public)")
            throw AppError.unknown("The verification result couldn't be read.")
        } catch {
            throw AppError.from(error)
        }
    }
}
