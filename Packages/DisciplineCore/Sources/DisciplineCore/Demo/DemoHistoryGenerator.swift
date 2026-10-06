import Foundation

/// Generated history for demonstrations. Only ever written in demo mode (the study backend's
/// security rules would reject its server-only statuses anyway).
public struct DemoHistory: Sendable {
    public let challenge: Challenge
    public let habits: [Habit]
    public let completions: [HabitCompletion]
    public let tasks: [AccountabilityTask]
    public let sessions: [ExerciseSession]
}

/// Deterministic history of a 90-day challenge that started `elapsedDays` ago:
/// - routine: workouts Mon/Tue/Thu/Fri, runs Wed/Sat, cold plunge Tue/Thu/Sat, and two skills
///   (Guitar, Spanish) for 60 minutes every day;
/// - two missed days (Spanish on challenge day 9, Guitar on day 21), each resetting the streak,
///   so the current streak is `elapsedDays - 21` days;
/// - AI-assisted evidence: verified, one rejected-then-verified retry, one uncertain result;
/// - two skips resolved with camera-counted push-ups (a skill and a workout).
/// Today is left empty (pending). Outcomes don't depend on which weekday today is.
public enum DemoHistoryGenerator {
    public static let elapsedDays = 45
    static let missedSpanishOffset = 8
    static let missedGuitarOffset = 20
    static let skippedGuitarOffset = 30

    public static let setup = RoutineSetup(
        workoutWeekdays: [2, 3, 5, 6],   // Mon, Tue, Thu, Fri
        runWeekdays: [4, 7],             // Wed, Sat
        skills: ["Guitar", "Spanish"],
        extras: [RoutineExtra(id: "cold-plunge", name: "Cold Plunge", category: .recovery, weekdays: [3, 5, 7])]
    )

    public static func generate(userId: String, condition: TrackingCondition, today: DayKey, calendar: Calendar) -> DemoHistory {
        let start = today.adding(days: -elapsedDays, calendar: calendar)
        let startTime = start.startDate(calendar: calendar).addingTimeInterval(8 * 3600)
        let challengeId = "demo-challenge"
        let challenge = Challenge(
            id: challengeId, ownerId: userId, name: RoutinePlanner.challengeName,
            description: RoutinePlanner.description(of: setup, calendar: calendar),
            durationDays: RoutinePlanner.durationDays, startDate: start, rules: RoutinePlanner.rules,
            createdAt: startTime, rulesAcceptedAt: startTime, templateId: RoutinePlanner.templateId, calendar: calendar
        )
        var habits = (try? RoutinePlanner.habits(for: setup, userId: userId, startDate: start)) ?? []
        for index in habits.indices {
            habits[index].id = "demo-\(habits[index].name.lowercased().replacingOccurrences(of: " ", with: "-"))"
            habits[index].challengeId = challengeId
            habits[index].endDate = challenge.endDate
        }
        func habit(_ name: String) -> Habit? { habits.first { $0.name == name } }

        var completions: [HabitCompletion] = []
        var tasks: [AccountabilityTask] = []
        var sessions: [ExerciseSession] = []
        var perDayIndex: [String: Int] = [:]
        var rejectedRunDone = false
        var uncertainPlungeDone = false
        var workoutSkipDone = false

        func add(_ habit: Habit, _ day: DayKey, status: CompletionStatus, method: CompletionMethod,
                 quantity: Int = 1, taskId: String? = nil, id: String? = nil) {
            let key = "\(habit.id)_\(day)"
            let index = perDayIndex[key, default: 0]
            perDayIndex[key] = index + 1
            let time = day.startDate(calendar: calendar).addingTimeInterval(TimeInterval(17 * 3600 + index * 900))
            completions.append(HabitCompletion(
                id: id ?? "\(key)_\(index)", userId: userId, habitId: habit.id, challengeId: challengeId, day: day,
                quantity: quantity, status: status, method: method, trackingCondition: condition,
                accountabilityTaskId: taskId, createdAt: time, updatedAt: time, clientRequestId: "demo-\(key)-\(index)"
            ))
        }

        func evidence(_ habit: Habit, _ day: DayKey, status: CompletionStatus = .verified, quantity: Int = 1) {
            if condition == .aiAssisted {
                add(habit, day, status: status, method: .photoVerification, quantity: quantity)
            } else {
                add(habit, day, status: .selfReported, method: .selfReport, quantity: quantity)
            }
        }

        func resolvedSkip(_ habit: Habit, _ day: DayKey, quantity: Int) {
            let taskId = "demo-task-\(habit.id)-\(day)"
            let accepted = day.startDate(calendar: calendar).addingTimeInterval(9 * 3600)
            let completionId = habit.unit == .sessions ? "\(habit.id)_\(day)_0" : "\(habit.id)_\(day)_skip"
            add(habit, day, status: .resolved, method: .accountabilityExercise, quantity: quantity, taskId: taskId, id: completionId)
            let session = ExerciseSession(
                id: "demo-session-\(habit.id)-\(day)", userId: userId, accountabilityTaskId: taskId, exercise: .pushUps,
                startedAt: accepted.addingTimeInterval(9 * 3600), completedAt: accepted.addingTimeInterval(9 * 3600 + 420),
                targetReps: 50, validReps: 50, invalidReps: 4, verificationMethod: .visionFaceProximity,
                engineVersion: "pushup-face-v1", outcome: .completed
            )
            sessions.append(session)
            tasks.append(AccountabilityTask(
                id: taskId, userId: userId, sourceHabitId: habit.id, sourceCompletionId: completionId, day: day,
                title: "50 Push-Ups", description: "Accountability for skipping \(habit.name) on \(day).", type: .pushUps,
                target: 50, progress: 50, status: .completed, createdAt: accepted, acceptedAt: accepted,
                deadline: accepted.addingTimeInterval(24 * 3600), completedAt: session.completedAt,
                exerciseSessionIds: [session.id]
            ))
        }

        var day = start
        while day < today {
            let offset = start.days(to: day, calendar: calendar)
            let weekday = day.weekday(calendar: calendar)

            if let workout = habit("Workout"), workout.scheduledWeekdays.contains(weekday) {
                if offset > skippedGuitarOffset && !workoutSkipDone {
                    resolvedSkip(workout, day, quantity: 1)
                    workoutSkipDone = true
                } else {
                    evidence(workout, day)
                }
            }
            if let run = habit("Run"), run.scheduledWeekdays.contains(weekday) {
                if !rejectedRunDone && condition == .aiAssisted {
                    evidence(run, day, status: .rejected)   // retried and verified the same day
                    rejectedRunDone = true
                }
                evidence(run, day)
            }
            if let plunge = habit("Cold Plunge"), plunge.scheduledWeekdays.contains(weekday) {
                let uncertain = offset > 10 && !uncertainPlungeDone
                evidence(plunge, day, status: uncertain ? .uncertain : .verified)
                if uncertain { uncertainPlungeDone = true }
            }
            if let guitar = habit("Guitar") {
                if offset == skippedGuitarOffset {
                    resolvedSkip(guitar, day, quantity: RoutinePlanner.minimumSkillMinutes)
                } else if offset != missedGuitarOffset {
                    // Some days in two shorter sessions.
                    if offset % 3 == 0 {
                        evidence(guitar, day, quantity: 30)
                        evidence(guitar, day, quantity: 35)
                    } else {
                        evidence(guitar, day, quantity: 60)
                    }
                }
            }
            if let spanish = habit("Spanish"), offset != missedSpanishOffset {
                evidence(spanish, day, quantity: offset % 4 == 0 ? 75 : 60)
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return DemoHistory(challenge: challenge, habits: habits, completions: completions, tasks: tasks, sessions: sessions)
    }
}
