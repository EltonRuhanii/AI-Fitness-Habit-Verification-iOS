import Foundation

/// An optional extra discipline item, e.g. reading or a cold plunge, on chosen weekdays.
public struct RoutineExtra: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var category: HabitCategory
    /// 1 = Sunday … 7 = Saturday.
    public var weekdays: [Int]

    public init(id: String = UUID().uuidString, name: String, category: HabitCategory, weekdays: [Int]) {
        self.id = id
        self.name = name
        self.category = category
        self.weekdays = weekdays
    }

    /// Suggested extras offered during setup.
    public static let presets: [RoutineExtra] = [
        RoutineExtra(id: "reading", name: "Reading", category: .reading, weekdays: []),
        RoutineExtra(id: "cold-plunge", name: "Cold Plunge", category: .recovery, weekdays: []),
        RoutineExtra(id: "stretching", name: "Stretching", category: .recovery, weekdays: []),
        RoutineExtra(id: "meal-prep", name: "Healthy Meal", category: .nutrition, weekdays: [])
    ]
}

/// What the participant chooses when starting the 90-day challenge.
public struct RoutineSetup: Hashable, Sendable {
    public var workoutWeekdays: [Int]
    public var runWeekdays: [Int]
    /// Exactly two new skills to learn, practised every day.
    public var skills: [String]
    public var extras: [RoutineExtra]

    public init(workoutWeekdays: [Int] = [], runWeekdays: [Int] = [], skills: [String] = ["", ""], extras: [RoutineExtra] = []) {
        self.workoutWeekdays = workoutWeekdays
        self.runWeekdays = runWeekdays
        self.skills = skills
        self.extras = extras
    }
}

public enum RoutineError: Error, Equatable, Sendable {
    case noWorkoutDays
    case skillsIncomplete
    case duplicateSkills
    case extraIncomplete(String)
}

/// The app's single challenge format: 90 days, a fixed weekly routine and two new skills
/// practised for at least an hour every day.
///
/// Every activity is tied to fixed weekdays (or every day), so each day has a definite list of
/// main activities. Under the strict rules below, a day with any of them left undone (and not
/// covered by a completed push-up accountability task) fails and resets the streak to 0.
public enum RoutinePlanner {
    public static let templateId = "discipline-90"
    public static let challengeName = "90 Day Discipline"
    public static let durationDays = 90
    public static let skillCount = 2
    public static let minimumSkillMinutes = 60

    /// Strict rules: every main activity required, a miss breaks the streak, skipping only via
    /// the agreed push-ups. Study parameters (AI threshold etc.) keep their defaults.
    public static let rules = ChallengeRules(
        streakEnabled: true,
        requireAllHabits: true,
        allowSkipping: true,
        defaultSkipConsequence: AccountabilityTemplate(type: .pushUps, target: 50),
        missedDayBehavior: .breakStreak,
        uncertainPolicy: .countsAsResolved
    )

    public static func validate(_ setup: RoutineSetup) throws {
        guard !setup.workoutWeekdays.isEmpty else { throw RoutineError.noWorkoutDays }
        let skills = setup.skills.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard skills.count == skillCount, skills.allSatisfy({ !$0.isEmpty }) else { throw RoutineError.skillsIncomplete }
        guard Set(skills.map { $0.lowercased() }).count == skillCount else { throw RoutineError.duplicateSkills }
        for extra in setup.extras where extra.name.trimmingCharacters(in: .whitespaces).isEmpty || extra.weekdays.isEmpty {
            throw RoutineError.extraIncomplete(extra.name)
        }
    }

    /// The challenge's habits. Every main activity needs photo evidence (all participants are
    /// in the AI-assisted condition); skipping costs push-ups.
    public static func habits(for setup: RoutineSetup, userId: String, startDate: DayKey) throws -> [Habit] {
        try validate(setup)
        func session(_ name: String, _ description: String, _ category: HabitCategory, _ weekdays: [Int], pushUps: Int) -> Habit {
            Habit(userId: userId, name: name, description: description, category: category, frequency: .custom,
                  unit: .sessions, targetCount: 1, scheduledWeekdays: weekdays.sorted(), startDate: startDate,
                  requiresEvidence: true, verificationType: .photoAI,
                  skipConsequence: AccountabilityTemplate(type: .pushUps, target: pushUps))
        }

        var habits = [session("Workout", "Strength or conditioning session.", .gym, setup.workoutWeekdays, pushUps: 50)]
        if !setup.runWeekdays.isEmpty {
            habits.append(session("Run", "Outdoor or treadmill run.", .running, setup.runWeekdays, pushUps: 40))
        }
        for skill in setup.skills.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            habits.append(Habit(
                userId: userId, name: skill, description: "Practise \(skill) for at least \(minimumSkillMinutes) minutes.",
                category: .skill, frequency: .daily, unit: .minutes, targetCount: minimumSkillMinutes, startDate: startDate,
                requiresEvidence: true, verificationType: .photoAI,
                skipConsequence: AccountabilityTemplate(type: .pushUps, target: 50)
            ))
        }
        for extra in setup.extras {
            habits.append(session(extra.name.trimmingCharacters(in: .whitespaces), "", extra.category, extra.weekdays, pushUps: 30))
        }
        return habits
    }

    /// Builds the challenge after the participant has explicitly accepted the rules.
    public static func plan(
        setup: RoutineSetup,
        ownerId: String,
        startDate: DayKey,
        existingChallenges: [Challenge],
        rulesAccepted: Bool,
        today: DayKey,
        now: Date = Date(),
        id: String = UUID().uuidString,
        calendar: Calendar
    ) throws -> ChallengePlan {
        let habits = try habits(for: setup, userId: ownerId, startDate: startDate)
        return try ChallengePlanner.plan(
            name: challengeName,
            description: description(of: setup, calendar: calendar),
            durationDays: durationDays,
            startDate: startDate,
            rules: rules,
            ownerId: ownerId,
            newHabits: habits,
            adoptedHabits: [],
            existingChallenges: existingChallenges,
            rulesAccepted: rulesAccepted,
            today: today,
            templateId: templateId,
            now: now,
            id: id,
            calendar: calendar
        )
    }

    /// Human-readable summary, e.g. "Workouts Mon, Tue, Thu, Fri · Runs Wed, Sat · Guitar and Spanish 60 min daily".
    public static func description(of setup: RoutineSetup, calendar: Calendar) -> String {
        func days(_ weekdays: [Int]) -> String {
            let order = [2, 3, 4, 5, 6, 7, 1]
            return order.filter(weekdays.contains).map { calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
        }
        var parts = ["Workouts \(days(setup.workoutWeekdays))"]
        if !setup.runWeekdays.isEmpty { parts.append("Runs \(days(setup.runWeekdays))") }
        let skills = setup.skills.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " and ")
        parts.append("\(skills) \(minimumSkillMinutes) min daily")
        for extra in setup.extras { parts.append("\(extra.name) \(days(extra.weekdays))") }
        return parts.joined(separator: " · ")
    }
}
