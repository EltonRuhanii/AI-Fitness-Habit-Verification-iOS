import XCTest
@testable import DisciplineCore

final class AccountabilityTests: XCTestCase {
    let calendar = Calendar.disciplineCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let day = DayKey(year: 2026, month: 9, day: 28)
    let accepted = Date(timeIntervalSince1970: 1_790_000_000)

    func gym(consequence: AccountabilityTemplate? = AccountabilityTemplate(type: .pushUps, target: 50)) -> Habit {
        Habit(id: "gym", userId: "u", name: "Gym", category: .gym, frequency: .weekly, targetCount: 4,
              startDate: day.adding(days: -7, calendar: calendar), requiresEvidence: true, skipConsequence: consequence)
    }

    func session(_ task: AccountabilityTask, valid: Int, completedAt: Date?) -> ExerciseSession {
        ExerciseSession(userId: "u", accountabilityTaskId: task.id, exercise: .pushUps, completedAt: completedAt,
                        targetReps: task.target, validReps: valid, engineVersion: "test")
    }

    // MARK: Task creation / acceptance

    func testSkipCreatesTaskAndAccountabilityCompletion() throws {
        let plan = try AccountabilityPlanner.planSkip(habit: gym(), day: day, condition: .aiAssisted, existing: [],
                                                      calendar: calendar, acceptedAt: accepted, taskId: "t1")
        XCTAssertEqual(plan.task.title, "50 Push-Ups")
        XCTAssertEqual(plan.task.target, 50)
        XCTAssertEqual(plan.task.status, .pending)
        XCTAssertEqual(plan.task.progress, 0)
        XCTAssertEqual(plan.task.acceptedAt, accepted)
        XCTAssertEqual(plan.task.deadline, accepted.addingTimeInterval(24 * 3600))
        XCTAssertEqual(plan.task.sourceCompletionId, plan.completion.id)

        XCTAssertEqual(plan.completion.status, .accountabilityRequired)
        XCTAssertEqual(plan.completion.method, .accountabilityExercise)
        XCTAssertEqual(plan.completion.accountabilityTaskId, "t1")
        XCTAssertEqual(plan.completion.trackingCondition, .aiAssisted)
    }

    func testDefaultConsequenceWhenHabitHasNone() {
        XCTAssertEqual(AccountabilityPlanner.consequence(for: gym(consequence: nil))?.target, 50)
    }

    func testUnsupportedExerciseFallsBackToPushUps() {
        let consequence = AccountabilityPlanner.consequence(for: gym(consequence: AccountabilityTemplate(type: .squats, target: 30)))
        XCTAssertEqual(consequence?.type, .pushUps)
    }

    func testSkippingRespectsRulesAndHabitKind() {
        let noSkipping = ChallengeRules(allowSkipping: false)
        XCTAssertThrowsError(try AccountabilityPlanner.planSkip(habit: gym(), day: day, condition: .manual, existing: [],
                                                                rules: noSkipping, calendar: calendar)) {
            XCTAssertEqual($0 as? SkipPlanError, .skippingNotAllowed)
        }
        let reading = Habit(id: "r", userId: "u", name: "Reading", category: .reading, frequency: .weekly, unit: .pages,
                            targetCount: 100, startDate: day)
        XCTAssertFalse(AccountabilityPlanner.canSkip(reading, on: day, completions: [], calendar: calendar))
    }

    func testCannotSkipAfterCompletingOrSkippingToday() throws {
        let habit = gym()
        let done = try CompletionPlanner.makeSelfReport(habit: habit, day: day, quantity: 1, condition: .manual, existing: [], calendar: calendar)
        XCTAssertThrowsError(try AccountabilityPlanner.planSkip(habit: habit, day: day, condition: .manual, existing: [done], calendar: calendar)) {
            XCTAssertEqual($0 as? SkipPlanError, .alreadyResolvedToday)
        }
        let skip = try AccountabilityPlanner.planSkip(habit: habit, day: day, condition: .manual, existing: [], calendar: calendar)
        XCTAssertFalse(AccountabilityPlanner.canSkip(habit, on: day, completions: [skip.completion], calendar: calendar))
        XCTAssertFalse(CompletionPlanner.canLogSession(for: habit, on: day, completions: [skip.completion], calendar: calendar),
                       "a skip occupies the day's slot")
    }

    // MARK: Completion / failure

    func testTaskCompletesWhenValidRepsReachTargetBeforeDeadline() throws {
        let task = try AccountabilityPlanner.planSkip(habit: gym(), day: day, condition: .manual, existing: [],
                                                      calendar: calendar, acceptedAt: accepted).task
        let during = accepted.addingTimeInterval(3600)
        let partial = session(task, valid: 30, completedAt: during)
        XCTAssertEqual(AccountabilityLifecycle.evaluate(task, sessions: [partial], now: during), .pending)
        let rest = session(task, valid: 20, completedAt: during.addingTimeInterval(600))
        XCTAssertEqual(AccountabilityLifecycle.evaluate(task, sessions: [partial, rest], now: during), .completed)
        XCTAssertEqual(AccountabilityLifecycle.completionStatus(for: .completed), .resolved)
    }

    func testRepsAfterDeadlineDoNotCountAndTaskExpires() throws {
        let task = try AccountabilityPlanner.planSkip(habit: gym(), day: day, condition: .manual, existing: [],
                                                      calendar: calendar, acceptedAt: accepted).task
        let late = task.deadline.addingTimeInterval(60)
        let lateSession = session(task, valid: 50, completedAt: late)
        XCTAssertEqual(AccountabilityLifecycle.evaluate(task, sessions: [lateSession], now: late), .expired)
        XCTAssertEqual(AccountabilityLifecycle.effectiveStatus(of: task, now: late), .expired)
        XCTAssertEqual(AccountabilityLifecycle.completionStatus(for: .expired), .failed)
    }

    func testTerminalStatusIsFinal() throws {
        var task = try AccountabilityPlanner.planSkip(habit: gym(), day: day, condition: .manual, existing: [],
                                                      calendar: calendar, acceptedAt: accepted).task
        task.status = .completed
        XCTAssertEqual(AccountabilityLifecycle.evaluate(task, sessions: [], now: task.deadline.addingTimeInterval(9999)), .completed)
        XCTAssertEqual(AccountabilityLifecycle.effectiveStatus(of: task, now: task.deadline.addingTimeInterval(9999)), .completed)
    }

    func testSessionsForOtherTasksAreIgnored() throws {
        let task = try AccountabilityPlanner.planSkip(habit: gym(), day: day, condition: .manual, existing: [],
                                                      calendar: calendar, acceptedAt: accepted).task
        let other = ExerciseSession(userId: "u", accountabilityTaskId: "other", exercise: .pushUps, completedAt: accepted,
                                    targetReps: 50, validReps: 50, engineVersion: "test")
        XCTAssertEqual(AccountabilityLifecycle.validRepetitions(for: task, sessions: [other]), 0)
    }

    // MARK: Dashboard + counting

    func testDashboardShowsAccountabilityDueAndResolvedCounts() throws {
        let habit = gym()
        var skip = try AccountabilityPlanner.planSkip(habit: habit, day: day, condition: .manual, existing: [], calendar: calendar).completion
        var items = TodayCommitments.build(habits: [habit], completions: [skip], today: day, condition: .manual, calendar: calendar)
        XCTAssertEqual(items.first?.state, .accountabilityDue)
        XCTAssertEqual(items.first?.progress.achieved, 0, "an unresolved skip doesn't count toward the target")

        skip.status = .resolved
        items = TodayCommitments.build(habits: [habit], completions: [skip], today: day, condition: .manual, calendar: calendar)
        XCTAssertEqual(items.first?.progress.achieved, 1, "a resolved skip counts as one occurrence")
    }
}
