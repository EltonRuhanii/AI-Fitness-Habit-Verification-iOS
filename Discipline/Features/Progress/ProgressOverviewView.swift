import Charts
import SwiftUI
import DisciplineCore

/// Progress analytics: day success, weekly chart, per-habit adherence, completion methods,
/// AI verification outcomes and accountability. Named to avoid clashing with SwiftUI's `ProgressView`.
struct ProgressOverviewView: View {
    enum Period: String, CaseIterable, Identifiable {
        case week = "7 days"
        case month = "30 days"
        case all = "All"

        var id: String { rawValue }

        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .all: return nil
            }
        }
    }

    @Environment(HabitsStore.self) private var store
    @State private var period: Period = .month

    var body: some View {
        NavigationStack {
            Group {
                if store.habits.isEmpty {
                    EmptyStateView(
                        systemImage: "chart.bar.xaxis",
                        title: "Progress will appear here",
                        message: "Complete habits for a few days to see your success rate, verification results and accountability history."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            Picker("Period", selection: $period) {
                                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("progress.period")

                            let summary = self.summary
                            headline(summary)
                            weeklyChart(summary)
                            habitsCard(summary)
                            completionsCard(summary)
                            accountabilityCard(summary)
                        }
                        .padding(Theme.Spacing.md)
                    }
                }
            }
            .screenBackground()
            .navigationTitle("Progress")
        }
    }

    private var summary: ProgressSummary {
        let from = period.days.map { store.today.adding(days: -($0 - 1), calendar: store.calendar) }
            ?? store.today.adding(days: -HabitsStore.historyDays, calendar: store.calendar)
        return ProgressCalculator.summary(days: store.streak.days, habits: store.habits, completions: store.completions,
                                          tasks: store.accountabilityTasks, from: from, through: store.today,
                                          today: store.today, calendar: store.calendar)
    }

    // MARK: Cards

    private func headline(_ summary: ProgressSummary) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            metric("Day success", summary.daySuccessRate.map(percent) ?? "–",
                   detail: "\(summary.successfulDays) of \(summary.successfulDays + summary.failedDays) days")
            metric("Current streak", "\(store.streak.current)", detail: "longest \(store.streak.longest)")
        }
    }

    private func metric(_ title: String, _ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            SectionEyebrow(title: title)
            Text(value)
                .font(Theme.Typography.metric)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func weeklyChart(_ summary: ProgressSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "Days per week", trailing: "Last 8 weeks")
            Chart {
                ForEach(summary.weeks) { week in
                    BarMark(x: .value("Week", week.weekStart.startDate(calendar: store.calendar), unit: .weekOfYear),
                            y: .value("Days", week.successful))
                        .foregroundStyle(by: .value("Outcome", "Successful"))
                    BarMark(x: .value("Week", week.weekStart.startDate(calendar: store.calendar), unit: .weekOfYear),
                            y: .value("Days", week.failed))
                        .foregroundStyle(by: .value("Outcome", "Missed"))
                }
            }
            .chartForegroundStyleScale(["Successful": Theme.Palette.success, "Missed": Theme.Palette.danger])
            .chartYScale(domain: 0...7)
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 180)
            .accessibilityLabel("Successful and missed days per week for the last 8 weeks")
        }
        .card()
    }

    private func habitsCard(_ summary: ProgressSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionEyebrow(title: "Targets met")
            ForEach(summary.habits) { item in
                if let habit = store.habit(id: item.habitId) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(habit.name).font(Theme.Typography.callout.weight(.semibold))
                            Spacer()
                            Text(item.total > 0 ? "\(item.met)/\(item.total) \(habit.frequency == .weekly ? "weeks" : "days")" : "–")
                                .font(Theme.Typography.callout.monospacedDigit())
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        ProgressBar(fraction: item.rate ?? 0, tint: (item.rate ?? 0) >= 0.8 ? Theme.Palette.success : Theme.Palette.accent)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card()
    }

    private func completionsCard(_ summary: ProgressSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "Completions")
            row("Completed", "\(summary.totalCompleted)")
            row("Self-reported", "\(summary.selfReported)")
            row("Verified by AI", "\(summary.verified)")
            row("Evidence not accepted", "\(summary.rejected)")
            row("Uncertain", "\(summary.uncertain)")
            if let rate = summary.verificationRate {
                row("Verification rate", percent(rate))
            }
        }
        .card()
    }

    private func accountabilityCard(_ summary: ProgressSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "Accountability")
            row("Skips", "\(summary.skipped)")
            row("Tasks completed", "\(summary.accountabilityCompleted)")
            row("Tasks missed", "\(summary.accountabilityFailed)")
            row("Tasks open", "\(summary.accountabilityOpen)")
        }
        .card()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.Palette.textPrimary).monospacedDigit()
        }
        .font(Theme.Typography.callout)
        .accessibilityElement(children: .combine)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
