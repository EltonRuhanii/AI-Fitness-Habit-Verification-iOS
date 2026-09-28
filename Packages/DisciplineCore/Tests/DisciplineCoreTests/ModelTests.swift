import XCTest
@testable import DisciplineCore

final class DayKeyTests: XCTestCase {
    private let calendar = Calendar.disciplineCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    func testStringRoundTrip() {
        let key = DayKey(year: 2026, month: 9, day: 3)
        XCTAssertEqual(key.description, "2026-09-03")
        XCTAssertEqual(DayKey(string: "2026-09-03"), key)
    }

    func testRejectsMalformedStrings() {
        XCTAssertNil(DayKey(string: "2026-13-01"))
        XCTAssertNil(DayKey(string: "2026/09/03"))
        XCTAssertNil(DayKey(string: "yesterday"))
    }

    func testAddingDaysCrossesMonthAndYear() {
        XCTAssertEqual(DayKey(year: 2026, month: 12, day: 31).adding(days: 1, calendar: calendar), DayKey(year: 2027, month: 1, day: 1))
        XCTAssertEqual(DayKey(year: 2026, month: 3, day: 1).adding(days: -1, calendar: calendar), DayKey(year: 2026, month: 2, day: 28))
    }

    func testAddingDaysAcrossDaylightSavingChange() {
        // Europe/Berlin switches to summer time on 2026-03-29; a day is 23 hours long.
        let before = DayKey(year: 2026, month: 3, day: 28)
        XCTAssertEqual(before.adding(days: 1, calendar: calendar), DayKey(year: 2026, month: 3, day: 29))
        XCTAssertEqual(before.adding(days: 2, calendar: calendar), DayKey(year: 2026, month: 3, day: 30))
        XCTAssertEqual(before.days(to: DayKey(year: 2026, month: 3, day: 30), calendar: calendar), 2)
    }

    func testWeekStartsOnMonday() {
        // 2026-09-27 is a Sunday; its ISO week starts Monday 2026-09-21.
        let sunday = DayKey(year: 2026, month: 9, day: 27)
        XCTAssertEqual(sunday.startOfWeek(calendar: calendar), DayKey(year: 2026, month: 9, day: 21))
        XCTAssertEqual(DayKey(year: 2026, month: 9, day: 28).startOfWeek(calendar: calendar), DayKey(year: 2026, month: 9, day: 28))
    }

    func testComparable() {
        XCTAssertLessThan(DayKey(year: 2026, month: 1, day: 31), DayKey(year: 2026, month: 2, day: 1))
    }

    func testCodableAsString() throws {
        let data = try JSONEncoder().encode(["day": DayKey(year: 2026, month: 9, day: 28)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"day":"2026-09-28"}"#)
        XCTAssertThrowsError(try JSONDecoder().decode([String: DayKey].self, from: Data(#"{"day":"nope"}"#.utf8)))
    }
}

final class ModelTests: XCTestCase {
    func testParticipantIdFormatContainsNoPersonalData() {
        let id = ParticipantID.generate()
        XCTAssertTrue(id.hasPrefix("P-"))
        XCTAssertEqual(id.count, 12)
        XCTAssertNotEqual(ParticipantID.generate(), ParticipantID.generate())
    }

    func testAccountabilityTemplateIsClampedToSafetyLimit() {
        XCTAssertEqual(AccountabilityTemplate(type: .pushUps, target: 1000).target, 100)
        XCTAssertEqual(AccountabilityTemplate(type: .pushUps, target: 0).target, 1)
        XCTAssertEqual(AccountabilityTemplate(type: .coldPlunge, target: 30).target, 5)
        XCTAssertEqual(AccountabilityTemplate(type: .pushUps, target: 50, deadlineHours: 500).deadlineHours, 48)
    }

    func testConfidenceThresholdIsClamped() {
        XCTAssertEqual(ChallengeRules(confidenceThreshold: 0.1).confidenceThreshold, 0.5)
        XCTAssertEqual(ChallengeRules(confidenceThreshold: 1.5).confidenceThreshold, 0.99)
    }

    func testChallengeEndDateAndDayNumber() {
        let calendar = Calendar.disciplineCalendar()
        let start = DayKey(year: 2026, month: 9, day: 1)
        let challenge = Challenge(ownerId: "u", name: "75 Day", description: "", durationDays: 75, startDate: start, rules: ChallengeRules(), calendar: calendar)
        XCTAssertEqual(challenge.endDate, DayKey(year: 2026, month: 11, day: 14))
        XCTAssertEqual(challenge.dayNumber(of: start, calendar: calendar), 1)
        XCTAssertEqual(challenge.dayNumber(of: challenge.endDate, calendar: calendar), 75)
        XCTAssertNil(challenge.dayNumber(of: start.adding(days: -1, calendar: calendar), calendar: calendar))
    }

    func testHabitInEffectRange() {
        let habit = Habit(userId: "u", name: "Gym", category: .gym, frequency: .weekly, targetCount: 4,
                          startDate: DayKey(year: 2026, month: 9, day: 10), endDate: DayKey(year: 2026, month: 9, day: 20))
        XCTAssertFalse(habit.isInEffect(on: DayKey(year: 2026, month: 9, day: 9)))
        XCTAssertTrue(habit.isInEffect(on: DayKey(year: 2026, month: 9, day: 10)))
        XCTAssertTrue(habit.isInEffect(on: DayKey(year: 2026, month: 9, day: 20)))
        XCTAssertFalse(habit.isInEffect(on: DayKey(year: 2026, month: 9, day: 21)))
        XCTAssertEqual(habit.targetDescription, "4x / week")
    }

    func testCompletionStatusSemantics() {
        XCTAssertTrue(CompletionStatus.verified.countsAsCompleted)
        XCTAssertTrue(CompletionStatus.selfReported.countsAsCompleted)
        XCTAssertFalse(CompletionStatus.uncertain.countsAsCompleted, "uncertain must be decided by challenge policy, not assumed")
        XCTAssertFalse(CompletionStatus.pendingVerification.countsAsCompleted)
    }

    func testCompletionRoundTripsThroughJSON() throws {
        let completion = HabitCompletion(userId: "u", habitId: "h", day: DayKey(year: 2026, month: 9, day: 28),
                                         status: .verified, method: .photoVerification, trackingCondition: .aiAssisted,
                                         createdAt: Date(timeIntervalSince1970: 1_790_000_000),
                                         updatedAt: Date(timeIntervalSince1970: 1_790_000_000))
        let decoded = try JSONDecoder().decode(HabitCompletion.self, from: JSONEncoder().encode(completion))
        XCTAssertEqual(decoded, completion)
    }
}
