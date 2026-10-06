import SwiftUI
import DisciplineCore

/// The most important screen: today's main activities in the 90-day challenge, one tap to act.
struct DashboardView: View {
    @Environment(SessionStore.self) private var session
    @Environment(HabitsStore.self) private var store
    @Environment(AppContainer.self) private var container

    @State private var actionTarget: Habit?
    @State private var skipTarget: Habit?
    @State private var startingTask: AccountabilityTask?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    SyncStatusBanner(monitor: store.sync, connectivity: container.connectivity)
                    challengeSection
                    content
                }
                .padding(Theme.Spacing.md)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { habitId in
                HabitDetailView(habitId: habitId)
            }
            .navigationDestination(for: DashboardRoute.self) { route in
                switch route {
                case .challenge: ChallengeHubView()
                }
            }
            .habitCompletionFlow(target: $actionTarget)
            .sheet(item: $skipTarget) { habit in
                SkipConfirmationSheet(habit: habit)
            }
            .fullScreenCover(item: $startingTask) { task in
                ExerciseCameraView(task: task, store: store, container: container)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .loading where store.habits.isEmpty:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        case .failed(let error) where store.habits.isEmpty:
            EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn't load your challenge",
                           message: error.localizedDescription, actionTitle: "Try again") { store.restart() }
                .card()
        default:
            if let upcoming = store.upcomingChallenge, store.activeChallenge == nil {
                EmptyStateView(
                    systemImage: "calendar.badge.clock",
                    title: "Your challenge starts \(upcoming.startDate == store.today.adding(days: 1, calendar: store.calendar) ? "tomorrow" : "soon")",
                    message: "Rest up. From day 1, every main activity has to be done each day to keep your streak."
                )
                .card()
            } else if store.activeChallenge != nil {
                accountabilitySection
                todaySection
                weeklySection
            }
        }
    }

    // MARK: Challenge

    @ViewBuilder
    private var challengeSection: some View {
        if let challenge = store.activeChallenge ?? store.upcomingChallenge {
            NavigationLink(value: DashboardRoute.challenge) {
                ChallengeBanner(challenge: challenge,
                                progress: store.activeChallenge?.id == challenge.id ? store.challengeProgress : nil)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.challenge")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(store.today.startDate(calendar: store.calendar).formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(Theme.Typography.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text("Hi, \(session.profile?.displayName ?? "there")")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            Spacer()
            Label("\(store.streak.current)", systemImage: "flame.fill")
                .font(Theme.Typography.headline.monospacedDigit())
                .foregroundStyle(store.streak.current > 0 ? Theme.Palette.accent : Theme.Palette.textTertiary)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Capsule().fill(Theme.Palette.accent.opacity(0.14)))
                .accessibilityLabel("\(store.streak.current) day streak")
                .accessibilityIdentifier("dashboard.streak")
        }
        .padding(.top, Theme.Spacing.md)
    }

    // MARK: Today

    @ViewBuilder
    private var accountabilitySection: some View {
        let open = store.openAccountabilityTasks
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionEyebrow(title: "Accountability", trailing: "\(open.count) due")
                ForEach(open) { task in
                    AccountabilityTaskCard(task: task, habitName: store.habit(id: task.sourceHabitId)?.name) {
                        startingTask = task
                    }
                }
            }
        }
    }

    private var todaySection: some View {
        let commitments = store.todayCommitments
        let outstanding = commitments.filter { $0.state != .done }.count
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "Today", trailing: outstanding == 0 ? "All done" : "\(outstanding) remaining")
            if commitments.isEmpty {
                Text("Nothing scheduled today.")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(commitments) { commitment in
                        NavigationLink(value: commitment.habit.id) {
                            CommitmentRow(commitment: commitment) { actionTarget = commitment.habit }
                        }
                        .accessibilityIdentifier("commitment.row.\(commitment.habit.name)")
                        .contextMenu {
                            if store.canSkip(commitment.habit) {
                                Button("Skip today…", systemImage: "arrow.uturn.forward") { skipTarget = commitment.habit }
                            }
                        }
                        .buttonStyle(.plain)
                        if commitment.id != commitments.last?.id {
                            Divider().overlay(Theme.Palette.hairline).padding(.leading, 72)
                        }
                    }
                }
                .card(padding: 0)
                Text("Every main activity must be done today, or skipped with push-ups, to keep your streak.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    // MARK: This week

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "This week")
            VStack(spacing: Theme.Spacing.md) {
                ForEach(store.activeHabits) { habit in
                    if let summary = store.weekSummary(for: habit) {
                        WeeklyGoalRow(habit: habit, achieved: summary.achieved, target: summary.target)
                    }
                }
            }
            .card()
        }
    }
}

enum DashboardRoute: Hashable {
    case challenge
}

// MARK: - Rows

private struct CommitmentRow: View {
    @Environment(HabitsStore.self) private var store
    let commitment: TodayCommitment
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            HabitIcon(category: commitment.habit.category, isComplete: commitment.state == .done)

            VStack(alignment: .leading, spacing: 3) {
                Text(commitment.habit.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(statusLine)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer(minLength: Theme.Spacing.xs)

            actionButton
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens habit details")
    }

    @ViewBuilder
    private var actionButton: some View {
        switch commitment.state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Palette.success)
                .accessibilityLabel("Done")
        case .awaitingVerification:
            Image(systemName: "hourglass.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Palette.info)
                .accessibilityLabel("Awaiting verification")
        case .accountabilityDue:
            Image(systemName: "figure.strengthtraining.traditional.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Palette.warning)
                .accessibilityLabel("Accountability task due")
        case .open, .inProgress:
            if canActToday {
                Button(action: onAction) {
                    Image(systemName: actionSymbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Palette.accent)
                        .frame(width: 40, height: 40)
                        .background(Circle().strokeBorder(Theme.Palette.accent.opacity(0.6), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actionLabel)
                .accessibilityIdentifier("commitment.action.\(commitment.habit.name)")
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .accessibilityLabel("Logged for today")
            }
        }
    }

    /// A weekly session habit already logged today can't be logged again until tomorrow.
    private var canActToday: Bool { store.canLog(commitment.habit) }

    private var actionSymbol: String {
        if commitment.requirement == .evidence { return "camera.fill" }
        return commitment.habit.unit == .sessions ? "checkmark" : "plus"
    }

    private var actionLabel: String {
        if commitment.requirement == .evidence { return "Submit evidence for \(commitment.habit.name)" }
        return commitment.habit.unit == .sessions ? "Mark \(commitment.habit.name) done" : "Log \(commitment.habit.name)"
    }

    private var statusLine: String {
        let habit = commitment.habit
        let progress = commitment.progress
        switch commitment.state {
        case .done:
            if let latest = commitment.todayCompletions.last { return latest.status.label }
            return habit.frequency == .weekly ? "Weekly target met" : "Done"
        case .awaitingVerification:
            return CompletionStatus.pendingVerification.label
        case .accountabilityDue:
            return "Skipped · accountability task due"
        case .inProgress, .open:
            let periodWord = habit.frequency == .weekly ? "this week" : "today"
            let amount = "\(habit.formatted(progress.achieved)) / \(habit.formatted(progress.target)) \(periodWord)"
            return commitment.requirement == .evidence ? "\(amount) · Photo evidence" : amount
        }
    }

    private var statusColor: Color {
        switch commitment.state {
        case .done: return Theme.Palette.success
        case .awaitingVerification: return Theme.Palette.info
        case .accountabilityDue: return Theme.Palette.warning
        case .inProgress, .open: return Theme.Palette.textSecondary
        }
    }
}

private struct WeeklyGoalRow: View {
    let habit: Habit
    let achieved: Int
    let target: Int

    private var fraction: Double { target > 0 ? Double(achieved) / Double(target) : 0 }
    private var isMet: Bool { achieved >= target }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(habit.name)
                    .font(Theme.Typography.callout.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Text(habit.frequency == .weekly ? "\(achieved)/\(target)" : "\(achieved)/\(target) days")
                    .font(Theme.Typography.callout.monospacedDigit())
                    .foregroundStyle(isMet ? Theme.Palette.success : Theme.Palette.textSecondary)
            }
            ProgressBar(fraction: fraction, tint: isMet ? Theme.Palette.success : Theme.Palette.accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(habit.name): \(achieved) of \(target)\(habit.frequency == .weekly ? "" : " days") this week")
    }
}

// MARK: - Sync

struct SyncStatusBanner: View {
    let monitor: SyncMonitor
    let connectivity: ConnectivityMonitor

    var body: some View {
        if !connectivity.isOnline {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "wifi.slash")
                Text(monitor.isSyncing
                     ? "Offline. \(monitor.pendingWrites) change\(monitor.pendingWrites == 1 ? "" : "s") saved on this device and will sync when you're back online."
                     : "Offline. Changes are saved on this device and will sync when you're back online.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.warning)
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .accessibilityElement(children: .combine)
        } else if let error = monitor.lastError {
            HStack(alignment: .top) {
                InlineMessage(text: "Some changes couldn't be synced: \(error.localizedDescription)")
                Button {
                    monitor.dismissError()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(8)
                }
                .accessibilityLabel("Dismiss")
            }
        } else if monitor.isSyncing {
            Label("Saved on this device, syncing…", systemImage: "arrow.triangle.2.circlepath")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
