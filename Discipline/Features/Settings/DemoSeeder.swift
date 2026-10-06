import Foundation
import DisciplineCore

/// Writes a generated 90-day challenge, 45 days in, with its history (demo mode only; the study backend's rules would reject it).
@MainActor
enum DemoSeeder {
    static func seed(container: AppContainer, store: HabitsStore) throws -> Int {
        guard container.configuration.backend == .demo else { return 0 }
        let history = DemoHistoryGenerator.generate(userId: store.userId, condition: store.condition,
                                                    today: store.today, calendar: store.calendar)
        try container.challenges.save(history.challenge)
        for habit in history.habits { try container.habits.save(habit) }
        for task in history.tasks { try container.accountability.save(task) }
        for completion in history.completions { try container.completions.save(completion) }
        for session in history.sessions { try container.exerciseSessions.save(session) }
        return history.completions.count
    }
}
