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

    func updateProfile(_ profile: UserProfile) async throws {
        do {
            // Full replace (not merge) so optional fields set back to nil are actually cleared.
            // Immutable fields are protected by security rules.
            let data = try Firestore.Encoder().encode(profile)
            try await document(profile.id).setData(data)
        } catch {
            throw AppError.from(error)
        }
    }

    func deleteProfile(uid: String) async throws {
        do {
            try await document(uid).delete()
        } catch {
            throw AppError.from(error)
        }
    }
}
