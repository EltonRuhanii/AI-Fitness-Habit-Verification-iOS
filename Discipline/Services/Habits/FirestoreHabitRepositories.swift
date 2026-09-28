import Foundation
import FirebaseFirestore
import DisciplineCore

@MainActor
final class FirestoreHabitRepository: HabitRepository {
    private let db: Firestore
    private let monitor: SyncMonitor

    init(db: Firestore = Firestore.firestore(), monitor: SyncMonitor) {
        self.db = db
        self.monitor = monitor
    }

    func observeHabits(userId: String) -> AsyncThrowingStream<[Habit], Error> {
        // Filtering on userId is required: security rules only permit queries scoped to the caller.
        FirestoreSupport.stream(db.collection(Collections.habits).whereField("userId", isEqualTo: userId), as: Habit.self)
    }

    func save(_ habit: Habit) throws {
        try FirestoreSupport.set(habit, at: db.collection(Collections.habits).document(habit.id), monitor: monitor)
    }
}

@MainActor
final class FirestoreCompletionRepository: CompletionRepository {
    private let db: Firestore
    private let monitor: SyncMonitor

    init(db: Firestore = Firestore.firestore(), monitor: SyncMonitor) {
        self.db = db
        self.monitor = monitor
    }

    func observeCompletions(userId: String, from: DayKey) -> AsyncThrowingStream<[HabitCompletion], Error> {
        // `day` is stored as yyyy-MM-dd, so lexicographic order equals chronological order.
        let query = db.collection(Collections.habitCompletions)
            .whereField("userId", isEqualTo: userId)
            .whereField("day", isGreaterThanOrEqualTo: from.description)
        return FirestoreSupport.stream(query, as: HabitCompletion.self)
    }

    func save(_ completion: HabitCompletion) throws {
        try FirestoreSupport.set(completion, at: db.collection(Collections.habitCompletions).document(completion.id), monitor: monitor)
    }
}
