import SwiftUI
import DisciplineCore

struct StreakView: View {
    @Environment(HabitsStore.self) private var store
    @State private var selectedDay: DayResolution?

    /// Weeks shown in the calendar (most recent last).
    private let weeksShown = 6

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    hero
                    statsRow
                    milestoneCard
                    calendarCard
                    explanation
                }
                .padding(Theme.Spacing.md)
            }
            .screenBackground()
            .navigationTitle("Streak")
            .sheet(item: $selectedDay) { day in
                DayDetailSheet(resolution: day)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        let streak = store.streak
        return VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "flame.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(streak.current > 0 ? AnyShapeStyle(Theme.Palette.emberGradient) : AnyShapeStyle(Theme.Palette.textTertiary))
                .symbolEffect(.bounce, value: streak.current)
                .accessibilityHidden(true)
            Text("\(streak.current) DAY STREAK")
                .font(Theme.Typography.hero)
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
                .multilineTextAlignment(.center)
            Text(heroMessage(streak))
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .accessibilityElement(children: .combine)
    }

    private func heroMessage(_ streak: StreakSummary) -> String {
        if let today = streak.today, today.resolution.outcome == .pending {
            let open = today.resolution.due.filter { $0.resolution != .resolved }.count
            let lead = streak.current > 0
                ? "You've resolved every required commitment for \(streak.current) consecutive day\(streak.current == 1 ? "" : "s")."
                : "Resolve today's commitments to start a streak."
            return "\(lead) Today: \(open) commitment\(open == 1 ? "" : "s") still open."
        }
        if streak.current == 0 { return "Resolve every commitment due today to start a streak." }
        return "You've resolved every required commitment for \(streak.current) consecutive day\(streak.current == 1 ? "" : "s")."
    }

    private var statsRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            stat("Current", value: store.streak.current)
            stat("Longest", value: store.streak.longest)
        }
    }

    private func stat(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            SectionEyebrow(title: title)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(Theme.Typography.metric)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(value == 1 ? "day" : "days")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    // MARK: Milestones

    private var milestoneCard: some View {
        let streak = store.streak
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "Milestones", trailing: streak.nextMilestone.map { "Next: \($0) days" })
            HStack(spacing: 6) {
                ForEach(StreakSummary.milestones, id: \.self) { milestone in
                    let reached = streak.reachedMilestones.contains(milestone)
                    Text("\(milestone)")
                        .font(Theme.Typography.caption.weight(.bold).monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(reached ? Color.white : Theme.Palette.textTertiary)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(reached ? AnyShapeStyle(Theme.Palette.emberGradient) : AnyShapeStyle(Theme.Palette.surfaceElevated))
                        )
                        .accessibilityLabel("\(milestone) days, \(reached ? "reached" : "not reached")")
                }
            }
            if let next = streak.nextMilestone {
                ProgressBar(fraction: Double(streak.current) / Double(next))
            }
        }
        .card()
    }

    // MARK: Calendar

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "History", trailing: "Last \(weeksShown) weeks")
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { column in
                    let weekday = (column + 1) % 7 + 1 // Monday-first: 2,3,4,5,6,7,1
                    Text(store.calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(weeks, id: \.self) { weekStart in
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { offset in
                        dayCell(weekStart.adding(days: offset, calendar: store.calendar))
                    }
                }
            }
            legend
        }
        .card()
    }

    private var weeks: [DayKey] {
        let currentWeek = store.today.startOfWeek(calendar: store.calendar)
        return (0..<weeksShown).reversed().map { currentWeek.adding(days: -7 * $0, calendar: store.calendar) }
    }

    @ViewBuilder
    private func dayCell(_ day: DayKey) -> some View {
        let resolution = store.resolution(for: day)
        let isToday = day == store.today
        let style = CellStyle(resolution: resolution, isFuture: day > store.today)
        Button {
            if let resolution { selectedDay = resolution }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(style.fill)
                if let symbol = style.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(style.symbolColor)
                } else {
                    Text("\(day.day)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isToday ? Theme.Palette.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(resolution == nil)
        .accessibilityLabel("\(day.startDate(calendar: store.calendar).formatted(date: .abbreviated, time: .omitted)): \(style.label)")
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.md) {
            legendItem(Theme.Palette.success, "Successful")
            legendItem(Theme.Palette.danger, "Missed")
            legendItem(Theme.Palette.info, "Pending")
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Palette.textSecondary)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }

    private var explanation: some View {
        Text("A day is successful when every commitment due that day is resolved. Weekly targets become due only when putting them off would make the target unreachable, so an early week with nothing done yet still counts as on track. Days waiting for verification or an open accountability task stay pending and never break your streak.")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CellStyle {
    let fill: Color
    let symbol: String?
    let symbolColor: Color
    let label: String

    init(resolution: DayResolution?, isFuture: Bool) {
        switch resolution?.outcome {
        case .successful?:
            fill = Theme.Palette.success.opacity(0.85); symbol = "checkmark"; symbolColor = .white; label = "successful"
        case .failed?:
            fill = Theme.Palette.danger.opacity(0.85); symbol = "xmark"; symbolColor = .white; label = "missed"
        case .pending?:
            fill = Theme.Palette.info.opacity(0.25); symbol = "ellipsis"; symbolColor = Theme.Palette.info; label = "pending"
        case .restDay?:
            fill = Theme.Palette.surfaceElevated; symbol = nil; symbolColor = .clear; label = "no commitments"
        case nil:
            fill = Theme.Palette.surfaceElevated.opacity(isFuture ? 0.4 : 1); symbol = nil; symbolColor = .clear
            label = isFuture ? "upcoming" : "no data"
        }
    }
}

/// Why a day ended up successful, missed or pending: each due commitment and its state.
private struct DayDetailSheet: View {
    @Environment(HabitsStore.self) private var store
    let resolution: DayResolution

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Result", value: outcomeLabel)
                }
                Section {
                    if resolution.due.isEmpty {
                        Text(resolution.hasCommitments
                             ? "Nothing was due this day. Weekly targets were still on track."
                             : "No commitments were in effect this day.")
                            .foregroundStyle(Theme.Palette.textSecondary)
                    } else {
                        ForEach(resolution.due, id: \.habitId) { item in
                            HStack {
                                Text(store.habit(id: item.habitId)?.name ?? "Habit")
                                Spacer()
                                Label(label(for: item.resolution), systemImage: symbol(for: item.resolution))
                                    .foregroundStyle(color(for: item.resolution))
                                    .font(Theme.Typography.callout)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                } header: {
                    Text("Due this day")
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(resolution.day.startDate(calendar: store.calendar).formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var outcomeLabel: String {
        switch resolution.outcome {
        case .successful: return "Successful"
        case .failed: return "Missed"
        case .pending: return "Pending"
        case .restDay: return "No commitments"
        }
    }

    private func label(for resolution: CommitmentResolution) -> String {
        switch resolution {
        case .resolved: return "Resolved"
        case .pending: return "Pending"
        case .unresolved: return "Not resolved"
        }
    }

    private func symbol(for resolution: CommitmentResolution) -> String {
        switch resolution {
        case .resolved: return "checkmark.circle.fill"
        case .pending: return "hourglass"
        case .unresolved: return "xmark.circle.fill"
        }
    }

    private func color(for resolution: CommitmentResolution) -> Color {
        switch resolution {
        case .resolved: return Theme.Palette.success
        case .pending: return Theme.Palette.info
        case .unresolved: return Theme.Palette.danger
        }
    }
}
