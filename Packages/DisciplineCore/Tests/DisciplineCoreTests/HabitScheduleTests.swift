import XCTest
@testable import DisciplineCore

final class HabitScheduleTests: XCTestCase {
    let calendar = Calendar.disciplineCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    // Monday 2026-09-28 … Sunday 2026-10-04
    let monday = DayKey(year: 2026, month: 9, day: 28)
    var wednesday: DayKey { monday.adding(days: 2, calendar: calendar) }
    var sunday: DayKey { monday.adding(days: 6, calendar: calendar) }

    func habit(_ frequency: HabitFrequency, target: Int, unit: HabitUnit = .sessions, weekdays: [Int] = [],
               requiresEvidence: Bool = false, start: DayKey? = nil) -> Habit {
        Habit(id: "h", userId: "u", name: "Test", category: .gym, frequency: frequency, unit: unit,
              targetCount: target, scheduledWeekdays: weekdays, startDate: start ?? monday.adding(days: -60, calendar: calendar),
              requiresEvidence: requiresEvidence)
    }

    func done(_ day: DayKey, _ quantity: Int = 1, _ status: CompletionStatus = .selfReported) -> HabitCompletion {
        HabitCompletion(userId: "u", habitId: "h", day: day, quantity: quantity, status: status,
                        method: .selfReport, trackingCondition: .manual)
    }

    // MARK: Periods

    func testWeeklyPeriodIsMondayToSunday() {
        let period = HabitSchedule.period(for: habit(.weekly, target: 4), containing: wednesday, calendar: calendar)
        XCTAssertEqual(period, HabitPeriod(start: monday, end: sunday))
    }

    func testCustomHabitOnlyScheduledOnSelectedWeekdays() {
        // Calendar weekday: 2 = Monday, 4 = Wednesday
        let h = habit(.custom, target: 1, weekdays: [2, 4])
        XCTAssertTrue(HabitSchedule.isScheduled(h, on: monday, calendar: calendar))
        XCTAssertFalse(HabitSchedule.isScheduled(h, on: monday.adding(days: 1, calendar: calendar), calendar: calendar))
        XCTAssertTrue(HabitSchedule.isScheduled(h, on: wednesday, calendar: calendar))
        XCTAssertNil(HabitSchedule.progress(for: h, on: monday.adding(days: 1, calendar: calendar), completions: [], calendar: calendar))
    }

    func testNotScheduledBeforeStartDate() {
        let h = habit(.daily, target: 1, start: wednesday)
        XCTAssertFalse(HabitSchedule.isScheduled(h, on: monday, calendar: calendar))
    }

    // MARK: Daily / weekly targets

    func testDailyProgressOnlyCountsThatDay() {
        let h = habit(.daily, target: 1)
        let completions = [done(monday)]
        XCTAssertTrue(HabitSchedule.progress(for: h, on: monday, completions: completions, calendar: calendar)!.isMet)
        XCTAssertFalse(HabitSchedule.progress(for: h, on: wednesday, completions: completions, calendar: calendar)!.isMet)
    }

    func testWeeklyProgressAccumulatesAcrossWeekAndResetsNextWeek() {
        let h = habit(.weekly, target: 4)
        let completions = [done(monday), done(wednesday), done(sunday)]
        let progress = HabitSchedule.progress(for: h, on: sunday, completions: completions, calendar: calendar)!
        XCTAssertEqual(progress.achieved, 3)
        XCTAssertEqual(progress.remaining, 1)
        XCTAssertEqual(progress.fraction, 0.75, accuracy: 0.0001)
        let nextMonday = sunday.adding(days: 1, calendar: calendar)
        XCTAssertEqual(HabitSchedule.progress(for: h, on: nextMonday, completions: completions, calendar: calendar)!.achieved, 0)
    }

    func testQuantityTargetSumsPages() {
        let h = habit(.weekly, target: 100, unit: .pages)
        let completions = [done(monday, 40), done(wednesday, 20)]
        let progress = HabitSchedule.progress(for: h, on: wednesday, completions: completions, calendar: calendar)!
        XCTAssertEqual(progress.achieved, 60)
        XCTAssertFalse(progress.isMet)
        XCTAssertEqual(progress.fraction, 0.6, accuracy: 0.0001)
    }

    func testOverAchievementCapsFractionAtOne() {
        let h = habit(.weekly, target: 2)
        let completions = [done(monday), done(wednesday), done(sunday)]
        XCTAssertEqual(HabitSchedule.progress(for: h, on: monday, completions: completions, calendar: calendar)!.fraction, 1)
    }

    func testCountingPolicy() {
        let h = habit(.weekly, target: 3)
        let completions = [done(monday, 1, .verified), done(wednesday, 1, .uncertain), done(sunday, 1, .rejected)]
        XCTAssertEqual(HabitSchedule.progress(for: h, on: monday, completions: completions, calendar: calendar)!.achieved, 2)
        let strict = CountingPolicy(countsUncertain: false)
        XCTAssertEqual(HabitSchedule.progress(for: h, on: monday, completions: completions, policy: strict, calendar: calendar)!.achieved, 1)
        XCTAssertFalse(CountingPolicy().counts(.pendingVerification))
        XCTAssertFalse(CountingPolicy().counts(.skipped))
        XCTAssertFalse(CountingPolicy(countsResolved: false).counts(.resolved))
    }

    // MARK: Monthly adherence

    func testMonthlyAdherenceForDailyHabit() {
        // September 2026: 30 days, habit done on 20 of them, evaluated after month end.
        let h = habit(.daily, target: 1, start: DayKey(year: 2026, month: 9, day: 1))
        let first = DayKey(year: 2026, month: 9, day: 1)
        let completions = (0..<20).map { done(first.adding(days: $0, calendar: calendar)) }
        let result = HabitSchedule.adherence(for: h, from: first, through: DayKey(year: 2026, month: 9, day: 30),
                                             today: DayKey(year: 2026, month: 10, day: 5), completions: completions, calendar: calendar)
        XCTAssertEqual(result.met, 20)
        XCTAssertEqual(result.total, 30)
    }

    func testAdherenceDoesNotCountInProgressWeekAsMiss() {
        let h = habit(.weekly, target: 2)
        let lastMonday = monday.adding(days: -7, calendar: calendar)
        let completions = [done(lastMonday), done(lastMonday.adding(days: 1, calendar: calendar))]
        // Two weeks: last week met, current week in progress (today = Wednesday) with nothing done yet.
        let result = HabitSchedule.adherence(for: h, from: lastMonday, through: sunday, today: wednesday, completions: completions, calendar: calendar)
        XCTAssertEqual(result.met, 1)
        XCTAssertEqual(result.total, 1)
    }

    func testWeekSummary() {
        let daily = habit(.daily, target: 1)
        let summary = HabitSchedule.weekSummary(for: daily, containing: wednesday, completions: [done(monday), done(wednesday)], calendar: calendar)
        XCTAssertEqual(summary?.achieved, 2)
        XCTAssertEqual(summary?.target, 7)

        let custom = habit(.custom, target: 1, weekdays: [2, 4, 6]) // Mon, Wed, Fri
        let customSummary = HabitSchedule.weekSummary(for: custom, containing: sunday, completions: [done(monday)], calendar: calendar)
        XCTAssertEqual(customSummary?.achieved, 1)
        XCTAssertEqual(customSummary?.target, 3)

        let weekly = habit(.weekly, target: 4)
        XCTAssertEqual(HabitSchedule.weekSummary(for: weekly, containing: monday, completions: [done(sunday)], calendar: calendar)?.achieved, 1)
    }

    func testPeriodsForWeeklyHabitAcrossMonth() {
        let h = habit(.weekly, target: 1)
        let periods = HabitSchedule.periods(for: h, from: DayKey(year: 2026, month: 9, day: 1),
                                            through: DayKey(year: 2026, month: 9, day: 30), calendar: calendar)
        // Sept 1 2026 is a Tuesday: weeks starting Aug 31, Sep 7, 14, 21, 28.
        XCTAssertEqual(periods.count, 5)
        XCTAssertEqual(periods.first?.start, DayKey(year: 2026, month: 8, day: 31))
    }
}

final class CompletionPlannerTests: XCTestCase {
    let calendar = Calendar.disciplineCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let day = DayKey(year: 2026, month: 9, day: 28)

    func habit(_ frequency: HabitFrequency = .weekly, target: Int = 4, unit: HabitUnit = .sessions, evidence: Bool = false) -> Habit {
        Habit(id: "h", userId: "u", name: "Gym", category: .gym, frequency: frequency, unit: unit, targetCount: target,
              startDate: day.adding(days: -10, calendar: calendar), requiresEvidence: evidence)
    }

    func testRequirementDependsOnCondition() {
        XCTAssertEqual(CompletionPlanner.requirement(for: habit(evidence: true), condition: .aiAssisted), .evidence)
        XCTAssertEqual(CompletionPlanner.requirement(for: habit(evidence: true), condition: .manual), .selfReport)
        XCTAssertEqual(CompletionPlanner.requirement(for: habit(evidence: false), condition: .aiAssisted), .selfReport)
    }

    func testSelfReportRejectedWhenEvidenceRequired() {
        XCTAssertThrowsError(try CompletionPlanner.makeSelfReport(habit: habit(evidence: true), day: day, quantity: 1,
                                                                  condition: .aiAssisted, existing: [], calendar: calendar)) {
            XCTAssertEqual($0 as? CompletionPlanError, .evidenceRequired)
        }
    }

    func testWeeklySessionHabitAllowsOneCompletionPerDay() throws {
        let h = habit()
        let first = try CompletionPlanner.makeSelfReport(habit: h, day: day, quantity: 1, condition: .manual, existing: [], calendar: calendar)
        XCTAssertEqual(first.id, "h_2026-09-28_0")
        XCTAssertEqual(first.status, .selfReported)
        XCTAssertEqual(first.method, .selfReport)
        XCTAssertEqual(first.trackingCondition, .manual)
        XCTAssertThrowsError(try CompletionPlanner.makeSelfReport(habit: h, day: day, quantity: 1, condition: .manual, existing: [first], calendar: calendar)) {
            XCTAssertEqual($0 as? CompletionPlanError, .alreadyCompletedToday)
        }
    }

    func testDailyTargetOfTwoAllowsTwoSessions() throws {
        let h = habit(.daily, target: 2)
        let first = try CompletionPlanner.makeSelfReport(habit: h, day: day, quantity: 1, condition: .manual, existing: [], calendar: calendar)
        let second = try CompletionPlanner.makeSelfReport(habit: h, day: day, quantity: 1, condition: .manual, existing: [first], calendar: calendar)
        XCTAssertEqual(second.id, "h_2026-09-28_1")
        XCTAssertFalse(CompletionPlanner.canLogSession(for: h, on: day, completions: [first, second], calendar: calendar))
    }

    func testRejectedCompletionFreesTheSlotButGetsNewId() throws {
        let h = habit()
        var rejected = try CompletionPlanner.makeSelfReport(habit: h, day: day, quantity: 1, condition: .manual, existing: [], calendar: calendar)
        rejected.status = .rejected
        let retry = try CompletionPlanner.makeSelfReport(habit: h, day: day, quantity: 1, condition: .manual, existing: [rejected], calendar: calendar)
        XCTAssertNotEqual(retry.id, rejected.id)
    }

    func testQuantityHabitValidatesAmountAndAllowsMultipleEntries() throws {
        let h = habit(target: 100, unit: .pages)
        XCTAssertThrowsError(try CompletionPlanner.makeSelfReport(habit: h, day: day, quantity: 0, condition: .manual, existing: [], calendar: calendar))
        let a = try CompletionPlanner.makeSelfReport(habit: h, day: day, quantity: 30, condition: .manual, existing: [], calendar: calendar, requestId: "r1")
        let b = try CompletionPlanner.makeSelfReport(habit: h, day: day, quantity: 20, condition: .manual, existing: [a], calendar: calendar, requestId: "r2")
        XCTAssertEqual(a.id, "r1")
        XCTAssertEqual(b.quantity, 20)
    }

    func testTodayCommitmentsStatesAndOrdering() throws {
        let gym = Habit(id: "gym", userId: "u", name: "Gym", category: .gym, frequency: .weekly, targetCount: 1, startDate: day)
        let read = Habit(id: "read", userId: "u", name: "Reading", category: .reading, frequency: .weekly, unit: .pages, targetCount: 100, startDate: day)
        let plunge = Habit(id: "plunge", userId: "u", name: "Cold Plunge", category: .recovery, frequency: .weekly, targetCount: 3,
                           startDate: day, requiresEvidence: true)
        let completions = [
            HabitCompletion(userId: "u", habitId: "gym", day: day, status: .selfReported, method: .selfReport, trackingCondition: .aiAssisted),
            HabitCompletion(userId: "u", habitId: "read", day: day, quantity: 40, status: .selfReported, method: .selfReport, trackingCondition: .aiAssisted),
            HabitCompletion(userId: "u", habitId: "plunge", day: day, status: .pendingVerification, method: .photoVerification, trackingCondition: .aiAssisted)
        ]
        let items = TodayCommitments.build(habits: [gym, read, plunge], completions: completions, today: day, condition: .aiAssisted, calendar: calendar)
        XCTAssertEqual(items.map(\.habit.id), ["plunge", "read", "gym"], "outstanding first, alphabetical, done last")
        XCTAssertEqual(items.map(\.state), [.awaitingVerification, .inProgress, .done])
        XCTAssertEqual(items[0].requirement, .evidence)
    }

    func testEvidenceSubmissionOnlyInAIAssistedCondition() throws {
        let gym = habit(evidence: true)
        let submission = try CompletionPlanner.makeEvidenceSubmission(habit: gym, day: day, evidenceId: "e1",
                                                                      condition: .aiAssisted, existing: [], calendar: calendar)
        XCTAssertEqual(submission.status, .pendingVerification)
        XCTAssertEqual(submission.method, .photoVerification)
        XCTAssertEqual(submission.evidenceId, "e1")
        XCTAssertEqual(submission.id, "h_2026-09-28_0")

        XCTAssertThrowsError(try CompletionPlanner.makeEvidenceSubmission(habit: gym, day: day, evidenceId: "e2",
                                                                          condition: .manual, existing: [], calendar: calendar)) {
            XCTAssertEqual($0 as? CompletionPlanError, .evidenceNotApplicable)
        }
        // A pending submission occupies the day's slot; a rejected one frees it with a new ID.
        XCTAssertThrowsError(try CompletionPlanner.makeEvidenceSubmission(habit: gym, day: day, evidenceId: "e3",
                                                                          condition: .aiAssisted, existing: [submission], calendar: calendar))
        var rejected = submission
        rejected.status = .rejected
        let retry = try CompletionPlanner.makeEvidenceSubmission(habit: gym, day: day, evidenceId: "e4",
                                                                 condition: .aiAssisted, existing: [rejected], calendar: calendar)
        XCTAssertEqual(retry.id, "h_2026-09-28_1")
    }

    func testEvidenceSubmissionCarriesQuantityForPages() throws {
        let reading = habit(target: 100, unit: .pages, evidence: true)
        let submission = try CompletionPlanner.makeEvidenceSubmission(habit: reading, day: day, evidenceId: "e", quantity: 30,
                                                                      condition: .aiAssisted, existing: [], calendar: calendar)
        XCTAssertEqual(submission.quantity, 30)
        XCTAssertThrowsError(try CompletionPlanner.makeEvidenceSubmission(habit: reading, day: day, evidenceId: "e", quantity: 0,
                                                                          condition: .aiAssisted, existing: [], calendar: calendar))
    }

    func testStarterTemplateMatchesStudyExamples() {
        let habits = HabitTemplates.disciplineStarter(userId: "u", startDate: day)
        XCTAssertEqual(habits.map(\.targetDescription), ["4x / week", "2x / week", "100 pages / week", "3x / week"])
        XCTAssertEqual(habits.filter(\.requiresEvidence).count, 3)
        XCTAssertEqual(Set(habits.map(\.id)).count, 4)
    }
}
