import XCTest
@testable import DisciplineCore

final class StreakTests: XCTestCase {
    let calendar = Calendar.disciplineCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    // Monday 2026-09-21 … Sunday 2026-09-27
    let monday = DayKey(year: 2026, month: 9, day: 21)
    func d(_ offset: Int) -> DayKey { monday.adding(days: offset, calendar: calendar) }

    func habit(_ id: String, _ frequency: HabitFrequency, target: Int = 1, unit: HabitUnit = .sessions,
               weekdays: [Int] = [], start: Int = -30, end: Int? = nil, required: Bool = true, active: Bool = true) -> Habit {
        Habit(id: id, userId: "u", name: id, category: .gym, frequency: frequency, unit: unit, targetCount: target,
              scheduledWeekdays: weekdays, startDate: d(start), endDate: end.map { d($0) }, isRequired: required, isActive: active)
    }

    func done(_ habitId: String, _ day: DayKey, _ status: CompletionStatus = .selfReported, quantity: Int = 1,
              task: String? = nil) -> HabitCompletion {
        HabitCompletion(userId: "u", habitId: habitId, day: day, quantity: quantity, status: status,
                        method: .selfReport, trackingCondition: .manual, accountabilityTaskId: task)
    }

    func resolve(_ day: DayKey, _ habits: [Habit], _ completions: [HabitCompletion], tasks: [AccountabilityTask] = [],
                 rules: ChallengeRules = ChallengeRules(), today: DayKey? = nil, now: Date = Date()) -> DayResolution {
        DayResolver.resolve(day: day, habits: habits, completions: completions, tasks: tasks, rules: rules,
                            today: today ?? d(20), now: now, calendar: calendar)
    }

    // MARK: Daily / custom

    func testDailyHabitDoneIsSuccessfulMissedIsFailedTodayIsPending() {
        let h = habit("read", .daily)
        XCTAssertEqual(resolve(d(0), [h], [done("read", d(0))]).outcome, .successful)
        XCTAssertEqual(resolve(d(1), [h], []).outcome, .failed)
        XCTAssertEqual(resolve(d(2), [h], [], today: d(2)).outcome, .pending, "today isn't over")
    }

    func testDailyQuantityNeedsFullAmount() {
        let h = habit("read", .daily, target: 20, unit: .pages)
        XCTAssertEqual(resolve(d(0), [h], [done("read", d(0), quantity: 15)]).outcome, .failed)
        XCTAssertEqual(resolve(d(0), [h], [done("read", d(0), quantity: 15), done("read", d(0), quantity: 5)]).outcome, .successful)
    }

    func testCustomHabitOnlyDueOnScheduledDays() {
        let h = habit("run", .custom, weekdays: [2]) // Mondays
        XCTAssertEqual(resolve(d(0), [h], []).outcome, .failed)
        let tuesday = resolve(d(1), [h], [])
        XCTAssertEqual(tuesday.outcome, .successful, "nothing due: on track")
        XCTAssertTrue(tuesday.due.isEmpty)
    }

    func testNoHabitsInEffectIsRestDay() {
        let h = habit("gym", .daily, start: 5)
        let before = resolve(d(0), [h], [])
        XCTAssertEqual(before.outcome, .restDay)
        XCTAssertFalse(before.hasCommitments)
    }

    func testOptionalHabitsDontAffectOutcome() {
        let optional = habit("extra", .daily, required: false)
        XCTAssertEqual(resolve(d(0), [optional], []).outcome, .restDay)
    }

    // MARK: Weekly feasibility rule

    func testWeeklySessionsBecomeDueOnlyWhenTight() {
        let gym = habit("gym", .weekly, target: 4)
        // Nothing done: Mon–Wed on track; Thursday (4 needed, 4 days left) is due.
        XCTAssertEqual(resolve(d(0), [gym], []).outcome, .successful)
        XCTAssertEqual(resolve(d(2), [gym], []).outcome, .successful)
        XCTAssertEqual(resolve(d(3), [gym], []).outcome, .failed)
        XCTAssertEqual(resolve(d(3), [gym], [done("gym", d(3))]).outcome, .successful)
    }

    func testWeeklyTargetMetEarlyIsNeverDue() {
        let gym = habit("gym", .weekly, target: 4)
        let week = (0..<4).map { done("gym", d($0)) }
        for offset in 4...6 {
            let resolution = resolve(d(offset), [gym], week)
            XCTAssertEqual(resolution.outcome, .successful)
            XCTAssertTrue(resolution.due.isEmpty)
        }
    }

    func testAfterFallingBehindEachRemainingDayNeedsASession() {
        let gym = habit("gym", .weekly, target: 4)
        // Missed Thursday; Friday is infeasible for the full target, but a session still resolves the day.
        XCTAssertEqual(resolve(d(4), [gym], [done("gym", d(4))]).outcome, .successful)
        XCTAssertEqual(resolve(d(4), [gym], []).outcome, .failed)
    }

    func testWeeklyQuantityDueOnLastDayOfWeek() {
        let reading = habit("read", .weekly, target: 100, unit: .pages)
        let partial = [done("read", d(1), quantity: 60)]
        XCTAssertEqual(resolve(d(5), [reading], partial).outcome, .successful, "Saturday: can still catch up")
        XCTAssertEqual(resolve(d(6), [reading], partial).outcome, .failed)
        XCTAssertEqual(resolve(d(6), [reading], partial + [done("read", d(6), quantity: 40)]).outcome, .successful)
    }

    func testWeeklyHabitStartingMidWeekNeedsOneSessionPerRemainingDay() {
        let gym = habit("gym", .weekly, target: 4, start: 5) // starts Saturday
        XCTAssertEqual(resolve(d(5), [gym], []).outcome, .failed)
        XCTAssertEqual(resolve(d(5), [gym], [done("gym", d(5))]).outcome, .successful)
    }

    // MARK: Verification and accountability

    func testPendingVerificationKeepsDayPendingAfterItEnds() {
        let gym = habit("gym", .daily)
        XCTAssertEqual(resolve(d(0), [gym], [done("gym", d(0), .pendingVerification)]).outcome, .pending)
        XCTAssertEqual(resolve(d(0), [gym], [done("gym", d(0), .verified)]).outcome, .successful)
        XCTAssertEqual(resolve(d(0), [gym], [done("gym", d(0), .rejected)]).outcome, .failed)
    }

    func testUncertainFollowsChallengePolicy() {
        let gym = habit("gym", .daily)
        let uncertain = [done("gym", d(0), .uncertain)]
        XCTAssertEqual(resolve(d(0), [gym], uncertain).outcome, .successful)
        let strict = ChallengeRules(uncertainPolicy: .requiresResubmission)
        XCTAssertEqual(resolve(d(0), [gym], uncertain, rules: strict).outcome, .failed)
    }

    func testSkipWithAccountabilityLifecycle() {
        let gym = habit("gym", .daily)
        let accepted = Date(timeIntervalSince1970: 1_790_000_000)
        let task = AccountabilityTask(id: "t1", userId: "u", sourceHabitId: "gym", sourceCompletionId: "c", day: d(0),
                                      title: "50 Push-Ups", description: "", type: .pushUps, target: 50,
                                      acceptedAt: accepted, deadline: accepted.addingTimeInterval(86_400))
        let skip = done("gym", d(0), .accountabilityRequired, task: "t1")
        XCTAssertEqual(resolve(d(0), [gym], [skip], tasks: [task], now: accepted.addingTimeInterval(3600)).outcome, .pending,
                       "task still open after the day ended")
        XCTAssertEqual(resolve(d(0), [gym], [skip], tasks: [task], now: accepted.addingTimeInterval(90_000)).outcome, .failed,
                       "task overdue")
        XCTAssertEqual(resolve(d(0), [gym], [done("gym", d(0), .resolved)]).outcome, .successful)
        XCTAssertEqual(resolve(d(0), [gym], [done("gym", d(0), .failed)]).outcome, .failed)
    }

    func testRequireAllHabitsFalseNeedsOneResolved() {
        let rules = ChallengeRules(requireAllHabits: false)
        let habits = [habit("a", .daily), habit("b", .daily)]
        XCTAssertEqual(resolve(d(0), habits, [done("a", d(0))], rules: rules).outcome, .successful)
        XCTAssertEqual(resolve(d(0), habits, [done("a", d(0))]).outcome, .failed)
    }

    func testArchivedHabitKeepsHistoryButIsNotDueAfterEnd() {
        let archived = habit("gym", .daily, end: 2, active: false)
        XCTAssertEqual(resolve(d(1), [archived], []).outcome, .failed)
        XCTAssertEqual(resolve(d(3), [archived], []).outcome, .restDay)
        let legacy = habit("old", .daily, active: false)
        XCTAssertEqual(resolve(d(1), [legacy], []).outcome, .restDay, "archived without end date: excluded")
    }

    // MARK: Streaks

    private func resolution(_ offset: Int, _ outcome: DayOutcome) -> DayResolution {
        DayResolution(day: d(offset), outcome: outcome, due: [], hasCommitments: outcome != .restDay)
    }

    func testStreakIncrementsAndBreaks() {
        let summary = StreakCalculator.compute([
            resolution(0, .successful), resolution(1, .successful), resolution(2, .successful),
            resolution(3, .failed), resolution(4, .successful), resolution(5, .successful)
        ])
        XCTAssertEqual(summary.current, 2)
        XCTAssertEqual(summary.longest, 3)
        XCTAssertEqual(summary.days[3].streakBefore, 3)
        XCTAssertEqual(summary.days[3].streakAfter, 0)
    }

    func testPauseStreakHoldsOnFailure() {
        let summary = StreakCalculator.compute([resolution(0, .successful), resolution(1, .failed), resolution(2, .successful)],
                                               missedDayBehavior: .pauseStreak)
        XCTAssertEqual(summary.current, 2)
    }

    func testPendingAndRestDaysAreNeutral() {
        let summary = StreakCalculator.compute([
            resolution(0, .successful), resolution(1, .restDay), resolution(2, .pending), resolution(3, .successful)
        ])
        XCTAssertEqual(summary.current, 2)
        XCTAssertEqual(summary.days[2].streakAfter, 1)
    }

    func testOrderIndependent() {
        let summary = StreakCalculator.compute([resolution(2, .successful), resolution(0, .failed), resolution(1, .successful)])
        XCTAssertEqual(summary.current, 2)
    }

    func testMilestones() {
        let summary = StreakSummary(current: 8, longest: 15, days: [])
        XCTAssertEqual(summary.nextMilestone, 14)
        XCTAssertEqual(summary.reachedMilestones, [3, 7, 14])
        XCTAssertNil(StreakSummary(current: 120, longest: 120, days: []).nextMilestone)
    }

    func testSummarizeEndToEnd() {
        // Daily habit from Monday; done Mon–Wed, missed Thu, done Fri; today is Saturday (pending).
        let h = habit("read", .daily, start: 0)
        let completions = [0, 1, 2, 4].map { done("read", d($0)) }
        let summary = StreakCalculator.summarize(habits: [h], completions: completions, tasks: [],
                                                 from: d(-100), today: d(5), calendar: calendar)
        XCTAssertEqual(summary.days.count, 6)
        XCTAssertEqual(summary.days.map(\.resolution.outcome), [.successful, .successful, .successful, .failed, .successful, .pending])
        XCTAssertEqual(summary.current, 1)
        XCTAssertEqual(summary.longest, 3)
        XCTAssertEqual(summary.today?.resolution.day, d(5))
    }
}
