import Foundation
import Observation
import DisciplineCore

/// Live habit and completion state for the signed-in participant. All calculations are
/// delegated to `DisciplineCore`; this type only loads data and performs actions.
@MainActor
@Observable
final class HabitsStore {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(AppError)
    }

    /// How far back completions are loaded. Long enough for a 75-day challenge's streak;
    /// longer history is persisted server-side as daily research records (Phase 10).
    static let historyDays = 120

    private(set) var habits: [Habit] = []
    private(set) var completions: [HabitCompletion] = []
    private(set) var accountabilityTasks: [AccountabilityTask] = []
    private(set) var loadState: LoadState = .loading
    private(set) var today: DayKey
    /// Incremented on every successful completion; drives success haptics.
    private(set) var completionEvents = 0
    /// Day outcomes and streaks over the loaded history, recomputed whenever data changes.
    private(set) var streak: StreakSummary = .empty

    let calendar: Calendar
    let userId: String
    let condition: TrackingCondition
    let sync: SyncMonitor

    private let habitRepository: HabitRepository
    private let completionRepository: CompletionRepository
    private let accountabilityRepository: AccountabilityRepository
    private var listeners: [Task<Void, Never>] = []
    /// Skipping rules. Phase 9 replaces these defaults with the active challenge's rules.
    let rules = ChallengeRules()

    init(profile: UserProfile, container: AppContainer, calendar: Calendar = .disciplineCalendar()) {
        self.userId = profile.id
        self.condition = profile.trackingCondition
        self.calendar = calendar
        self.today = DayKey.today(calendar: calendar)
        self.habitRepository = container.habits
        self.completionRepository = container.completions
        self.accountabilityRepository = container.accountability
        self.sync = container.sync
    }

    // MARK: Derived state

    var activeHabits: [Habit] {
        habits.filter(\.isActive).sorted { $0.createdAt < $1.createdAt }
    }

    var todayCommitments: [TodayCommitment] {
        TodayCommitments.build(habits: activeHabits, completions: completions, today: today, condition: condition, calendar: calendar)
    }

    func weekSummary(for habit: Habit) -> (achieved: Int, target: Int)? {
        HabitSchedule.weekSummary(for: habit, containing: today, completions: completions, calendar: calendar)
    }

    func completions(for habit: Habit) -> [HabitCompletion] {
        completions.filter { $0.habitId == habit.id }.sorted { $0.createdAt > $1.createdAt }
    }

    func progress(for habit: Habit) -> HabitProgress? {
        HabitSchedule.progress(for: habit, on: today, completions: completions, calendar: calendar)
    }

    func requirement(for habit: Habit) -> CompletionRequirement {
        CompletionPlanner.requirement(for: habit, condition: condition)
    }

    func canLogSession(for habit: Habit) -> Bool {
        CompletionPlanner.canLogSession(for: habit, on: today, completions: completions, calendar: calendar)
    }

    /// Whether the habit's primary action is available today in this participant's condition.
    func canLog(_ habit: Habit) -> Bool {
        guard HabitSchedule.isScheduled(habit, on: today, calendar: calendar) else { return false }
        if requirement(for: habit) == .evidence {
            return CompletionPlanner.activeCompletions(for: habit, on: today, in: completions).count
                < CompletionPlanner.maxSessionsPerDay(for: habit)
        }
        return habit.unit != .sessions || canLogSession(for: habit)
    }

    // MARK: Accountability

    func canSkip(_ habit: Habit) -> Bool {
        AccountabilityPlanner.canSkip(habit, on: today, completions: completions, rules: rules, calendar: calendar)
    }

    func skipConsequence(for habit: Habit) -> AccountabilityTemplate? {
        AccountabilityPlanner.consequence(for: habit, rules: rules)
    }

    /// Tasks the participant can still act on, soonest deadline first. Uses the effective
    /// status so an overdue task never appears doable before the server expires it.
    var openAccountabilityTasks: [AccountabilityTask] {
        let now = Date()
        return accountabilityTasks
            .filter { AccountabilityLifecycle.effectiveStatus(of: $0, now: now).isOpen }
            .sorted { $0.deadline < $1.deadline }
    }

    func accountabilityTask(id: String) -> AccountabilityTask? {
        accountabilityTasks.first { $0.id == id }
    }

    func habit(id: String) -> Habit? {
        habits.first { $0.id == id }
    }

    // MARK: Loading

    func start() {
        guard listeners.isEmpty else { return }
        let from = today.adding(days: -Self.historyDays, calendar: calendar)

        listeners.append(Task { [weak self, habitRepository, userId] in
            do {
                for try await habits in habitRepository.observeHabits(userId: userId) {
                    self?.habits = habits
                    self?.markLoaded()
                    self?.recomputeStreak()
                }
            } catch {
                self?.loadState = .failed(AppError.from(error))
            }
        })
        listeners.append(Task { [weak self, completionRepository, userId] in
            do {
                for try await completions in completionRepository.observeCompletions(userId: userId, from: from) {
                    self?.completions = completions
                    self?.recomputeStreak()
                }
            } catch {
                self?.loadState = .failed(AppError.from(error))
            }
        })
        listeners.append(Task { [weak self, accountabilityRepository, userId] in
            do {
                for try await tasks in accountabilityRepository.observeTasks(userId: userId) {
                    self?.accountabilityTasks = tasks
                    self?.recomputeStreak()
                }
            } catch {
                self?.loadState = .failed(AppError.from(error))
            }
        })
    }

    func restart() {
        listeners.forEach { $0.cancel() }
        listeners.removeAll()
        loadState = .loading
        start()
    }

    /// Call when the app returns to the foreground so "today" rolls over at midnight and
    /// overdue accountability tasks are re-evaluated.
    func refreshToday() {
        let now = DayKey.today(calendar: calendar)
        if now != today {
            today = now
        }
        restart()
    }

    private func recomputeStreak() {
        streak = StreakCalculator.summarize(
            habits: habits,
            completions: completions,
            tasks: accountabilityTasks,
            rules: rules,
            from: today.adding(days: -Self.historyDays, calendar: calendar),
            today: today,
            calendar: calendar
        )
    }

    func resolution(for day: DayKey) -> DayResolution? {
        streak.days.first { $0.resolution.day == day }?.resolution
    }

    private func markLoaded() {
        if loadState != .loaded { loadState = .loaded }
    }

    // MARK: Actions

    func save(_ habit: Habit) throws {
        let trimmed = habit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError.validation("Give your habit a name.") }
        var habit = habit
        habit.name = trimmed
        habit.verificationType = habit.requiresEvidence ? .photoAI : .manual
        try habitRepository.save(habit)
    }

    /// Archives from today on: the habit keeps its history but is no longer due.
    func archive(_ habit: Habit) throws {
        var archived = habit
        archived.isActive = false
        let yesterday = today.adding(days: -1, calendar: calendar)
        if archived.endDate.map({ $0 > yesterday }) ?? true {
            archived.endDate = yesterday
        }
        try habitRepository.save(archived)
    }

    func addStarterHabits() throws {
        let existing = Set(activeHabits.map { $0.name.lowercased() })
        for habit in HabitTemplates.disciplineStarter(userId: userId, startDate: today) where !existing.contains(habit.name.lowercased()) {
            try habitRepository.save(habit)
        }
    }

    /// Builds (but does not save) a pending completion for photo evidence submitted today.
    func makeEvidenceSubmission(for habit: Habit, evidenceId: String, quantity: Int) throws -> HabitCompletion {
        do {
            return try CompletionPlanner.makeEvidenceSubmission(
                habit: habit,
                day: today,
                evidenceId: evidenceId,
                quantity: quantity,
                condition: condition,
                existing: completions,
                calendar: calendar
            )
        } catch let error as CompletionPlanError {
            throw AppError.validation(error.message(for: habit))
        }
    }

    func noteCompletionEvent() {
        completionEvents += 1
    }

    /// Records a skip the participant has explicitly accepted, creating its accountability task.
    @discardableResult
    func acceptSkip(_ habit: Habit) throws -> AccountabilityTask {
        do {
            let plan = try AccountabilityPlanner.planSkip(
                habit: habit, day: today, condition: condition, existing: completions, rules: rules, calendar: calendar
            )
            try accountabilityRepository.recordSkip(plan)
            return plan.task
        } catch let error as SkipPlanError {
            throw AppError.validation(error.message(for: habit))
        }
    }

    /// Marks a task as started (pending → inProgress). Completion is decided by the server.
    func markStarted(_ task: AccountabilityTask) throws {
        guard task.status == .pending else { return }
        var started = task
        started.status = .inProgress
        try accountabilityRepository.save(started)
    }

    /// Logs a self-reported completion for today.
    func logSelfReport(_ habit: Habit, quantity: Int = 1) throws {
        do {
            let completion = try CompletionPlanner.makeSelfReport(
                habit: habit,
                day: today,
                quantity: quantity,
                condition: condition,
                existing: completions,
                calendar: calendar
            )
            try completionRepository.save(completion)
            completionEvents += 1
        } catch let error as CompletionPlanError {
            throw AppError.validation(error.message(for: habit))
        }
    }
}

extension SkipPlanError {
    func message(for habit: Habit) -> String {
        switch self {
        case .notScheduled: return "\(habit.name) isn't scheduled today."
        case .skippingNotAllowed: return "Skipping isn't allowed by your challenge rules."
        case .notSkippable: return "\(habit.name) can't be skipped. Only session habits can be skipped."
        case .alreadyResolvedToday: return "\(habit.name) is already logged or skipped for today."
        }
    }
}

extension CompletionPlanError {
    func message(for habit: Habit) -> String {
        switch self {
        case .notScheduled: return "\(habit.name) isn't scheduled today."
        case .alreadyCompletedToday: return "\(habit.name) is already logged for today."
        case .invalidQuantity: return "Enter an amount between 1 and 10,000."
        case .evidenceRequired: return "\(habit.name) needs photo evidence in your tracking mode."
        case .evidenceNotApplicable: return "\(habit.name) is self-reported in your tracking mode."
        }
    }
}
