import XCTest
@testable import DisciplineCore

final class ResearchTests: XCTestCase {
    let calendar = Calendar.disciplineCalendar(timeZone: TimeZone(identifier: "UTC")!)

    // MARK: Shared history vectors

    private struct Fixture: Decodable {
        struct Case: Decodable {
            struct HabitSpec: Decodable {
                let id: String
                let challengeId: String?
                let frequency: HabitFrequency
                let unit: HabitUnit
                let targetCount: Int
                let scheduledWeekdays: [Int]?
                let startDate: DayKey
                let endDate: DayKey?
                let isRequired: Bool?
                let isActive: Bool?
            }
            struct CompletionSpec: Decodable {
                let habitId: String
                let day: DayKey
                let status: CompletionStatus
                let quantity: Int?
                let accountabilityTaskId: String?
            }
            struct TaskSpec: Decodable {
                let id: String
                let status: AccountabilityTaskStatus
                let deadline: String
            }
            struct ChallengeSpec: Decodable {
                struct RulesSpec: Decodable {
                    let requireAllHabits: Bool?
                    let allowSkipping: Bool?
                    let missedDayBehavior: MissedDayBehavior?
                    let uncertainPolicy: UncertainVerificationPolicy?
                }
                let id: String
                let startDate: DayKey
                let durationDays: Int
                let rules: RulesSpec
            }
            struct Expected: Decodable {
                let outcomes: [DayOutcome]
                let current: Int
                let longest: Int
            }
            let name: String
            let today: DayKey
            let from: DayKey
            let now: String
            let habits: [HabitSpec]
            let completions: [CompletionSpec]
            let tasks: [TaskSpec]?
            let challenges: [ChallengeSpec]?
            let expected: Expected
        }
        let cases: [Case]
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso) ?? Date(timeIntervalSince1970: 0)
    }

    func testSharedHistoryVectors() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/history-resolution-cases.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(fixture.cases.count, 9)

        for testCase in fixture.cases {
            let habits = testCase.habits.map {
                Habit(id: $0.id, userId: "u", challengeId: $0.challengeId, name: $0.id, category: .custom,
                      frequency: $0.frequency, unit: $0.unit, targetCount: $0.targetCount,
                      scheduledWeekdays: $0.scheduledWeekdays ?? [], startDate: $0.startDate, endDate: $0.endDate,
                      isRequired: $0.isRequired ?? true, isActive: $0.isActive ?? true)
            }
            let completions = testCase.completions.map {
                HabitCompletion(userId: "u", habitId: $0.habitId, day: $0.day, quantity: $0.quantity ?? 1, status: $0.status,
                                method: ($0.status == .accountabilityRequired || $0.status == .resolved) ? .accountabilityExercise : .selfReport,
                                trackingCondition: .manual, accountabilityTaskId: $0.accountabilityTaskId)
            }
            let tasks = (testCase.tasks ?? []).map {
                AccountabilityTask(id: $0.id, userId: "u", sourceHabitId: "x", sourceCompletionId: "x", day: testCase.today,
                                   title: "50 Push-Ups", description: "", type: .pushUps, target: 50, status: $0.status,
                                   deadline: date($0.deadline))
            }
            let challenges = (testCase.challenges ?? []).map { spec -> Challenge in
                let defaults = ChallengeRules()
                let rules = ChallengeRules(
                    requireAllHabits: spec.rules.requireAllHabits ?? defaults.requireAllHabits,
                    allowSkipping: spec.rules.allowSkipping ?? defaults.allowSkipping,
                    missedDayBehavior: spec.rules.missedDayBehavior ?? defaults.missedDayBehavior,
                    uncertainPolicy: spec.rules.uncertainPolicy ?? defaults.uncertainPolicy
                )
                return Challenge(id: spec.id, ownerId: "u", name: spec.id, description: "", durationDays: spec.durationDays,
                                 startDate: spec.startDate, rules: rules, createdAt: Date(timeIntervalSince1970: 0), calendar: calendar)
            }
            let summary = StreakCalculator.summarizeHistory(habits: habits, completions: completions, tasks: tasks,
                                                            challenges: challenges, from: testCase.from, today: testCase.today,
                                                            now: date(testCase.now), calendar: calendar)
            XCTAssertEqual(summary.days.map(\.resolution.outcome), testCase.expected.outcomes, testCase.name)
            XCTAssertEqual(summary.current, testCase.expected.current, testCase.name)
            XCTAssertEqual(summary.longest, testCase.expected.longest, testCase.name)
        }
    }

    // MARK: Records, aggregation, CSV

    private func record(_ participant: String, _ day: Int, _ condition: TrackingCondition, _ outcome: DayOutcome,
                        required: Int = 2, completed: Int = 2, verified: Int = 0, rejected: Int = 0, uncertain: Int = 0,
                        selfReported: Int = 0, streakAfter: Int = 0, confidence: [Double] = [],
                        tasks: Int = 0, tasksDone: Int = 0, tasksFailed: Int = 0) -> DailyRecord {
        DailyRecord(participantId: participant, challengeId: nil, day: DayKey(year: 2026, month: 9, day: day),
                    trackingCondition: condition, requiredHabits: required, completedHabits: completed, skippedHabits: tasks,
                    verifiedHabits: verified, rejectedHabits: rejected, uncertainHabits: uncertain, selfReportedHabits: selfReported,
                    accountabilityTasks: tasks, accountabilityTasksCompleted: tasksDone, accountabilityTasksFailed: tasksFailed,
                    verificationCount: confidence.count, verificationConfidenceSum: confidence.reduce(0, +),
                    outcome: outcome, streakBefore: 0, streakAfter: streakAfter, resolverVersion: DayResolver.version)
    }

    func testAggregatorComparesConditions() {
        let records = [
            record("P-A", 21, .aiAssisted, .successful, verified: 2, streakAfter: 1, confidence: [0.9, 0.8]),
            record("P-A", 22, .aiAssisted, .failed, completed: 1, verified: 1, rejected: 1, streakAfter: 0, confidence: [0.95, 0.75],
                   tasks: 1, tasksDone: 0, tasksFailed: 1),
            record("P-B", 21, .aiAssisted, .successful, verified: 1, uncertain: 1, streakAfter: 4, confidence: [0.6]),
            record("P-M", 21, .manual, .successful, selfReported: 2, streakAfter: 5, tasks: 1, tasksDone: 1),
            record("P-M", 22, .manual, .pending, completed: 0, streakAfter: 5)
        ]
        let summary = ResearchAggregator.summarize(records)
        let ai = summary[.aiAssisted]!
        XCTAssertEqual(ai.participants, 2)
        XCTAssertEqual(ai.daySuccessRate ?? -1, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(ai.adherence ?? -1, 5.0 / 6.0, accuracy: 1e-9)
        XCTAssertEqual(ai.verificationRate ?? -1, 4.0 / 6.0, accuracy: 1e-9)
        XCTAssertEqual(ai.rejectionRate ?? -1, 1.0 / 6.0, accuracy: 1e-9)
        XCTAssertEqual(ai.uncertainRate ?? -1, 1.0 / 6.0, accuracy: 1e-9)
        XCTAssertEqual(ai.meanConfidence ?? -1, 4.0 / 5.0, accuracy: 1e-9)
        XCTAssertEqual(ai.accountabilityCompletionRate ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(ai.meanCurrentStreak ?? -1, 2, accuracy: 1e-9, "P-A ends at 0, P-B at 4")
        XCTAssertEqual(ai.meanLongestStreak ?? -1, 2.5, accuracy: 1e-9)

        let manual = summary[.manual]!
        XCTAssertEqual(manual.participants, 1)
        XCTAssertEqual(manual.pendingDays, 1)
        XCTAssertEqual(manual.daySuccessRate ?? -1, 1, accuracy: 1e-9, "pending days excluded")
        XCTAssertNil(manual.verificationRate, "no AI verification in the manual condition")
        XCTAssertNil(manual.meanConfidence)
        XCTAssertEqual(manual.accountabilityCompletionRate ?? -1, 1, accuracy: 1e-9)
    }

    func testDailyCSVIsAnonymousAndEscaped() {
        var withComma = record("P-A", 21, .aiAssisted, .successful, verified: 2, confidence: [0.9, 0.8])
        withComma.challengeId = "c,1"
        let csv = ResearchCSV.daily([record("P-B", 22, .manual, .failed), withComma])
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, ResearchCSV.dailyHeader.joined(separator: ","))
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].hasPrefix("P-A,2026-09-21,aiAssisted,\"c,1\",2,2,0,2,0,0,0,0,0,0,2,0.8500,successful,1,"), lines[1])
        XCTAssertTrue(lines[2].hasPrefix("P-B,2026-09-22,manual,,"), "sorted by participant then date")
        XCTAssertFalse(csv.contains("@"), "no emails")
    }

    func testRecordBuilderCountsEventsForScopedDays() {
        let day = DayKey(year: 2026, month: 9, day: 28)
        let habit = Habit(id: "gym", userId: "u", name: "Gym", category: .gym, frequency: .daily, targetCount: 1, startDate: day)
        let completions = [
            HabitCompletion(id: "c1", userId: "u", habitId: "gym", day: day, status: .rejected, method: .photoVerification,
                            trackingCondition: .aiAssisted, verificationId: "v1"),
            HabitCompletion(id: "c2", userId: "u", habitId: "gym", day: day, status: .verified, method: .photoVerification,
                            trackingCondition: .aiAssisted, verificationId: "v2")
        ]
        let summary = StreakCalculator.summarizeHistory(habits: [habit], completions: completions, tasks: [], challenges: [],
                                                        from: day, today: day.adding(days: 1, calendar: calendar), calendar: calendar)
        let records = DailyRecordBuilder.build(participantId: "P-X", condition: .aiAssisted, summary: summary, habits: [habit],
                                               completions: completions, tasks: [], confidences: ["v1": 0.9, "v2": 0.8])
        XCTAssertEqual(records.count, 2)
        let first = records[0]
        XCTAssertEqual(first.outcome, .successful)
        XCTAssertEqual(first.requiredHabits, 1)
        XCTAssertEqual(first.completedHabits, 1)
        XCTAssertEqual(first.verifiedHabits, 1)
        XCTAssertEqual(first.rejectedHabits, 1)
        XCTAssertEqual(first.verificationCount, 2)
        XCTAssertEqual(first.verificationConfidenceSum, 1.7, accuracy: 1e-9)
        XCTAssertEqual(first.streakAfter, 1)
        XCTAssertEqual(records[1].outcome, .pending)
        XCTAssertEqual(first.id, "P-X_2026-09-28")
    }
}
