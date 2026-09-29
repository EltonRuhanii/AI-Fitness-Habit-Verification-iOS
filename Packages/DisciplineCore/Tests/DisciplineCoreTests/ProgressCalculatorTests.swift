import XCTest
@testable import DisciplineCore

final class ProgressCalculatorTests: XCTestCase {
    let calendar = Calendar.disciplineCalendar(timeZone: TimeZone(identifier: "UTC")!)

    func testSummaryOverDemoHistory() {
        let today = DayKey(year: 2026, month: 9, day: 30) // Wednesday
        let history = DemoHistoryGenerator.generate(userId: "u", condition: .aiAssisted, today: today, calendar: calendar)
        let now = today.startDate(calendar: calendar).addingTimeInterval(12 * 3600)
        let streak = StreakCalculator.summarizeHistory(habits: history.habits, completions: history.completions, tasks: history.tasks,
                                                       challenges: [], from: today.adding(days: -120, calendar: calendar),
                                                       today: today, now: now, calendar: calendar)
        let from = today.adding(days: -60, calendar: calendar)
        let summary = ProgressCalculator.summary(days: streak.days, habits: history.habits, completions: history.completions,
                                                 tasks: history.tasks, from: from, through: today, today: today, now: now,
                                                 calendar: calendar)
        XCTAssertEqual(summary.failedDays, 2)
        XCTAssertGreaterThan(summary.successfulDays, 30)
        XCTAssertEqual(summary.rejected, 1)
        XCTAssertEqual(summary.uncertain, 1)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.accountabilityCompleted, 1)
        XCTAssertEqual(summary.accountabilityOpen, 0)
        XCTAssertEqual(summary.verificationRate ?? 0, Double(summary.verified) / Double(summary.verified + 2), accuracy: 1e-9)
        XCTAssertEqual(summary.weeks.count, 8)
        XCTAssertEqual(summary.weeks.last?.weekStart, today.startOfWeek(calendar: calendar))
        XCTAssertEqual(summary.weeks.map(\.failed).reduce(0, +), 2)

        let gym = summary.habits.first { $0.habitId == history.habits[0].id }
        XCTAssertNotNil(gym)
        XCTAssertEqual(gym.map { $0.total - $0.met }, 1, "one missed gym week (the broken week)")
    }

    func testPeriodFiltering() {
        let today = DayKey(year: 2026, month: 9, day: 30)
        let habit = Habit(id: "h", userId: "u", name: "Read", category: .reading, frequency: .daily, targetCount: 1,
                          startDate: today.adding(days: -10, calendar: calendar))
        let completions = (1...10).map {
            HabitCompletion(userId: "u", habitId: "h", day: today.adding(days: -$0, calendar: calendar), status: .selfReported,
                            method: .selfReport, trackingCondition: .manual)
        }
        let streak = StreakCalculator.summarizeHistory(habits: [habit], completions: completions, tasks: [], challenges: [],
                                                       from: today.adding(days: -30, calendar: calendar), today: today, calendar: calendar)
        let lastWeek = ProgressCalculator.summary(days: streak.days, habits: [habit], completions: completions, tasks: [],
                                                  from: today.adding(days: -6, calendar: calendar), through: today, today: today,
                                                  calendar: calendar)
        XCTAssertEqual(lastWeek.successfulDays, 6)
        XCTAssertEqual(lastWeek.pendingDays, 1, "today")
        XCTAssertEqual(lastWeek.selfReported, 6)
        XCTAssertEqual(lastWeek.daySuccessRate, 1)
        XCTAssertEqual(lastWeek.habits.first?.met, 6)
        XCTAssertEqual(lastWeek.habits.first?.total, 6, "today isn't counted as a miss yet")
    }
}
