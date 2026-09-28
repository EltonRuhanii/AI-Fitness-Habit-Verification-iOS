import SwiftUI
import DisciplineCore

struct HabitDetailView: View {
    @Environment(HabitsStore.self) private var store
    let habitId: String

    @State private var editing = false
    @State private var actionTarget: Habit?

    private var habit: Habit? { store.habits.first { $0.id == habitId } }

    var body: some View {
        Group {
            if let habit {
                content(for: habit)
            } else {
                EmptyStateView(systemImage: "questionmark.folder", title: "Habit not found", message: "It may have been removed on another device.")
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .habitCompletionFlow(target: $actionTarget)
    }

    private func content(for habit: Habit) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header(habit)
                progressCard(habit)
                WeekStrip(habit: habit)
                history(habit)
            }
            .padding(Theme.Spacing.md)
        }
        .safeAreaInset(edge: .bottom) {
            if habit.isActive {
                HabitPrimaryButton(habit: habit) { actionTarget = habit }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Palette.background)
            }
        }
        .toolbar {
            if habit.isActive {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            HabitEditorView(habit: habit, userId: store.userId, today: store.today, calendar: store.calendar)
        }
    }

    private func header(_ habit: Habit) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            HabitIcon(category: habit.category, size: 60, isComplete: store.progress(for: habit)?.isMet == true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(habit.name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(habit.isActive ? habit.summaryLine : "Archived")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func progressCard(_ habit: Habit) -> some View {
        if let progress = store.progress(for: habit) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionEyebrow(title: habit.frequency == .weekly ? "This week" : "Today")
                HStack(alignment: .firstTextBaseline) {
                    Text("\(progress.achieved)")
                        .font(Theme.Typography.metric)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .contentTransition(.numericText())
                    Text("/ \(habit.formatted(progress.target))")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Spacer()
                    if progress.isMet {
                        Label("Target met", systemImage: "checkmark.circle.fill")
                            .font(Theme.Typography.callout.weight(.semibold))
                            .foregroundStyle(Theme.Palette.success)
                    } else {
                        Text("\(habit.formatted(progress.remaining)) to go")
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                ProgressBar(fraction: progress.fraction, tint: progress.isMet ? Theme.Palette.success : Theme.Palette.accent, height: 10)
            }
            .card()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(progress.achieved) of \(habit.formatted(progress.target))\(progress.isMet ? ", target met" : "")")
        } else {
            InlineMessage(text: "Not scheduled today.", style: .info)
        }
    }

    @ViewBuilder
    private func history(_ habit: Habit) -> some View {
        let entries = store.completions(for: habit)
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "History", trailing: "Last \(HabitsStore.historyDays) days")
            if entries.isEmpty {
                Text("Nothing logged yet.")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        HistoryRow(habit: habit, completion: entry, calendar: store.calendar)
                        if entry.id != entries.last?.id {
                            Divider().overlay(Theme.Palette.hairline)
                        }
                    }
                }
                .card(padding: 0)
            }
        }
    }
}

/// The main completion button, labeled for the participant's condition.
struct HabitPrimaryButton: View {
    @Environment(HabitsStore.self) private var store
    let habit: Habit
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.primary)
            .disabled(!isEnabled)
            .accessibilityIdentifier("habit.primaryAction")
    }

    private var isEnabled: Bool {
        guard store.progress(for: habit) != nil else { return false }
        if store.requirement(for: habit) == .evidence { return true }
        return habit.unit != .sessions || store.canLogSession(for: habit)
    }

    private var title: String {
        if store.progress(for: habit) == nil { return "Not scheduled today" }
        if store.requirement(for: habit) == .evidence { return "Submit photo evidence" }
        switch habit.unit {
        case .sessions: return store.canLogSession(for: habit) ? "Mark as done" : "Done for today"
        case .pages: return "Log pages"
        case .minutes: return "Log minutes"
        }
    }
}

private struct HistoryRow: View {
    let habit: Habit
    let completion: HabitCompletion
    let calendar: Calendar

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(completion.day.startDate(calendar: calendar).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(Theme.Typography.callout.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(completion.createdAt.formatted(date: .omitted, time: .shortened) + (habit.unit == .sessions ? "" : " · \(habit.formatted(completion.quantity))"))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            StatusBadge(status: completion.status)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
    }
}

/// Monday–Sunday strip showing which days have a counted completion.
private struct WeekStrip: View {
    @Environment(HabitsStore.self) private var store
    let habit: Habit

    var body: some View {
        let start = store.today.startOfWeek(calendar: store.calendar)
        let policy = CountingPolicy()
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let day = start.adding(days: offset, calendar: store.calendar)
                let done = store.completions.contains { $0.habitId == habit.id && $0.day == day && policy.counts($0.status) }
                let scheduled = HabitSchedule.isScheduled(habit, on: day, calendar: store.calendar)
                VStack(spacing: 6) {
                    Text(store.calendar.veryShortStandaloneWeekdaySymbols[day.weekday(calendar: store.calendar) - 1])
                        .font(Theme.Typography.caption)
                        .foregroundStyle(day == store.today ? Theme.Palette.accent : Theme.Palette.textTertiary)
                    ZStack {
                        Circle()
                            .fill(done ? Theme.Palette.success : Theme.Palette.surfaceElevated)
                            .opacity(scheduled || done ? 1 : 0.35)
                        if done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(day == store.today ? Theme.Palette.accent : .clear, lineWidth: 2))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(store.calendar.standaloneWeekdaySymbols[day.weekday(calendar: store.calendar) - 1]): \(done ? "done" : "not done")")
            }
        }
        .card()
    }
}
