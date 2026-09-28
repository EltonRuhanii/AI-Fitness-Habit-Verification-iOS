import Foundation
import FirebaseFirestore
import DisciplineCore

/// Tasks are created and started by the client. Completion and expiry are written only by
/// Cloud Functions (enforced by security rules), so a client can't mark its own task done.
@MainActor
final class FirestoreAccountabilityRepository: AccountabilityRepository {
    private let db: Firestore
    private let monitor: SyncMonitor

    init(db: Firestore = Firestore.firestore(), monitor: SyncMonitor) {
        self.db = db
        self.monitor = monitor
    }

    func observeTasks(userId: String) -> AsyncThrowingStream<[AccountabilityTask], Error> {
        FirestoreSupport.stream(
            db.collection(Collections.accountabilityTasks).whereField("userId", isEqualTo: userId),
            as: AccountabilityTask.self
        )
    }

    func recordSkip(_ plan: SkipPlan) throws {
        let batch = db.batch()
        do {
            batch.setData(try Firestore.Encoder().encode(plan.task),
                          forDocument: db.collection(Collections.accountabilityTasks).document(plan.task.id))
            batch.setData(try Firestore.Encoder().encode(plan.completion),
                          forDocument: db.collection(Collections.habitCompletions).document(plan.completion.id))
        } catch {
            throw AppError.unknown("Could not prepare the skip for saving.")
        }
        // Local-first like other writes: applied to the cache immediately, synced in the background.
        monitor.writeStarted()
        batch.commit { [monitor] error in
            Task { @MainActor in monitor.writeFinished(error: error) }
        }
    }

    func save(_ task: AccountabilityTask) throws {
        try FirestoreSupport.set(task, at: db.collection(Collections.accountabilityTasks).document(task.id), monitor: monitor)
    }
}
