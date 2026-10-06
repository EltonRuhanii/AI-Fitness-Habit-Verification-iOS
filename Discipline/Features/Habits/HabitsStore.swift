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
    private(set) var challenges: [Challenge] = []
    /// True once the first challenge snapshot arrived, so setup isn't shown before data loads.
    private(set) var challengesLoaded = false
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
    private let challengeRepository: ChallengeRepository
    private let notifications: NotificationScheduler
    private let notificationPreferences: NotificationPreferencesStore
    private var listeners: [Task<Void, Never>] = []
    private var notificationTask: Task<Void, Never>?

    /// The challenge currently in progress, if any. Its rules govern skipping, counting and streaks.
    var activeChallenge: Challenge? { ChallengePlanner.activeChallenge(in: challenges, today: today) }
    var upcomingChallenge: Challenge? { ChallengePlanner.upcomingChallenge(in: challenges, today: today) }
    /// Rules in effect: the active challenge's (locked at start), or the defaults.
    var rules: ChallengeRules { activeChallenge?.rules ?? ChallengeRules() }
    private var countingPolicy: CountingPolicy { CountingPolicy(rules: rules) }

    init(profile: UserProfile, container: AppContainer, calendar: Calendar = .disciplineCalendar()) {
        self.userId = profile.id
        self.condition = profile.trackingCondition
        self.calendar = calendar
        self.today = DayKey.today(calendar: calendar)
        self.habitRepository = container.habits
        self.completionRepository = container.completions
        self.accountabilityRepository = container.accountability
        self.challengeRepository = container.challenges
        self.notifications = container.notifications
        self.notificationPreferences = container.notificationPreferences
        self.sync = container.sync
    }

    // MARK: Derived state

    var activeHabits: [Habit] {
        habits.filter(\.isActive).sorted { $0.createdAt < $1.createdAt }
    }

    var todayCommitments: [TodayCommitment] {
        TodayCommitments.build(habits: activeHabits, completions: completions, today: today, condition: condition,
                               policy: countingPolicy, calendar: calendar)
    }

    func weekSummary(for habit: Habit) -> (achieved: Int, target: Int)? {
        HabitSchedule.weekSummary(for: habit, containing: today, completions: completions, policy: countingPolicy, calendar: calendar)
    }

    func completions(for habit: Habit) -> [HabitCompletion] {
        completions.filter { $0.habitId == habit.id }.sorted { $0.createdAt > $1.createdAt }
    }

    func progress(for habit: Habit) -> HabitProgress? {
        HabitSchedule.progress(for: habit, on: today, completions: completions, policy: countingPolicy, calendar: calendar)
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

    /// Suggested amount when logging: what's left of today's target (a skill's 60 minutes).
    func defaultLogAmount(for habit: Habit) -> Int {
        let remaining = AccountabilityPlanner.remainingAmount(habit, on: today, completions: completions)
        if remaining > 0 { return remaining }
        return habit.unit == .pages ? 20 : 15
    }

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
        listeners.append(Task { [weak self, challengeRepository, userId] in
            do {
                for try await challenges in challengeRepository.observeChallenges(userId: userId) {
                    self?.challenges = challenges
                    self?.challengesLoaded = true
                    self?.completeFinishedChallenges()
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

    /// Uses the same history definition as the server's research records: each day is resolved
    /// under the challenge covering it (its habits and rules), or all habits outside challenges.
    private func recomputeStreak() {
        streak = StreakCalculator.summarizeHistory(
            habits: habits,
            completions: completions,
            tasks: accountabilityTasks,
            challenges: challenges,
            from: today.adding(days: -Self.historyDays, calendar: calendar),
            today: today,
            calendar: calendar
        )
        scheduleNotifications()
    }

    // MARK: Notifications

    /// Replans local notifications from the current state (debounced: data often arrives in bursts).
    func scheduleNotifications() {
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            let planned = NotificationPlanner.plan(
                now: Date(),
                calendar: self.calendar,
                preferences: self.notificationPreferences.preferences,
                today: self.today,
                commitments: self.todayCommitments,
                openTasks: self.openAccountabilityTasks,
                streak: self.streak,
                streakEnabled: self.rules.streakEnabled
            )
            await self.notifications.reschedule(planned)
            self.publishWidget()
        }
    }

    /// Today's first unfinished main activities and the streak, for the home-screen widget.
    private func publishWidget() {
        let tomorrow = today.adding(days: 1, calendar: calendar)
        let nextDay = TodayCommitments.build(habits: activeHabits, completions: completions, today: tomorrow,
                                             condition: condition, policy: countingPolicy, calendar: calendar)
        WidgetBridge.publish(WidgetSnapshot.make(
            today: today,
            commitments: todayCommitments,
            streak: rules.streakEnabled ? streak.current : 0,
            progress: challengeProgress,
            nextDayCommitments: nextDay
        ))
    }

    /// Notification permission is requested in context: when the challenge is started.
    private func requestNotifications() {
        Task { [notifications] in
            await notifications.requestAuthorizationIfNeeded()
            self.scheduleNotifications()
        }
    }

    // MARK: Statistics

    struct Statistics {
        var totalCompleted = 0
        var verified = 0
        var selfReported = 0
        var accountabilityCompleted = 0
        var accountabilityFailed = 0
    }

    /// Profile statistics over the loaded history.
    var statistics: Statistics {
        var stats = Statistics()
        let policy = CountingPolicy()
        stats.totalCompleted = completions.filter { policy.counts($0.status) }.count
        stats.verified = completions.filter { $0.status == .verified }.count
        stats.selfReported = completions.filter { $0.status == .selfReported }.count
        let now = Date()
        for task in accountabilityTasks {
            switch AccountabilityLifecycle.effectiveStatus(of: task, now: now) {
            case .completed: stats.accountabilityCompleted += 1
            case .failed, .expired: stats.accountabilityFailed += 1
            default: break
            }
        }
        return stats
    }

    /// Research records for this participant computed on device (demo mode's research preview).
    func localResearchRecords(participantId: String) -> [DailyRecord] {
        DailyRecordBuilder.build(participantId: participantId, condition: condition, summary: streak, habits: habits,
                                 completions: completions, tasks: accountabilityTasks)
    }

    private func completeFinishedChallenges() {
        for var challenge in ChallengePlanner.finishedChallenges(in: challenges, today: today) {
            challenge.status = .completed
            do {
                try challengeRepository.save(challenge)
            } catch {
                Log.data.error("Couldn't complete challenge \(challenge.id, privacy: .public)")
            }
        }
    }

    var challengeProgress: ChallengeProgress? {
        activeChallenge.map { ChallengePlanner.progress(of: $0, days: streak.days, today: today, calendar: calendar) }
    }

    func habits(in challenge: Challenge) -> [Habit] {
        habits.filter { $0.challengeId == challenge.id }
    }

    // MARK: Challenges

    /// Starts a challenge the participant has explicitly accepted. Saves the challenge first,
    /// then its habits (new template habits and adopted existing ones).
    func startChallenge(_ plan: ChallengePlan) throws {
        requestNotifications()
        try challengeRepository.save(plan.challenge)
        for habit in plan.habits {
            try habitRepository.save(habit)
        }
    }

    /// Abandons a challenge. Its habits keep their history but stop being due after today.
    /// The app only runs in challenge mode: without an active or upcoming challenge the
    /// participant has to set up their 90-day routine.
    var needsChallengeSetup: Bool {
        challengesLoaded && activeChallenge == nil && upcomingChallenge == nil
    }

    /// Plans and starts the 90-day challenge from the participant's routine. Habits from before
    /// challenge mode (outside any challenge) stop being due so only the routine counts.
    func startRoutine(_ setup: RoutineSetup, startDate: DayKey, rulesAccepted: Bool) throws {
        let plan: ChallengePlan
        do {
            plan = try RoutinePlanner.plan(setup: setup, ownerId: userId, startDate: startDate,
                                           existingChallenges: challenges, rulesAccepted: rulesAccepted,
                                           today: today, calendar: calendar)
        } catch let error as RoutineError {
            throw AppError.validation(error.message)
        } catch let error as ChallengePlanError {
            throw AppError.validation(error.message)
        }
        for habit in activeHabits where habit.challengeId == nil {
            try archive(habit)
        }
        try startChallenge(plan)
    }

    func abandon(_ challenge: Challenge) throws {
        var abandoned = challenge
        abandoned.status = .abandoned
        try challengeRepository.save(abandoned)
        for habit in habits(in: challenge) where habit.isActive {
            try archive(habit)
        }
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
