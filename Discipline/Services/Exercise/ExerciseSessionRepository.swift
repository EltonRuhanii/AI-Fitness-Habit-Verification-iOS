import Foundation
import FirebaseFirestore
import DisciplineCore

@MainActor
protocol ExerciseSessionRepository: AnyObject {
    /// Stores a finished session. Task progress and completion are then decided by the backend
    /// (the `onExerciseSessionCreated` function, or the demo backend in demo mode).
    func save(_ session: ExerciseSession) throws
}

@MainActor
final class FirestoreExerciseSessionRepository: ExerciseSessionRepository {
    private let db: Firestore
    private let monitor: SyncMonitor

    init(db: Firestore = Firestore.firestore(), monitor: SyncMonitor) {
        self.db = db
        self.monitor = monitor
    }

    /// Local-first: if the participant is offline the session is kept and synced later; the
    /// server then evaluates it against the deadline using its own receive time.
    func save(_ session: ExerciseSession) throws {
        try FirestoreSupport.set(session, at: db.collection(Collections.exerciseSessions).document(session.id), monitor: monitor)
    }
}

@MainActor
final class DemoExerciseSessionRepository: ExerciseSessionRepository {
    private let sessions = DemoCollection<ExerciseSession>(fileName: "demo-exercise-sessions.json")
    private let accountability: DemoAccountabilityRepository

    init(accountability: DemoAccountabilityRepository) {
        self.accountability = accountability
    }

    func save(_ session: ExerciseSession) throws {
        try sessions.upsert(session)
        let forTask = sessions.snapshot().filter { $0.accountabilityTaskId == session.accountabilityTaskId }
        try accountability.apply(sessions: forTask, toTaskId: session.accountabilityTaskId)
    }
}
