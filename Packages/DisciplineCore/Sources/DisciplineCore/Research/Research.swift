import Foundation

/// Builds research records from a participant's resolved history. Mirrored server-side
/// (`firebase/functions/src/research/records.ts`), which writes the authoritative records.
public enum DailyRecordBuilder {
    /// - Parameter confidences: verification id → model confidence for decided verifications.
    /// - Returns: one record per day on which the participant had commitments in effect.
    public static func build(
        participantId: String,
        condition: TrackingCondition,
        summary: StreakSummary,
        habits: [Habit],
        completions: [HabitCompletion],
        tasks: [AccountabilityTask],
        confidences: [String: Double] = [:],
        now: Date = Date()
    ) -> [DailyRecord] {
        summary.days.compactMap { streakDay -> DailyRecord? in
            let resolution = streakDay.resolution
            guard resolution.hasCommitments else { return nil }
            let scope = Set(habits.filter { streakDay.challengeId == nil || $0.challengeId == streakDay.challengeId }.map(\.id))
            let events = completions.filter { $0.day == resolution.day && scope.contains($0.habitId) }
            let dayTasks = tasks.filter { $0.day == resolution.day && scope.contains($0.sourceHabitId) }
            let confidenceValues = events.compactMap { $0.verificationId.flatMap { confidences[$0] } }
            func count(_ status: CompletionStatus) -> Int { events.filter { $0.status == status }.count }

            return DailyRecord(
                participantId: participantId,
                challengeId: streakDay.challengeId,
                day: resolution.day,
                trackingCondition: condition,
                requiredHabits: resolution.due.count,
                completedHabits: resolution.due.filter { $0.resolution == .resolved }.count,
                skippedHabits: events.filter { $0.method == .accountabilityExercise }.count,
                verifiedHabits: count(.verified),
                rejectedHabits: count(.rejected),
                uncertainHabits: count(.uncertain),
                selfReportedHabits: count(.selfReported),
                accountabilityTasks: dayTasks.count,
                accountabilityTasksCompleted: dayTasks.filter { $0.status == .completed }.count,
                accountabilityTasksFailed: dayTasks.filter {
                    let status = AccountabilityLifecycle.effectiveStatus(of: $0, now: now)
                    return status == .failed || status == .expired
                }.count,
                verificationCount: confidenceValues.count,
                verificationConfidenceSum: confidenceValues.reduce(0, +),
                outcome: resolution.outcome,
                streakBefore: streakDay.streakBefore,
                streakAfter: streakDay.streakAfter,
                resolverVersion: DayResolver.version
            )
        }
    }
}

/// Aggregate, anonymous statistics per experimental condition.
public struct ConditionStatistics: Equatable, Sendable {
    public var participants = 0
    public var successfulDays = 0
    public var failedDays = 0
    public var pendingDays = 0
    public var requiredCommitments = 0
    public var resolvedCommitments = 0
    public var selfReported = 0
    public var verified = 0
    public var rejected = 0
    public var uncertain = 0
    public var skipped = 0
    public var accountabilityTasks = 0
    public var accountabilityCompleted = 0
    public var accountabilityFailed = 0
    public var verificationCount = 0
    public var verificationConfidenceSum = 0.0
    public var meanCurrentStreak: Double?
    public var meanLongestStreak: Double?

    public init() {}

    private static func ratio(_ numerator: Int, _ denominator: Int) -> Double? {
        denominator > 0 ? Double(numerator) / Double(denominator) : nil
    }

    /// Successful days / decided days (pending excluded).
    public var daySuccessRate: Double? { Self.ratio(successfulDays, successfulDays + failedDays) }
    /// Resolved due commitments / due commitments: the primary adherence measure.
    public var adherence: Double? { Self.ratio(resolvedCommitments, requiredCommitments) }
    public var verificationRate: Double? { Self.ratio(verified, verified + rejected + uncertain) }
    public var rejectionRate: Double? { Self.ratio(rejected, verified + rejected + uncertain) }
    public var uncertainRate: Double? { Self.ratio(uncertain, verified + rejected + uncertain) }
    public var meanConfidence: Double? { verificationCount > 0 ? verificationConfidenceSum / Double(verificationCount) : nil }
    public var accountabilityCompletionRate: Double? { Self.ratio(accountabilityCompleted, accountabilityCompleted + accountabilityFailed) }
}

public enum ResearchAggregator {
    public static func summarize(_ records: [DailyRecord]) -> [TrackingCondition: ConditionStatistics] {
        var result: [TrackingCondition: ConditionStatistics] = [:]
        for condition in TrackingCondition.allCases {
            let subset = records.filter { $0.trackingCondition == condition }
            var stats = ConditionStatistics()
            let byParticipant = Dictionary(grouping: subset, by: \.participantId)
            stats.participants = byParticipant.count
            for record in subset {
                switch record.outcome {
                case .successful: stats.successfulDays += 1
                case .failed: stats.failedDays += 1
                case .pending: stats.pendingDays += 1
                case .restDay: break
                }
                stats.requiredCommitments += record.requiredHabits
                stats.resolvedCommitments += record.completedHabits
                stats.selfReported += record.selfReportedHabits
                stats.verified += record.verifiedHabits
                stats.rejected += record.rejectedHabits
                stats.uncertain += record.uncertainHabits
                stats.skipped += record.skippedHabits
                stats.accountabilityTasks += record.accountabilityTasks
                stats.accountabilityCompleted += record.accountabilityTasksCompleted
                stats.accountabilityFailed += record.accountabilityTasksFailed
                stats.verificationCount += record.verificationCount
                stats.verificationConfidenceSum += record.verificationConfidenceSum
            }
            if !byParticipant.isEmpty {
                let latest = byParticipant.values.compactMap { $0.max { $0.day < $1.day }?.streakAfter }
                let longest = byParticipant.values.map { $0.map(\.streakAfter).max() ?? 0 }
                stats.meanCurrentStreak = Double(latest.reduce(0, +)) / Double(latest.count)
                stats.meanLongestStreak = Double(longest.reduce(0, +)) / Double(longest.count)
            }
            result[condition] = stats
        }
        return result
    }
}

/// Anonymous CSV export. Columns contain no names, emails, habit names or photos.
public enum ResearchCSV {
    public static let dailyHeader = [
        "participant_id", "date", "condition", "challenge_id", "required_habits", "completed_habits",
        "self_reported", "verified", "rejected", "uncertain", "skipped", "accountability_tasks",
        "accountability_completed", "accountability_failed", "verification_count",
        "mean_verification_confidence", "day_outcome", "day_successful", "streak_before", "streak_after",
        "resolver_version"
    ]

    public static func daily(_ records: [DailyRecord]) -> String {
        let rows = records
            .sorted { ($0.participantId, $0.day) < ($1.participantId, $1.day) }
            .map { r -> [String] in
                [
                    r.participantId, r.day.description, r.trackingCondition.rawValue, r.challengeId ?? "",
                    "\(r.requiredHabits)", "\(r.completedHabits)", "\(r.selfReportedHabits)", "\(r.verifiedHabits)",
                    "\(r.rejectedHabits)", "\(r.uncertainHabits)", "\(r.skippedHabits)", "\(r.accountabilityTasks)",
                    "\(r.accountabilityTasksCompleted)", "\(r.accountabilityTasksFailed)", "\(r.verificationCount)",
                    r.verificationCount > 0 ? format(r.verificationConfidenceSum / Double(r.verificationCount)) : "",
                    r.outcome.rawValue, r.daySuccessful ? "1" : "0", "\(r.streakBefore)", "\(r.streakAfter)",
                    r.resolverVersion
                ]
            }
        return encode(header: dailyHeader, rows: rows)
    }

    static func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    static func encode(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
