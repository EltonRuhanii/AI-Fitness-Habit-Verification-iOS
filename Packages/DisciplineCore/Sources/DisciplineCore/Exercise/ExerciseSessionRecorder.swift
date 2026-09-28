import Foundation

/// Accumulates repetitions from an engine into an `ExerciseSession` for one accountability task.
public struct ExerciseSessionRecorder: Sendable {
    public private(set) var session: ExerciseSession

    /// - Parameter alreadyCompleted: valid reps from earlier sessions for the same task; this
    ///   session's target is what remains, so several short sessions can complete a task.
    public init(task: AccountabilityTask, exercise: ExerciseKind, engineVersion: String,
                alreadyCompleted: Int = 0, startedAt: Date = Date(), id: String = UUID().uuidString) {
        session = ExerciseSession(
            id: id,
            userId: task.userId,
            accountabilityTaskId: task.id,
            exercise: exercise,
            startedAt: startedAt,
            targetReps: max(1, task.target - alreadyCompleted),
            engineVersion: engineVersion
        )
    }

    public var isTargetReached: Bool { session.validReps >= session.targetReps }
    public var remaining: Int { max(0, session.targetReps - session.validReps) }

    /// Records a finished repetition. Ignored once the session is finished.
    public mutating func record(_ outcome: RepetitionOutcome, at date: Date = Date()) {
        guard session.outcome == .inProgress else { return }
        if outcome.isValid {
            session.validReps += 1
        } else {
            session.invalidReps += 1
        }
        session.repetitions.append(RepetitionEvent(
            index: session.repetitions.count + 1,
            timestamp: date,
            isValid: outcome.isValid,
            fault: outcome.fault,
            minimumAngle: (outcome.minimumAngle * 10).rounded() / 10,
            maximumAngle: (outcome.maximumAngle * 10).rounded() / 10
        ))
    }

    /// Ends the session. The outcome is `completed` only if the target was reached;
    /// otherwise `interrupted` (camera/tracking stopped) or `abandoned` (participant ended it).
    @discardableResult
    public mutating func finish(at date: Date = Date(), interrupted: Bool = false) -> ExerciseSession {
        guard session.outcome == .inProgress else { return session }
        session.completedAt = date
        session.outcome = isTargetReached ? .completed : (interrupted ? .interrupted : .abandoned)
        return session
    }
}
