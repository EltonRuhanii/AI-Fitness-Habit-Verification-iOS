import Foundation

/// What the home-screen widget shows. Written by the app into the shared App Group container
/// whenever data changes; the widget only renders it (it never computes progress itself).
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let name: String
        public let symbolName: String
        public let detail: String

        public init(name: String, symbolName: String, detail: String) {
            self.name = name
            self.symbolName = symbolName
            self.detail = detail
        }
    }

    public static let maxItems = 3
    public static let appGroup = "group.com.eltonruhani.discipline"
    public static let storageKey = "widget.snapshot"

    /// Day the snapshot describes; the widget treats an older snapshot as stale.
    public let day: DayKey
    public let streak: Int
    /// Up to `maxItems` main activities still unfinished today.
    public let items: [Item]
    /// All unfinished main activities today (may exceed `items.count`).
    public let remaining: Int
    public let challengeDay: Int?
    public let challengeLength: Int?
    public let updatedAt: Date
    /// Tomorrow's main activities, so the widget is right after midnight without the app.
    public let nextDayItems: [Item]
    public let nextDayRemaining: Int

    public init(day: DayKey, streak: Int, items: [Item], remaining: Int, challengeDay: Int?, challengeLength: Int?,
                updatedAt: Date, nextDayItems: [Item] = [], nextDayRemaining: Int = 0) {
        self.day = day
        self.streak = streak
        self.items = items
        self.remaining = remaining
        self.challengeDay = challengeDay
        self.challengeLength = challengeLength
        self.updatedAt = updatedAt
        self.nextDayItems = nextDayItems
        self.nextDayRemaining = nextDayRemaining
    }

    public var allDone: Bool { remaining == 0 }

    /// Builds the snapshot from today's commitments: the first unfinished required activities
    /// in dashboard order, each with a short status.
    public static func make(today: DayKey, commitments: [TodayCommitment], streak: Int,
                            progress: ChallengeProgress?, nextDayCommitments: [TodayCommitment] = [],
                            now: Date = Date()) -> WidgetSnapshot {
        let unfinished = commitments.filter { $0.habit.isRequired && $0.state != .done }
        let nextDay = nextDayCommitments.filter(\.habit.isRequired)
        return WidgetSnapshot(day: today, streak: streak, items: items(unfinished), remaining: unfinished.count,
                              challengeDay: progress?.dayNumber, challengeLength: progress?.durationDays, updatedAt: now,
                              nextDayItems: items(nextDay), nextDayRemaining: nextDay.count)
    }

    private static func items(_ commitments: [TodayCommitment]) -> [Item] {
        commitments.prefix(maxItems).map { commitment in
            Item(name: commitment.habit.name, symbolName: commitment.habit.category.symbolName, detail: detail(for: commitment))
        }
    }

    /// What the widget shows on `today`, which may be after the snapshot was written.
    public struct Display: Equatable, Sendable {
        public let streak: Int
        public let items: [Item]
        /// Nil when the snapshot is too old to know today's activities.
        public let remaining: Int?
        public let challengeDay: Int?
        public let challengeLength: Int?

        public init(streak: Int, items: [Item], remaining: Int?, challengeDay: Int?, challengeLength: Int?) {
            self.streak = streak
            self.items = items
            self.remaining = remaining
            self.challengeDay = challengeDay
            self.challengeLength = challengeLength
        }
    }

    /// Today: as written. The next day (app not opened since midnight): tomorrow's activities,
    /// and the streak survives only if every activity was finished. Older: unknown.
    public func display(on today: DayKey, calendar: Calendar) -> Display {
        if today == day {
            return Display(streak: streak, items: items, remaining: remaining,
                           challengeDay: challengeDay, challengeLength: challengeLength)
        }
        let nextChallengeDay = challengeDay.map { $0 + 1 }
        if today == day.adding(days: 1, calendar: calendar) {
            let stillRunning = nextChallengeDay.map { day in challengeLength.map { day <= $0 } ?? true } ?? false
            return Display(streak: allDone ? streak : 0, items: nextDayItems, remaining: nextDayRemaining,
                           challengeDay: stillRunning ? nextChallengeDay : nil, challengeLength: challengeLength)
        }
        return Display(streak: 0, items: [], remaining: nil, challengeDay: nil, challengeLength: challengeLength)
    }

    static func detail(for commitment: TodayCommitment) -> String {
        switch commitment.state {
        case .awaitingVerification: return "Checking photo"
        case .accountabilityDue: return "Push-ups due"
        case .done: return "Done"
        case .open, .inProgress:
            if commitment.habit.unit == .sessions {
                return commitment.requirement == .evidence ? "Photo needed" : "To do"
            }
            return "\(commitment.progress.achieved)/\(commitment.progress.target) \(commitment.habit.unit == .minutes ? "min" : commitment.habit.unit.displayName)"
        }
    }

    public func isCurrent(today: DayKey) -> Bool { day == today }
}
