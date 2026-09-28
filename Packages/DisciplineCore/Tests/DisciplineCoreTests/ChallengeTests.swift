import XCTest
@testable import DisciplineCore

final class ChallengeTests: XCTestCase {
    let calendar = Calendar.disciplineCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let today = DayKey(year: 2026, month: 9, day: 29)

    private func plan(name: String = "75 Day Discipline", duration: Int = 75, start: DayKey? = nil,
                      newHabits: [Habit]? = nil, adopted: [Habit] = [], existing: [Challenge] = [],
                      accepted: Bool = true, rules: ChallengeRules = ChallengeRules()) throws -> ChallengePlan {
        let start = start ?? today
        return try ChallengePlanner.plan(
            name: name, description: "", durationDays: duration, startDate: start, rules: rules, ownerId: "u",
            newHabits: newHabits ?? ChallengeTemplates.discipline75Habits(userId: "u", startDate: start),
            adoptedHabits: adopted, existingChallenges: existing, rulesAccepted: accepted, today: today,
            templateId: ChallengeTemplates.discipline75Id, calendar: calendar
        )
    }

    func testTemplateChallengeCreatesLinkedHabitsForItsDates() throws {
        let result = try plan()
        XCTAssertEqual(result.challenge.durationDays, 75)
        XCTAssertEqual(result.challenge.endDate, today.adding(days: 74, calendar: calendar))
        XCTAssertNotNil(result.challenge.rulesAcceptedAt)
        XCTAssertEqual(result.challenge.templateId, "75-day-discipline")
        XCTAssertEqual(result.habits.count, 5)
        XCTAssertTrue(result.habits.allSatisfy { $0.challengeId == result.challenge.id })
        XCTAssertTrue(result.habits.allSatisfy { $0.startDate == today && $0.endDate == result.challenge.endDate })
        XCTAssertEqual(result.habits.map(\.name), ["Gym", "Running", "Reading", "Cold Plunge", "Progress Photo"])
    }

    func testCustomChallengeAdoptsExistingHabitsWithoutChangingTheirDates() throws {
        let existing = Habit(id: "h", userId: "u", name: "Stretch", category: .recovery, frequency: .daily, targetCount: 1,
                             startDate: today.adding(days: -10, calendar: calendar))
        let result = try plan(name: "My 30", duration: 30, newHabits: [], adopted: [existing])
        XCTAssertEqual(result.habits.map(\.id), ["h"])
        XCTAssertEqual(result.habits.first?.challengeId, result.challenge.id)
        XCTAssertEqual(result.habits.first?.startDate, existing.startDate)
    }

    func testValidation() {
        XCTAssertThrowsError(try plan(name: "  ")) { XCTAssertEqual($0 as? ChallengePlanError, .emptyName) }
        XCTAssertThrowsError(try plan(duration: 3)) { XCTAssertEqual($0 as? ChallengePlanError, .invalidDuration) }
        XCTAssertThrowsError(try plan(accepted: false)) { XCTAssertEqual($0 as? ChallengePlanError, .rulesNotAccepted) }
        XCTAssertThrowsError(try plan(newHabits: [])) { XCTAssertEqual($0 as? ChallengePlanError, .noHabits) }
        XCTAssertThrowsError(try plan(start: today.adding(days: -1, calendar: calendar))) {
            XCTAssertEqual($0 as? ChallengePlanError, .startInPast)
        }
    }

    func testOnlyOneActiveOrUpcomingChallenge() throws {
        let active = try plan().challenge
        XCTAssertThrowsError(try plan(existing: [active])) { XCTAssertEqual($0 as? ChallengePlanError, .alreadyActive) }
        let upcoming = try plan(start: today.adding(days: 1, calendar: calendar)).challenge
        XCTAssertThrowsError(try plan(existing: [upcoming])) { XCTAssertEqual($0 as? ChallengePlanError, .alreadyActive) }
        var abandoned = active
        abandoned.status = .abandoned
        XCTAssertNoThrow(try plan(existing: [abandoned]))
    }

    func testActiveUpcomingAndFinished() throws {
        let challenge = try plan(duration: 7).challenge
        XCTAssertEqual(ChallengePlanner.activeChallenge(in: [challenge], today: today)?.id, challenge.id)
        let afterEnd = challenge.endDate.adding(days: 1, calendar: calendar)
        XCTAssertNil(ChallengePlanner.activeChallenge(in: [challenge], today: afterEnd))
        XCTAssertEqual(ChallengePlanner.finishedChallenges(in: [challenge], today: afterEnd).map(\.id), [challenge.id])
        XCTAssertTrue(ChallengePlanner.finishedChallenges(in: [challenge], today: challenge.endDate).isEmpty)

        let tomorrow = try plan(start: today.adding(days: 1, calendar: calendar)).challenge
        XCTAssertNil(ChallengePlanner.activeChallenge(in: [tomorrow], today: today))
        XCTAssertEqual(ChallengePlanner.upcomingChallenge(in: [tomorrow], today: today)?.id, tomorrow.id)
    }

    func testProgress() throws {
        let challenge = try plan(duration: 10).challenge
        func day(_ offset: Int, _ outcome: DayOutcome) -> StreakDay {
            StreakDay(resolution: DayResolution(day: today.adding(days: offset, calendar: calendar), outcome: outcome, due: [], hasCommitments: true),
                      streakBefore: 0, streakAfter: 0)
        }
        let days = [day(-1, .failed), day(0, .successful), day(1, .successful), day(2, .failed), day(3, .pending)]
        let progress = ChallengePlanner.progress(of: challenge, days: days, today: today.adding(days: 3, calendar: calendar), calendar: calendar)
        XCTAssertEqual(progress.dayNumber, 4)
        XCTAssertEqual(progress.daysRemaining, 6)
        XCTAssertEqual(progress.successfulDays, 2)
        XCTAssertEqual(progress.failedDays, 1, "the day before the challenge doesn't count")
        XCTAssertEqual(progress.pendingDays, 1)
        XCTAssertEqual(progress.adherence ?? 0, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(progress.fractionElapsed, 0.4, accuracy: 1e-9)
    }

    func testRulesDriveStreakBehaviour() throws {
        // A challenge whose rules pause instead of break the streak.
        let rules = ChallengeRules(missedDayBehavior: .pauseStreak)
        let challenge = try plan(duration: 7, rules: rules).challenge
        let habit = Habit(id: "h", userId: "u", challengeId: challenge.id, name: "Read", category: .reading,
                          frequency: .daily, targetCount: 1, startDate: today)
        let completions = [0, 2].map {
            HabitCompletion(userId: "u", habitId: "h", day: today.adding(days: $0, calendar: calendar), status: .selfReported,
                            method: .selfReport, trackingCondition: .manual)
        }
        let summary = StreakCalculator.summarize(habits: [habit], completions: completions, tasks: [], rules: challenge.rules,
                                                 from: challenge.startDate, today: today.adding(days: 3, calendar: calendar), calendar: calendar)
        XCTAssertEqual(summary.current, 2, "missed day 2 paused rather than reset the streak")
    }
}
