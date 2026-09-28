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

    /// How far back completions are loaded (covers the current and previous month).
    static let historyDays = 62

    private(set) var habits: [Habit] = []
    private(set) var completions: [HabitCompletion] = []
    private(set) var loadState: LoadState = .loading
    private(set) var today: DayKey
    /// Incremented on every successful completion; drives success haptics.
    private(set) var completionEvents = 0

    let calendar: Calendar
    let userId: String
    let condition: TrackingCondition
    let sync: SyncMonitor

    private let habitRepository: HabitRepository
    private let completionRepository: CompletionRepository
    private var tasks: [Task<Void, Never>] = []

    init(profile: UserProfile, container: AppContainer, calendar: Calendar = .disciplineCalendar()) {
        self.userId = profile.id
        self.condition = profile.trackingCondition
        self.calendar = calendar
        self.today = DayKey.today(calendar: calendar)
        self.habitRepository = container.habits
        self.completionRepository = container.completions
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

    // MARK: Loading

    func start() {
        guard tasks.isEmpty else { return }
        let from = today.adding(days: -Self.historyDays, calendar: calendar)

        tasks.append(Task { [weak self, habitRepository, userId] in
            do {
                for try await habits in habitRepository.observeHabits(userId: userId) {
                    self?.habits = habits
                    self?.markLoaded()
                }
            } catch {
                self?.loadState = .failed(AppError.from(error))
            }
        })
        tasks.append(Task { [weak self, completionRepository, userId] in
            do {
                for try await completions in completionRepository.observeCompletions(userId: userId, from: from) {
                    self?.completions = completions
                }
            } catch {
                self?.loadState = .failed(AppError.from(error))
            }
        })
    }

    func restart() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        loadState = .loading
        start()
    }

    /// Call when the app returns to the foreground so "today" rolls over at midnight.
    func refreshToday() {
        let now = DayKey.today(calendar: calendar)
        if now != today {
            today = now
            restart()
        }
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

    func archive(_ habit: Habit) throws {
        var archived = habit
        archived.isActive = false
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
