import Foundation
import DisciplineCore

@MainActor
protocol AccountabilityRepository: AnyObject {
    func observeTasks(userId: String) -> AsyncThrowingStream<[AccountabilityTask], Error>
    /// Records an accepted skip: the skipped occurrence and its task, together.
    func recordSkip(_ plan: SkipPlan) throws
    /// Saves a client-side change to an open task (e.g. pending → inProgress).
    func save(_ task: AccountabilityTask) throws
}
