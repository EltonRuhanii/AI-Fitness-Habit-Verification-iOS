import Foundation

/// Generated history for demonstrations. Only ever written in demo mode (the study backend's
/// security rules would reject its server-only statuses anyway).
public struct DemoHistory: Sendable {
    public let habits: [Habit]
    public let completions: [HabitCompletion]
    public let tasks: [AccountabilityTask]
    public let sessions: [ExerciseSession]
}

/// Deterministic five-week history for the starter habits:
/// - typical weeks meet every target (gym Mon/Tue/Thu/Fri, running Wed/Sat, cold plunge
///   Tue/Thu/Sat, reading 105 pages Mon/Wed/Fri/Sun);
/// - week 2 misses two gym sessions → Saturday and Sunday fail → broken streak;
/// - AI-assisted participants get verified evidence, one rejected-then-verified retry and one
///   uncertain result; manual participants self-report;
/// - the last full week replaces Friday's gym with a skip resolved by 50 camera-counted push-ups.
public enum DemoHistoryGenerator {
    public static let weeks = 5

    public static func generate(userId: String, condition: TrackingCondition, today: DayKey, calendar: Calendar) -> DemoHistory {
        let start = today.adding(days: -7 * weeks, calendar: calendar).startOfWeek(calendar: calendar)
        let habits = HabitTemplates.disciplineStarter(userId: userId, startDate: start)
        guard habits.count == 4 else { return DemoHistory(habits: habits, completions: [], tasks: [], sessions: []) }
        let (gym, running, reading, plunge) = (habits[0], habits[1], habits[2], habits[3])

        var completions: [HabitCompletion] = []
        var tasks: [AccountabilityTask] = []
        var sessions: [ExerciseSession] = []
        var perDayIndex: [String: Int] = [:]

        func add(_ habit: Habit, _ day: DayKey, status: CompletionStatus, method: CompletionMethod, quantity: Int = 1, taskId: String? = nil) {
            let key = "\(habit.id)_\(day)"
            let index = perDayIndex[key, default: 0]
            perDayIndex[key] = index + 1
            let time = day.startDate(calendar: calendar).addingTimeInterval(TimeInterval(17 * 3600 + index * 600))
            completions.append(HabitCompletion(
                id: "\(key)_\(index)", userId: userId, habitId: habit.id, day: day, quantity: quantity, status: status,
                method: method, trackingCondition: condition, accountabilityTaskId: taskId, createdAt: time, updatedAt: time,
                clientRequestId: "demo-\(key)-\(index)"
            ))
        }

        func evidence(_ habit: Habit, _ day: DayKey, override: CompletionStatus? = nil) {
            if condition == .aiAssisted && habit.requiresEvidence {
                add(habit, day, status: override ?? .verified, method: .photoVerification)
            } else {
                add(habit, day, status: .selfReported, method: .selfReport)
            }
        }

        let lastFullWeek = weeks - 1
        var day = start
        while day < today {
            let week = start.days(to: day, calendar: calendar) / 7
            let weekday = start.days(to: day, calendar: calendar) % 7 // 0 = Monday

            // Gym: Mon, Tue, Thu, Fri (week 1 stops after Tuesday → broken streak).
            if [0, 1, 3, 4].contains(weekday) && !(week == 1 && weekday >= 2) {
                if week == lastFullWeek && weekday == 4 {
                    // Skip, resolved by a completed accountability task.
                    let taskId = "demo-task-\(day)"
                    let accepted = day.startDate(calendar: calendar).addingTimeInterval(8 * 3600)
                    add(gym, day, status: .resolved, method: .accountabilityExercise, taskId: taskId)
                    let session = ExerciseSession(
                        id: "demo-session-\(day)", userId: userId, accountabilityTaskId: taskId, exercise: .pushUps,
                        startedAt: accepted.addingTimeInterval(10 * 3600), completedAt: accepted.addingTimeInterval(10 * 3600 + 420),
                        targetReps: 50, validReps: 50, invalidReps: 4, verificationMethod: .visionFaceProximity,
                        engineVersion: "pushup-face-v1", outcome: .completed
                    )
                    tasks.append(AccountabilityTask(
                        id: taskId, userId: userId, sourceHabitId: gym.id, sourceCompletionId: "\(gym.id)_\(day)_0", day: day,
                        title: "50 Push-Ups", description: "Accountability for skipping Gym on \(day).", type: .pushUps,
                        target: 50, progress: 50, status: .completed, createdAt: accepted, acceptedAt: accepted,
                        deadline: accepted.addingTimeInterval(24 * 3600), completedAt: session.completedAt,
                        exerciseSessionIds: [session.id]
                    ))
                    sessions.append(session)
                } else {
                    evidence(gym, day)
                }
            }
            // Running: Wed, Sat. The first run shows a rejected photo, retried and verified.
            if [2, 5].contains(weekday) {
                if week == 0 && weekday == 2 && condition == .aiAssisted {
                    evidence(running, day, override: .rejected)
                }
                evidence(running, day)
            }
            // Cold plunge: Tue, Thu, Sat. One uncertain AI result in week 2.
            if [1, 3, 5].contains(weekday) {
                evidence(plunge, day, override: (week == 2 && weekday == 1) ? .uncertain : nil)
            }
            // Reading: 30 + 30 + 25 + 20 = 105 pages a week.
            let pages = [0: 30, 2: 30, 4: 25, 6: 20][weekday]
            if let pages {
                add(reading, day, status: .selfReported, method: .selfReport, quantity: pages)
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return DemoHistory(habits: habits, completions: completions, tasks: tasks, sessions: sessions)
    }
}
