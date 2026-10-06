import XCTest
@testable import DisciplineCore

final class DemoHistoryTests: XCTestCase {
    let calendar = Calendar.disciplineCalendar(timeZone: TimeZone(identifier: "UTC")!)

    func summary(_ history: DemoHistory, today: DayKey) -> StreakSummary {
        StreakCalculator.summarizeHistory(habits: history.habits, completions: history.completions, tasks: history.tasks,
                                          challenges: [history.challenge], from: today.adding(days: -120, calendar: calendar),
                                          today: today, now: today.startDate(calendar: calendar).addingTimeInterval(12 * 3600),
                                          calendar: calendar)
    }

    func testTwoMissedDaysAndA24DayStreakForEveryWeekday() {
        let monday = DayKey(year: 2026, month: 10, day: 5)
        for offset in 0..<7 {
            let today = monday.adding(days: offset, calendar: calendar)
            let history = DemoHistoryGenerator.generate(userId: "u", condition: .aiAssisted, today: today, calendar: calendar)
            let result = summary(history, today: today)
            let outcomes = result.days.map(\.resolution.outcome)
            XCTAssertEqual(outcomes.filter { $0 == .failed }.count, 2, "today \(today)")
            XCTAssertEqual(result.current, 24, "today \(today)")
            XCTAssertEqual(result.longest, 24, "today \(today)")
            XCTAssertEqual(outcomes.last, .pending, "skills are due today and not logged yet")
            XCTAssertFalse(history.completions.contains { $0.day >= today })
            XCTAssertEqual(history.challenge.dayNumber(of: today, calendar: calendar), 46)
        }
    }

    func testAIAssistedHistoryMixesVerificationOutcomes() {
        let today = DayKey(year: 2026, month: 10, day: 6)
        let history = DemoHistoryGenerator.generate(userId: "u", condition: .aiAssisted, today: today, calendar: calendar)
        let statuses = history.completions.map(\.status)
        XCTAssertGreaterThan(statuses.filter { $0 == .verified }.count, 100)
        XCTAssertEqual(statuses.filter { $0 == .rejected }.count, 1)
        XCTAssertEqual(statuses.filter { $0 == .uncertain }.count, 1)
        XCTAssertEqual(statuses.filter { $0 == .resolved }.count, 2)
        XCTAssertEqual(history.tasks.count, 2)
        XCTAssertTrue(history.tasks.allSatisfy { $0.status == .completed })
        XCTAssertEqual(history.sessions.map(\.validReps), [50, 50])
        XCTAssertEqual(Set(history.completions.map(\.id)).count, history.completions.count, "unique ids")
        XCTAssertTrue(history.habits.allSatisfy { $0.challengeId == history.challenge.id })
        XCTAssertEqual(history.habits.filter { $0.category == .skill }.map(\.name), ["Guitar", "Spanish"])
    }
}
