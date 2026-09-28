import Foundation
import DisciplineCore

@MainActor
protocol HabitRepository: AnyObject {
    /// All of the user's habits, including archived ones (needed for history and research).
    func observeHabits(userId: String) -> AsyncThrowingStream<[Habit], Error>
    /// Saves locally and synchronizes in the background.
    func save(_ habit: Habit) throws
}

@MainActor
protocol CompletionRepository: AnyObject {
    /// Completions on or after `from`.
    func observeCompletions(userId: String, from: DayKey) -> AsyncThrowingStream<[HabitCompletion], Error>
    /// Saves locally and synchronizes in the background. Saving the same ID twice is idempotent.
    func save(_ completion: HabitCompletion) throws
}
