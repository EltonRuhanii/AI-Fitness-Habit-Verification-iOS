import Foundation

/// A calendar day independent of time zone, encoded as `yyyy-MM-dd`.
///
/// Habit completions, daily records and streaks are keyed by the *participant's local
/// calendar day* at the moment of the action. Storing the day explicitly (rather than
/// deriving it from a timestamp later) keeps research data reproducible when a
/// participant travels or when the analysis runs in a different time zone.
public struct DayKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// Parses `yyyy-MM-dd`. Returns `nil` for anything else.
    public init?(string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Midnight at the start of this day in the given calendar.
    public func startDate(calendar: Calendar = .current) -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        let shifted = calendar.date(byAdding: .day, value: days, to: startDate(calendar: calendar)) ?? startDate(calendar: calendar)
        return DayKey(shifted, calendar: calendar)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(to other: DayKey, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: startDate(calendar: calendar), to: other.startDate(calendar: calendar)).day ?? 0
    }

    /// The first day of the week containing this day, using the calendar's `firstWeekday`.
    public func startOfWeek(calendar: Calendar = .current) -> DayKey {
        let date = startDate(calendar: calendar)
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        return DayKey(interval?.start ?? date, calendar: calendar)
    }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar.Component.weekday`.
    public func weekday(calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: startDate(calendar: calendar))
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public static func today(calendar: Calendar = .current, now: Date = Date()) -> DayKey {
        DayKey(now, calendar: calendar)
    }
}

extension DayKey: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let key = DayKey(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid day key '\(raw)', expected yyyy-MM-dd")
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public extension Calendar {
    /// Gregorian calendar with ISO-8601 week semantics (weeks start on Monday).
    /// Used for all weekly-target calculations so "4x per week" means Monday–Sunday.
    static func disciplineCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = timeZone
        return calendar
    }
}
