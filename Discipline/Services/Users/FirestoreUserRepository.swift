import Foundation
import FirebaseFirestore
import DisciplineCore

@MainActor
final class FirestoreUserRepository: UserRepository {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    private func document(_ uid: String) -> DocumentReference {
        db.collection(Collections.users).document(uid)
    }

    func fetchProfile(uid: String) async throws -> UserProfile? {
        do {
            let snapshot = try await document(uid).getDocument()
            guard snapshot.exists else { return nil }
            return try snapshot.data(as: UserProfile.self)
        } catch {
            throw AppError.from(error)
        }
    }

    func createProfile(_ profile: UserProfile) async throws {
        do {
            let data = try Firestore.Encoder().encode(profile)
            try await document(profile.id).setData(data)
        } catch {
            throw AppError.from(error)
        }
    }

    func observeProfile(uid: String) -> AsyncThrowingStream<UserProfile?, Error> {
        AsyncThrowingStream { continuation in
            let registration = document(uid).addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: AppError.from(error))
                    return
                }
                guard let snapshot else { return }
                guard snapshot.exists else {
                    continuation.yield(nil)
                    return
                }
                do {
                    continuation.yield(try snapshot.data(as: UserProfile.self))
                } catch {
                    Log.data.error("Could not decode profile: \(error.localizedDescription, privacy: .public)")
                }
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    func updateProfile(_ profile: UserProfile) async throws {
        // Field-level update: the server owns trackingCondition / participantId / assignment
        // fields, and rewriting them (even unchanged-looking) could be rejected by the rules.
        func value(_ optional: Any?) -> Any { optional ?? FieldValue.delete() }
        let fields: [String: Any] = [
            "displayName": profile.displayName,
            "onboardingCompleted": profile.onboardingCompleted,
            "rulesAcceptedAt": value(profile.rulesAcceptedAt.map(Timestamp.init(date:))),
            "researchConsentAt": value(profile.researchConsentAt.map(Timestamp.init(date:))),
            "activeChallengeId": value(profile.activeChallengeId),
            "profileImageURL": value(profile.profileImageURL?.absoluteString),
            "timeZone": value(profile.timeZone)
        ]
        do {
            try await document(profile.id).updateData(fields)
        } catch {
            throw AppError.from(error)
        }
    }

    func prepareForAccountDeletion(uid: String) async throws {
        // Nothing to do client-side: `onUserDeleted` deletes everything once the identity is gone.
    }
}
