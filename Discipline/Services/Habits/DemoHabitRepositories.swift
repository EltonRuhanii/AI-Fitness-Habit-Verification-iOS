import Foundation
import DisciplineCore

/// A locally persisted, observable collection for demo mode. Mirrors the semantics of a
/// Firestore collection closely enough for the app: keyed by ID, idempotent writes, live updates.
@MainActor
final class DemoCollection<Value: Codable & Identifiable> where Value.ID == String {
    private let store: LocalJSONStore<[String: Value]>
    private var values: [String: Value]
    private var observers: [UUID: (filter: (Value) -> Bool, continuation: AsyncThrowingStream<[Value], Error>.Continuation)] = [:]

    init(fileName: String) {
        store = LocalJSONStore(fileName: fileName)
        values = store.load() ?? [:]
    }

    func observe(where filter: @escaping (Value) -> Bool) -> AsyncThrowingStream<[Value], Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            observers[id] = (filter, continuation)
            continuation.yield(values.values.filter(filter))
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.observers[id] = nil }
            }
        }
    }

    func remove(id: String) throws {
        values[id] = nil
        try store.save(values)
        for observer in observers.values {
            observer.continuation.yield(values.values.filter(observer.filter))
        }
    }

    func snapshot() -> [Value] {
        Array(values.values)
    }

    func upsert(_ value: Value) throws {
        values[value.id] = value
        try store.save(values)
        for observer in observers.values {
            observer.continuation.yield(values.values.filter(observer.filter))
        }
    }
}

@MainActor
final class DemoHabitRepository: HabitRepository {
    private let collection = DemoCollection<Habit>(fileName: "demo-habits.json")

    func observeHabits(userId: String) -> AsyncThrowingStream<[Habit], Error> {
        collection.observe { $0.userId == userId }
    }

    func save(_ habit: Habit) throws {
        try collection.upsert(habit)
    }

    func all() -> [Habit] {
        collection.snapshot()
    }
}

@MainActor
final class DemoCompletionRepository: CompletionRepository {
    private let collection = DemoCollection<HabitCompletion>(fileName: "demo-completions.json")

    func observeCompletions(userId: String, from: DayKey) -> AsyncThrowingStream<[HabitCompletion], Error> {
        collection.observe { $0.userId == userId && $0.day >= from }
    }

    func save(_ completion: HabitCompletion) throws {
        try collection.upsert(completion)
    }
}
