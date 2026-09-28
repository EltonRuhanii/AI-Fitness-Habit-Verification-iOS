import Foundation
import FirebaseFirestore
import DisciplineCore

@MainActor
protocol ChallengeRepository: AnyObject {
    func observeChallenges(userId: String) -> AsyncThrowingStream<[Challenge], Error>
    /// Saves locally and syncs in the background. Security rules reject rule changes once active.
    func save(_ challenge: Challenge) throws
}

@MainActor
final class FirestoreChallengeRepository: ChallengeRepository {
    private let db: Firestore
    private let monitor: SyncMonitor

    init(db: Firestore = Firestore.firestore(), monitor: SyncMonitor) {
        self.db = db
        self.monitor = monitor
    }

    func observeChallenges(userId: String) -> AsyncThrowingStream<[Challenge], Error> {
        FirestoreSupport.stream(db.collection(Collections.challenges).whereField("ownerId", isEqualTo: userId), as: Challenge.self)
    }

    func save(_ challenge: Challenge) throws {
        try FirestoreSupport.set(challenge, at: db.collection(Collections.challenges).document(challenge.id), monitor: monitor)
    }
}

@MainActor
final class DemoChallengeRepository: ChallengeRepository {
    private let collection = DemoCollection<Challenge>(fileName: "demo-challenges.json")

    func observeChallenges(userId: String) -> AsyncThrowingStream<[Challenge], Error> {
        collection.observe { $0.ownerId == userId }
    }

    func save(_ challenge: Challenge) throws {
        // Mirror the server rule: an active challenge's rules and dates can't change.
        if let existing = collection.snapshot().first(where: { $0.id == challenge.id }), existing.status != .draft,
           existing.rules != challenge.rules || existing.startDate != challenge.startDate || existing.durationDays != challenge.durationDays {
            throw AppError.permissionDenied
        }
        try collection.upsert(challenge)
    }
}
