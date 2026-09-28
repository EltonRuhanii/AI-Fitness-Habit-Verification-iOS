import Foundation
import DisciplineCore

/// Demo-mode accountability storage. Also plays the server's role for expiry: overdue open
/// tasks are expired and their skipped occurrence marked failed, using the same
/// `AccountabilityLifecycle` rules as the `expireAccountabilityTasks` Cloud Function.
@MainActor
final class DemoAccountabilityRepository: AccountabilityRepository {
    private let tasks = DemoCollection<AccountabilityTask>(fileName: "demo-accountability-tasks.json")
    /// Copies of skipped occurrences so they can be updated when their task resolves.
    private let skippedCompletions = DemoCollection<HabitCompletion>(fileName: "demo-skipped-completions.json")
    private let completions: CompletionRepository

    init(completions: CompletionRepository) {
        self.completions = completions
    }

    func observeTasks(userId: String) -> AsyncThrowingStream<[AccountabilityTask], Error> {
        expireOverdue()
        return tasks.observe { $0.userId == userId }
    }

    func recordSkip(_ plan: SkipPlan) throws {
        try tasks.upsert(plan.task)
        try skippedCompletions.upsert(plan.completion)
        try completions.save(plan.completion)
    }

    func save(_ task: AccountabilityTask) throws {
        try tasks.upsert(task)
    }

    /// Applies a server-style resolution to a task and its skipped occurrence.
    func resolve(taskId: String, status: AccountabilityTaskStatus, progress: Int? = nil, at date: Date = Date()) throws {
        guard var task = tasks.snapshot().first(where: { $0.id == taskId }), task.status.isOpen else { return }
        task.status = status
        if let progress { task.progress = progress }
        if status == .completed { task.completedAt = date }
        try tasks.upsert(task)

        if var completion = skippedCompletions.snapshot().first(where: { $0.id == task.sourceCompletionId }) {
            completion.status = AccountabilityLifecycle.completionStatus(for: status)
            completion.updatedAt = date
            try skippedCompletions.upsert(completion)
            try completions.save(completion)
        }
    }

    /// Server-equivalent evaluation after a session is stored: updates progress, and completes
    /// the task if valid repetitions before the deadline reach the target.
    func apply(sessions: [ExerciseSession], toTaskId taskId: String, now: Date = Date()) throws {
        guard var task = tasks.snapshot().first(where: { $0.id == taskId }), task.status.isOpen else { return }
        let progress = AccountabilityLifecycle.validRepetitions(for: task, sessions: sessions)
        let status = AccountabilityLifecycle.evaluate(task, sessions: sessions, now: now)
        if status == .completed || status == .expired {
            try resolve(taskId: taskId, status: status, progress: progress, at: now)
        } else {
            task.progress = progress
            task.exerciseSessionIds = sessions.map(\.id)
            try tasks.upsert(task)
        }
    }

    func expireOverdue(now: Date = Date()) {
        for task in tasks.snapshot() where AccountabilityLifecycle.effectiveStatus(of: task, now: now) == .expired && task.status.isOpen {
            do {
                try resolve(taskId: task.id, status: .expired, at: now)
            } catch {
                Log.data.error("Demo expiry failed for task \(task.id, privacy: .public)")
            }
        }
    }
}
