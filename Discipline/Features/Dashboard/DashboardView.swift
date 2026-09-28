import SwiftUI
import DisciplineCore

/// The most important screen: what's due today, how the week is going, and one tap to act.
struct DashboardView: View {
    @Environment(SessionStore.self) private var session
    @Environment(HabitsStore.self) private var store
    @Environment(AppContainer.self) private var container

    @State private var creatingHabit = false
    @State private var actionTarget: Habit?
    @State private var skipTarget: Habit?
    @State private var startingTask: AccountabilityTask?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    SyncStatusBanner(monitor: store.sync)
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
            .sheet(isPresented: $creatingHabit) {
                HabitEditorView(habit: nil, userId: store.userId, today: store.today, calendar: store.calendar)
            }
            .habitCompletionFlow(target: $actionTarget)
            .sheet(item: $skipTarget) { habit in
                SkipConfirmationSheet(habit: habit)
            }
            .fullScreenCover(item: $startingTask) { task in
                ExerciseCameraView(task: task, store: store, container: container)
            }
            .alert("Couldn't add habits", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
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
            EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn't load your habits",
                           message: error.localizedDescription, actionTitle: "Try again") { store.restart() }
                .card()
        default:
            if store.activeHabits.isEmpty {
                emptyState
            } else {
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
        } else if !store.activeHabits.isEmpty {
            NavigationLink(value: DashboardRoute.challenge) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.Palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start a challenge")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text("Commit for a set number of days with rules you choose.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.Palette.textTertiary)
                }
                .card()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.startChallenge")
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
            if store.streak.current > 0 {
                Label("\(store.streak.current)", systemImage: "flame.fill")
                    .font(Theme.Typography.headline.monospacedDigit())
                    .foregroundStyle(Theme.Palette.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Capsule().fill(Theme.Palette.accent.opacity(0.14)))
                    .accessibilityLabel("\(store.streak.current) day streak")
            }
            Button {
                creatingHabit = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.Palette.emberGradient))
            }
            .accessibilityLabel("New habit")
            .accessibilityIdentifier("dashboard.addHabit")
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
        let outstanding = commitments.filter(\.isOutstanding).count
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "Today", trailing: outstanding == 0 ? "All done" : "\(outstanding) remaining")
            if commitments.isEmpty {
                Text("Nothing scheduled today. Enjoy the rest day.")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(commitments) { commitment in
                        NavigationLink(value: commitment.habit.id) {
                            CommitmentRow(commitment: commitment) { actionTarget = commitment.habit }
                        }
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
            }
        }
    }

    // MARK: Weekly goals

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "Weekly goals")
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

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            EmptyStateView(
                systemImage: "checklist",
                title: "Set your first commitment",
                message: "Habits are the commitments you'll hold yourself to, like gym 4× a week or 100 pages of reading.",
                actionTitle: "Create a habit"
            ) { creatingHabit = true }
            .card()

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Quick start", systemImage: "bolt.fill")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Gym 4×/week · Running 2×/week · Reading 100 pages/week · Cold plunge 3×/week")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                NavigationLink(value: DashboardRoute.challenge) {
                Label("Or start the 75 Day Discipline challenge", systemImage: "flame.fill")
                    .font(Theme.Typography.callout.weight(.semibold))
            }
            .accessibilityIdentifier("dashboard.emptyChallenge")

            Button("Add these habits") {
                    do {
                        try store.addStarterHabits()
                    } catch {
                        errorMessage = AppError.from(error).localizedDescription
                    }
                }
                .buttonStyle(.secondary(tint: Theme.Palette.accent))
                .accessibilityIdentifier("dashboard.addStarter")
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

    var body: some View {
        if let error = monitor.lastError {
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
