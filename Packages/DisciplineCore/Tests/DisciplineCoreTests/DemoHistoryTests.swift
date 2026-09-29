import XCTest
@testable import DisciplineCore

final class DemoHistoryTests: XCTestCase {
    let calendar = Calendar.disciplineCalendar(timeZone: TimeZone(identifier: "UTC")!)

    func summary(_ history: DemoHistory, today: DayKey) -> StreakSummary {
        StreakCalculator.summarizeHistory(habits: history.habits, completions: history.completions, tasks: history.tasks,
                                          challenges: [], from: today.adding(days: -120, calendar: calendar), today: today,
                                          now: today.startDate(calendar: calendar).addingTimeInterval(12 * 3600), calendar: calendar)
    }

    func testHistoryHasBrokenStreakThenLongStreakForEveryWeekday() {
        // Run for each weekday so "today" never lands on a pattern the history can't support.
        let monday = DayKey(year: 2026, month: 9, day: 28)
        for offset in 0..<7 {
            let today = monday.adding(days: offset, calendar: calendar)
            let history = DemoHistoryGenerator.generate(userId: "u", condition: .aiAssisted, today: today, calendar: calendar)
            let result = summary(history, today: today)
            let outcomes = result.days.map(\.resolution.outcome)
            XCTAssertEqual(outcomes.filter { $0 == .failed }.count, 2, "exactly the two broken days (today \(today))")
            XCTAssertGreaterThanOrEqual(result.current, 21, "three clean weeks since the break (today \(today))")
            XCTAssertEqual(result.longest, result.current)
            // Nothing is logged today: it's on track (nothing due yet) or pending, never failed.
            XCTAssertNotEqual(outcomes.last, .failed)
            XCTAssertEqual(result.days.last?.resolution.day, today)
            XCTAssertFalse(history.completions.contains { $0.day >= today })
        }
    }

    func testAIAssistedHistoryMixesVerificationOutcomes() {
        let today = DayKey(year: 2026, month: 9, day: 30)
        let history = DemoHistoryGenerator.generate(userId: "u", condition: .aiAssisted, today: today, calendar: calendar)
        let statuses = history.completions.map(\.status)
        XCTAssertGreaterThan(statuses.filter { $0 == .verified }.count, 30)
        XCTAssertEqual(statuses.filter { $0 == .rejected }.count, 1)
        XCTAssertEqual(statuses.filter { $0 == .uncertain }.count, 1)
        XCTAssertEqual(statuses.filter { $0 == .resolved }.count, 1)
        XCTAssertEqual(history.tasks.count, 1)
        XCTAssertEqual(history.tasks.first?.status, .completed)
        XCTAssertEqual(history.sessions.first?.validReps, 50)
        XCTAssertEqual(Set(history.completions.map(\.id)).count, history.completions.count, "unique ids")
        XCTAssertTrue(history.completions.allSatisfy { $0.trackingCondition == .aiAssisted })
    }

    func testManualHistorySelfReports() {
        let today = DayKey(year: 2026, month: 9, day: 30)
        let history = DemoHistoryGenerator.generate(userId: "u", condition: .manual, today: today, calendar: calendar)
        XCTAssertFalse(history.completions.contains { $0.status == .verified || $0.status == .rejected || $0.status == .uncertain })
        XCTAssertTrue(history.completions.allSatisfy { $0.trackingCondition == .manual })
        XCTAssertEqual(summary(history, today: today).days.filter { $0.resolution.outcome == .failed }.count, 2)
    }
}
