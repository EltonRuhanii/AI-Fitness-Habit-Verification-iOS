import Foundation

/// The window in which a habit's target must be met: one day for daily/custom habits,
/// one Monday–Sunday week for weekly habits.
public struct HabitPeriod: Hashable, Sendable {
    public let start: DayKey
    public let end: DayKey

    public init(start: DayKey, end: DayKey) {
        self.start = start
        self.end = end
    }

    public func contains(_ day: DayKey) -> Bool { day >= start && day <= end }
}

/// Which completion states count towards a target.
///
/// `selfReported` and `verified` always count. The treatment of `uncertain` (AI could not
/// decide) and `resolved` (skipped, accountability completed) is a challenge rule, so it
/// is explicit rather than hidden inside the calculation.
public struct CountingPolicy: Hashable, Sendable {
    public var countsUncertain: Bool
    public var countsResolved: Bool

    public init(countsUncertain: Bool = true, countsResolved: Bool = true) {
        self.countsUncertain = countsUncertain
        self.countsResolved = countsResolved
    }

    public init(rules: ChallengeRules) {
        self.init(countsUncertain: rules.uncertainPolicy == .countsAsResolved, countsResolved: rules.allowSkipping)
    }

    public func counts(_ status: CompletionStatus) -> Bool {
        switch status {
        case .selfReported, .verified: return true
        case .uncertain: return countsUncertain
        case .resolved: return countsResolved
        default: return false
        }
    }
}

public struct HabitProgress: Hashable, Sendable {
    public let habitId: String
    public let period: HabitPeriod
    public let achieved: Int
    public let target: Int

    public init(habitId: String, period: HabitPeriod, achieved: Int, target: Int) {
        self.habitId = habitId
        self.period = period
        self.achieved = achieved
        self.target = target
    }

    public var isMet: Bool { achieved >= target }
    public var remaining: Int { max(0, target - achieved) }
    public var fraction: Double { target > 0 ? min(1, Double(achieved) / Double(target)) : 0 }
}

/// Pure scheduling and target arithmetic. All functions take an explicit calendar so
/// results are reproducible (tests and research analysis use a fixed time zone).
public enum HabitSchedule {
    /// Whether the habit can be worked on / is expected on `day`.
    /// Weekly habits may be done on any day of the week.
    public static func isScheduled(_ habit: Habit, on day: DayKey, calendar: Calendar) -> Bool {
        guard habit.isInEffect(on: day) else { return false }
        switch habit.frequency {
        case .daily, .weekly: return true
        case .custom: return habit.scheduledWeekdays.contains(day.weekday(calendar: calendar))
        }
    }

    /// The target period containing `day`, or `nil` if the habit is not scheduled that day.
    public static func period(for habit: Habit, containing day: DayKey, calendar: Calendar) -> HabitPeriod? {
        guard isScheduled(habit, on: day, calendar: calendar) else { return nil }
        switch habit.frequency {
        case .daily, .custom:
            return HabitPeriod(start: day, end: day)
        case .weekly:
            let start = day.startOfWeek(calendar: calendar)
            return HabitPeriod(start: start, end: start.adding(days: 6, calendar: calendar))
        }
    }

    public static func progress(
        for habit: Habit,
        on day: DayKey,
        completions: [HabitCompletion],
        policy: CountingPolicy = CountingPolicy(),
        calendar: Calendar
    ) -> HabitProgress? {
        guard let period = period(for: habit, containing: day, calendar: calendar) else { return nil }
        let achieved = completions
            .filter { $0.habitId == habit.id && period.contains($0.day) && policy.counts($0.status) }
            .reduce(0) { $0 + $1.quantity }
        return HabitProgress(habitId: habit.id, period: period, achieved: achieved, target: habit.targetCount)
    }

    /// All target periods of a habit that overlap `[from, through]`, clipped to the habit's
    /// effective dates. Used for weekly/monthly adherence.
    public static func periods(for habit: Habit, from: DayKey, through: DayKey, calendar: Calendar) -> [HabitPeriod] {
        guard from <= through else { return [] }
        var result: [HabitPeriod] = []
        var day = from
        while day <= through {
            if let period = period(for: habit, containing: day, calendar: calendar), result.last != period {
                result.append(period)
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return result
    }

    /// Progress over the Monday–Sunday week containing `day`. Weekly habits report their own
    /// target; daily/custom habits report scheduled days met out of scheduled days.
    public static func weekSummary(
        for habit: Habit,
        containing day: DayKey,
        completions: [HabitCompletion],
        policy: CountingPolicy = CountingPolicy(),
        calendar: Calendar
    ) -> (achieved: Int, target: Int)? {
        switch habit.frequency {
        case .weekly:
            return progress(for: habit, on: day, completions: completions, policy: policy, calendar: calendar)
                .map { ($0.achieved, $0.target) }
        case .daily, .custom:
            let start = day.startOfWeek(calendar: calendar)
            let weekPeriods = periods(for: habit, from: start, through: start.adding(days: 6, calendar: calendar), calendar: calendar)
            guard !weekPeriods.isEmpty else { return nil }
            let met = weekPeriods.filter {
                progress(for: habit, on: $0.start, completions: completions, policy: policy, calendar: calendar)?.isMet == true
            }.count
            return (met, weekPeriods.count)
        }
    }

    /// Number of periods in `[from, through]` whose target was met, out of all periods.
    /// A weekly period is only counted once it has ended, or if it is already met, so an
    /// in-progress week doesn't count as a miss.
    public static func adherence(
        for habit: Habit,
        from: DayKey,
        through: DayKey,
        today: DayKey,
        completions: [HabitCompletion],
        policy: CountingPolicy = CountingPolicy(),
        calendar: Calendar
    ) -> (met: Int, total: Int) {
        var met = 0
        var total = 0
        for period in periods(for: habit, from: from, through: through, calendar: calendar) {
            guard let progress = progress(for: habit, on: period.start, completions: completions, policy: policy, calendar: calendar) else { continue }
            if progress.isMet {
                met += 1
                total += 1
            } else if period.end < today {
                total += 1
            }
        }
        return (met, total)
    }
}
