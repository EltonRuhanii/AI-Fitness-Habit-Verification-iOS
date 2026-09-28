import XCTest
@testable import DisciplineCore

final class NotificationPlannerTests: XCTestCase {
    let calendar = Calendar.disciplineCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let today = DayKey(year: 2026, month: 9, day: 30) // Wednesday

    func at(_ hour: Int, _ minute: Int = 0, day: DayKey? = nil) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: (day ?? today).startDate(calendar: calendar))!
    }

    func commitment(_ name: String, frequency: HabitFrequency = .daily, target: Int = 1, achieved: Int = 0,
                    state: TodayCommitment.State = .open) -> TodayCommitment {
        let habit = Habit(id: name, userId: "u", name: name, category: .gym, frequency: frequency, targetCount: target, startDate: today)
        return TodayCommitment(habit: habit, progress: HabitProgress(habitId: name, period: HabitPeriod(start: today, end: today),
                                                                   achieved: achieved, target: target),
                               todayCompletions: [], state: state, requirement: .selfReport)
    }

    func streak(current: Int, todayOutcome: DayOutcome = .pending) -> StreakSummary {
        let day = StreakDay(resolution: DayResolution(day: today, outcome: todayOutcome, due: [], hasCommitments: true),
                            streakBefore: current, streakAfter: current)
        return StreakSummary(current: current, longest: current, days: [day])
    }

    func plan(now: Date, preferences: NotificationPreferences = NotificationPreferences(), commitments: [TodayCommitment] = [],
              tasks: [AccountabilityTask] = [], streak: StreakSummary? = nil) -> [PlannedNotification] {
        NotificationPlanner.plan(now: now, calendar: calendar, preferences: preferences, today: today, commitments: commitments,
                                 openTasks: tasks, streak: streak ?? self.streak(current: 0))
    }

    func testDisabledPlansNothing() {
        var preferences = NotificationPreferences()
        preferences.enabled = false
        XCTAssertTrue(plan(now: at(9), preferences: preferences, commitments: [commitment("Gym")]).isEmpty)
    }

    func testTodayReminderOnlyWhenSomethingIsOpen() {
        let withOpen = plan(now: at(9), commitments: [commitment("Gym"), commitment("Read", state: .done)])
        let todays = withOpen.filter { $0.id == "reminder.2026-09-30" }
        XCTAssertEqual(todays.count, 1)
        XCTAssertEqual(todays.first?.fireDate, at(18))
        XCTAssertEqual(todays.first?.title, "1 commitment left today")
        XCTAssertEqual(todays.first?.body, "Still open: Gym.")

        let allDone = plan(now: at(9), commitments: [commitment("Gym", state: .done)])
        XCTAssertFalse(allDone.contains { $0.id == "reminder.2026-09-30" })
        XCTAssertEqual(allDone.filter { $0.kind == .dailyReminder }.count, NotificationPlanner.reminderDaysAhead, "generic reminders for coming days")
    }

    func testReminderMentionsRemainingWeeklySessions() {
        let notes = plan(now: at(9), commitments: [commitment("Gym", frequency: .weekly, target: 4, achieved: 3, state: .inProgress)])
        XCTAssertEqual(notes.first { $0.id == "reminder.2026-09-30" }?.body, "You have one remaining gym session this week.")
    }

    func testNoReminderAfterItsTimeHasPassed() {
        XCTAssertFalse(plan(now: at(19), commitments: [commitment("Gym")]).contains { $0.id == "reminder.2026-09-30" })
    }

    func testAccountabilityDeadlineTwoHoursBefore() {
        let task = AccountabilityTask(id: "t1", userId: "u", sourceHabitId: "gym", sourceCompletionId: "c", day: today,
                                      title: "50 Push-Ups", description: "", type: .pushUps, target: 50, deadline: at(17))
        let note = plan(now: at(9), tasks: [task]).first { $0.kind == .accountabilityDeadline }
        XCTAssertEqual(note?.fireDate, at(15))
        XCTAssertTrue(note?.body.hasPrefix("50 Push-Ups is due at") == true)
    }

    func testAccountabilityInQuietHoursMovesEarlier() {
        let tomorrow = today.adding(days: 1, calendar: calendar)
        let task = AccountabilityTask(id: "t1", userId: "u", sourceHabitId: "gym", sourceCompletionId: "c", day: today,
                                      title: "50 Push-Ups", description: "", type: .pushUps, target: 50, deadline: at(1, day: tomorrow))
        let note = plan(now: at(9), tasks: [task]).first { $0.kind == .accountabilityDeadline }
        // Would fire at 23:00 (quiet); moved to 21:00 the same evening.
        XCTAssertEqual(note?.fireDate, at(21))
    }

    func testStreakWarningOnlyForMeaningfulPendingStreak() {
        let open = [commitment("Gym")]
        XCTAssertTrue(plan(now: at(9), commitments: open, streak: streak(current: 5)).contains { $0.kind == .streakWarning })
        XCTAssertFalse(plan(now: at(9), commitments: open, streak: streak(current: 2)).contains { $0.kind == .streakWarning })
        XCTAssertFalse(plan(now: at(9), commitments: [commitment("Gym", state: .done)], streak: streak(current: 5, todayOutcome: .successful))
            .contains { $0.kind == .streakWarning })
    }

    func testWeeklySummaryOnSundayEvening() {
        let note = plan(now: at(9)).first { $0.kind == .weeklySummary }
        XCTAssertEqual(note?.fireDate, at(19, day: DayKey(year: 2026, month: 10, day: 4)))
    }

    func testDailyCapKeepsHighestPriority() {
        let tasks = (0..<3).map {
            AccountabilityTask(id: "t\($0)", userId: "u", sourceHabitId: "gym", sourceCompletionId: "c", day: today,
                               title: "Task \($0)", description: "", type: .pushUps, target: 50, deadline: at(17 + $0))
        }
        let todays = plan(now: at(9), commitments: [commitment("Gym")], tasks: tasks, streak: streak(current: 5))
            .filter { DayKey($0.fireDate, calendar: calendar) == today }
        XCTAssertEqual(todays.count, NotificationPlanner.maxPerDay)
        XCTAssertTrue(todays.allSatisfy { $0.kind == .accountabilityDeadline })
    }

    func testQuietHours() {
        let preferences = NotificationPreferences()
        XCTAssertTrue(NotificationPlanner.isQuiet(hour: 23, preferences: preferences))
        XCTAssertTrue(NotificationPlanner.isQuiet(hour: 7, preferences: preferences))
        XCTAssertFalse(NotificationPlanner.isQuiet(hour: 8, preferences: preferences))
        XCTAssertFalse(NotificationPlanner.isQuiet(hour: 21, preferences: preferences))

        var late = NotificationPreferences()
        late.reminderHour = 23
        XCTAssertTrue(plan(now: at(9), preferences: late, commitments: [commitment("Gym")]).filter { $0.kind == .dailyReminder }.isEmpty,
                      "reminders set inside quiet hours are dropped")
    }
}
