import XCTest
@testable import DisciplineCore

final class RoutinePlannerTests: XCTestCase {
    let calendar = Calendar.disciplineCalendar(timeZone: TimeZone(identifier: "UTC")!)
    let monday = DayKey(year: 2026, month: 10, day: 5)

    var setup: RoutineSetup {
        RoutineSetup(workoutWeekdays: [2, 3, 5, 6], runWeekdays: [4, 7], skills: ["Guitar", "Spanish"],
                     extras: [RoutineExtra(name: "Cold Plunge", category: .recovery, weekdays: [3])])
    }

    func testHabitsFromSetup() throws {
        let habits = try RoutinePlanner.habits(for: setup, userId: "u", startDate: monday)
        XCTAssertEqual(habits.map(\.name), ["Workout", "Run", "Guitar", "Spanish", "Cold Plunge"])
        XCTAssertTrue(habits.allSatisfy { $0.requiresEvidence && $0.isRequired })
        let guitar = habits[2]
        XCTAssertEqual(guitar.category, .skill)
        XCTAssertEqual(guitar.frequency, .daily)
        XCTAssertEqual(guitar.unit, .minutes)
        XCTAssertEqual(guitar.targetCount, 60)
        XCTAssertEqual(habits[0].frequency, .custom)
        XCTAssertEqual(habits[0].scheduledWeekdays, [2, 3, 5, 6])
    }

    func testValidation() {
        var noWorkout = setup
        noWorkout.workoutWeekdays = []
        XCTAssertThrowsError(try RoutinePlanner.validate(noWorkout)) { XCTAssertEqual($0 as? RoutineError, .noWorkoutDays) }
        var oneSkill = setup
        oneSkill.skills = ["Guitar", " "]
        XCTAssertThrowsError(try RoutinePlanner.validate(oneSkill)) { XCTAssertEqual($0 as? RoutineError, .skillsIncomplete) }
        var duplicate = setup
        duplicate.skills = ["Guitar", "guitar"]
        XCTAssertThrowsError(try RoutinePlanner.validate(duplicate)) { XCTAssertEqual($0 as? RoutineError, .duplicateSkills) }
        var badExtra = setup
        badExtra.extras = [RoutineExtra(name: "Reading", category: .reading, weekdays: [])]
        XCTAssertThrowsError(try RoutinePlanner.validate(badExtra))
        var noRuns = setup
        noRuns.runWeekdays = []
        XCTAssertNoThrow(try RoutinePlanner.validate(noRuns), "runs are optional")
    }

    func testPlanIsA90DayStrictChallenge() throws {
        let plan = try RoutinePlanner.plan(setup: setup, ownerId: "u", startDate: monday, existingChallenges: [],
                                           rulesAccepted: true, today: monday, calendar: calendar)
        XCTAssertEqual(plan.challenge.durationDays, 90)
        XCTAssertEqual(plan.challenge.templateId, "discipline-90")
        XCTAssertEqual(plan.challenge.rules.missedDayBehavior, .breakStreak)
        XCTAssertTrue(plan.challenge.rules.requireAllHabits)
        XCTAssertEqual(plan.habits.count, 5)
        XCTAssertTrue(plan.habits.allSatisfy { $0.challengeId == plan.challenge.id && $0.endDate == plan.challenge.endDate })
        XCTAssertTrue(plan.challenge.description.contains("Guitar and Spanish 60 min daily"))
    }

    // MARK: Strict daily rule

    private func resolve(_ day: DayKey, _ habits: [Habit], _ completions: [HabitCompletion], rules: ChallengeRules) -> DayOutcome {
        DayResolver.resolve(day: day, habits: habits, completions: completions, tasks: [], rules: rules,
                            today: day.adding(days: 1, calendar: calendar), calendar: calendar).outcome
    }

    private func done(_ habit: Habit, _ day: DayKey, _ quantity: Int = 1, _ status: CompletionStatus = .verified) -> HabitCompletion {
        HabitCompletion(userId: "u", habitId: habit.id, day: day, quantity: quantity, status: status,
                        method: .photoVerification, trackingCondition: .aiAssisted)
    }

    func testAnyUnfinishedMainActivityFailsTheDay() throws {
        let plan = try RoutinePlanner.plan(setup: setup, ownerId: "u", startDate: monday, existingChallenges: [],
                                           rulesAccepted: true, today: monday, calendar: calendar)
        let byName = Dictionary(uniqueKeysWithValues: plan.habits.map { ($0.name, $0) })
        let rules = plan.challenge.rules
        // Monday: Workout + Guitar + Spanish are due (no run, no cold plunge).
        var monday = [done(byName["Workout"]!, self.monday), done(byName["Guitar"]!, self.monday, 60), done(byName["Spanish"]!, self.monday, 60)]
        XCTAssertEqual(resolve(self.monday, plan.habits, monday, rules: rules), .successful)

        monday[2] = done(byName["Spanish"]!, self.monday, 45)
        XCTAssertEqual(resolve(self.monday, plan.habits, monday, rules: rules), .failed, "45 of 60 minutes isn't enough")

        monday.append(done(byName["Spanish"]!, self.monday, 15))
        XCTAssertEqual(resolve(self.monday, plan.habits, monday, rules: rules), .successful, "two sessions add up")
    }

    func testSkippingASkillWithPushUpsCoversTheRestOfToday() throws {
        let plan = try RoutinePlanner.plan(setup: setup, ownerId: "u", startDate: monday, existingChallenges: [],
                                           rulesAccepted: true, today: monday, calendar: calendar)
        let guitar = plan.habits.first { $0.name == "Guitar" }!
        let partial = done(guitar, monday, 20)
        XCTAssertTrue(AccountabilityPlanner.canSkip(guitar, on: monday, completions: [partial], rules: plan.challenge.rules, calendar: calendar))
        let skip = try AccountabilityPlanner.planSkip(habit: guitar, day: monday, condition: .aiAssisted, existing: [partial],
                                                      rules: plan.challenge.rules, calendar: calendar)
        XCTAssertEqual(skip.completion.quantity, 40, "covers the remaining 40 minutes")
        XCTAssertEqual(skip.completion.id, "\(guitar.id)_2026-10-05_skip")
        XCTAssertFalse(AccountabilityPlanner.canSkip(guitar, on: monday, completions: [partial, skip.completion],
                                                     rules: plan.challenge.rules, calendar: calendar), "one skip per day")

        var resolved = skip.completion
        resolved.status = .resolved
        let summary = HabitSchedule.progress(for: guitar, on: monday, completions: [partial, resolved],
                                             policy: CountingPolicy(rules: plan.challenge.rules), calendar: calendar)
        XCTAssertEqual(summary?.isMet, true)
    }

    // MARK: Widget snapshot

    func testWidgetSnapshotShowsFirstThreeUnfinished() throws {
        let plan = try RoutinePlanner.plan(setup: setup, ownerId: "u", startDate: monday, existingChallenges: [],
                                           rulesAccepted: true, today: monday, calendar: calendar)
        let workout = plan.habits.first { $0.name == "Workout" }!
        let guitar = plan.habits.first { $0.name == "Guitar" }!
        let completions = [done(workout, monday), done(guitar, monday, 25)]
        let commitments = TodayCommitments.build(habits: plan.habits, completions: completions, today: monday,
                                                 condition: .aiAssisted, calendar: calendar)
        let snapshot = WidgetSnapshot.make(today: monday, commitments: commitments, streak: 7, progress: nil)
        XCTAssertEqual(snapshot.remaining, 2, "Guitar (partial) and Spanish; Workout is done")
        XCTAssertEqual(Set(snapshot.items.map(\.name)), ["Guitar", "Spanish"])
        XCTAssertEqual(snapshot.items.first { $0.name == "Guitar" }?.detail, "25/60 min")
        XCTAssertFalse(snapshot.allDone)
        XCTAssertEqual(snapshot.streak, 7)

        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: encoded), snapshot)

        let allDone = WidgetSnapshot.make(today: monday, commitments: [], streak: 8, progress: nil)
        XCTAssertTrue(allDone.allDone)
        XCTAssertTrue(allDone.items.isEmpty)
        XCTAssertFalse(allDone.isCurrent(today: monday.adding(days: 1, calendar: calendar)))
    }

    func testWidgetDisplayRollsOverAtMidnight() throws {
        let plan = try RoutinePlanner.plan(setup: setup, ownerId: "u", startDate: monday, existingChallenges: [],
                                           rulesAccepted: true, today: monday, calendar: calendar)
        let tuesday = monday.adding(days: 1, calendar: calendar)
        let todays = TodayCommitments.build(habits: plan.habits, completions: [], today: monday, condition: .aiAssisted, calendar: calendar)
        let tomorrows = TodayCommitments.build(habits: plan.habits, completions: [], today: tuesday, condition: .aiAssisted, calendar: calendar)
        let progress = ChallengeProgress(dayNumber: 10, durationDays: 90, successfulDays: 9, failedDays: 0, pendingDays: 1)
        let unfinished = WidgetSnapshot.make(today: monday, commitments: todays, streak: 9, progress: progress,
                                             nextDayCommitments: tomorrows)
        XCTAssertEqual(unfinished.display(on: monday, calendar: calendar).streak, 9)
        XCTAssertEqual(unfinished.display(on: monday, calendar: calendar).remaining, 3)

        let rolled = unfinished.display(on: tuesday, calendar: calendar)
        XCTAssertEqual(rolled.streak, 0, "an unfinished day resets the streak at midnight")
        XCTAssertEqual(rolled.remaining, 4, "Tuesday: workout, cold plunge and both skills")
        XCTAssertEqual(rolled.items.count, 3)
        XCTAssertEqual(rolled.challengeDay, 11)

        let finished = WidgetSnapshot.make(today: monday, commitments: [], streak: 10, progress: progress,
                                           nextDayCommitments: tomorrows)
        XCTAssertEqual(finished.display(on: tuesday, calendar: calendar).streak, 10, "a finished day keeps the streak")

        let stale = finished.display(on: tuesday.adding(days: 1, calendar: calendar), calendar: calendar)
        XCTAssertNil(stale.remaining)
        XCTAssertTrue(stale.items.isEmpty)
    }
}
