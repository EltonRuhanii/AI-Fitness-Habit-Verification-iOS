import SwiftUI
import DisciplineCore

/// The 90-day challenge setup: weekly routine, two new skills, optional extras, then the rules
/// to accept. Shown whenever the participant has no active or upcoming challenge.
struct RoutineSetupView: View {
    enum Step: Int, CaseIterable {
        case intro, routine, skills, extras, review
    }

    @Environment(HabitsStore.self) private var store
    @Environment(AppContainer.self) private var container

    @State private var step: Step = .intro
    @State private var setup = RoutineSetup(workoutWeekdays: [2, 3, 5, 6], runWeekdays: [4, 7])
    @State private var startsTomorrow = false
    @State private var acceptsRules = false
    @State private var isStarting = false
    @State private var errorMessage: String?

    /// Monday-first display order (1 = Sunday … 7 = Saturday).
    private static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    stepHeader
                    switch step {
                    case .intro: intro
                    case .routine: routine
                    case .skills: skills
                    case .extras: extras
                    case .review: review
                    }
                    if let errorMessage { InlineMessage(text: errorMessage) }
                }
                .padding(Theme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .intro {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { move(by: -1) }
                            .accessibilityIdentifier("setup.back")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomButton }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Steps

    private var stepHeader: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Theme.Palette.accent : Theme.Palette.surfaceElevated)
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Image(systemName: "flame.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Theme.Palette.emberGradient)
            Text("\(RoutinePlanner.durationDays) Day Discipline")
                .font(Theme.Typography.hero)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("For the next \(RoutinePlanner.durationDays) days you follow one routine: your workouts, your runs and two new skills you practise for at least an hour every day.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            ruleLine("camera.fill", "Every activity is proven with a photo, checked by AI.")
            ruleLine("flame", "Finish every main activity each day to grow your streak.")
            ruleLine("arrow.counterclockwise", "Leave one unfinished and your streak restarts from 0.")
            ruleLine("figure.strengthtraining.traditional", "Can't make it? Skip with 50 push-ups, counted by the camera.")
            if container.configuration.backend == .demo {
                Button("Load a demo challenge (day 46)") { loadDemo() }
                    .buttonStyle(.secondary)
                    .padding(.top, Theme.Spacing.md)
                    .accessibilityIdentifier("setup.loadDemo")
                Text("Demo mode only: a challenge 45 days in, with two missed days, a 24-day streak, AI results and resolved skips.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    private func ruleLine(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(Theme.Palette.accent)
            Text(text)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var routine: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            title("Your weekly routine", "Pick the days you train. These days are fixed for all 90 days.")
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionEyebrow(title: "Workouts", trailing: "\(setup.workoutWeekdays.count) per week")
                weekdayPicker($setup.workoutWeekdays, id: "setup.workout")
            }
            .card()
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionEyebrow(title: "Runs", trailing: setup.runWeekdays.isEmpty ? "None" : "\(setup.runWeekdays.count) per week")
                weekdayPicker($setup.runWeekdays, id: "setup.run")
            }
            .card()
        }
    }

    private var skills: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            title("Two new skills", "Something you've wanted to learn. You'll practise each for at least \(RoutinePlanner.minimumSkillMinutes) minutes every day.")
            ForEach(0..<RoutinePlanner.skillCount, id: \.self) { index in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    SectionEyebrow(title: "Skill \(index + 1)")
                    TextField(index == 0 ? "e.g. Guitar" : "e.g. Spanish", text: skillBinding(index))
                        .font(Theme.Typography.headline)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .accessibilityIdentifier("setup.skill\(index + 1)")
                }
                .card()
            }
        }
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            title("Anything else?", "Optional. Add other habits you want to hold yourself to, on the days you choose.")
            ForEach(RoutineExtra.presets) { preset in
                let index = setup.extras.firstIndex { $0.id == preset.id }
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Button {
                        withAnimation(.snappy) { toggle(preset) }
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            HabitIcon(category: preset.category, size: 32)
                            Text(preset.name).font(Theme.Typography.callout.weight(.semibold))
                            Spacer()
                            Image(systemName: index != nil ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(index != nil ? Theme.Palette.accent : Theme.Palette.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(index != nil ? .isSelected : [])
                    .accessibilityIdentifier("setup.extra.\(preset.id)")
                    if let index {
                        weekdayPicker($setup.extras[index].weekdays, id: "setup.extra.\(preset.id)")
                    }
                }
                .card()
            }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            title("Your 90 days", "Review your routine. It can't be changed once the challenge starts.")
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(previewHabits, id: \.name) { habit in
                    HStack(spacing: Theme.Spacing.sm) {
                        HabitIcon(category: habit.category, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.name).font(Theme.Typography.callout.weight(.semibold))
                            Text(habit.summaryLine).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                }
            }
            .card()
            Toggle("Start tomorrow", isOn: $startsTomorrow)
                .font(Theme.Typography.callout)
                .card()
            Text("Runs \(format(startDay)) – \(format(startDay.adding(days: RoutinePlanner.durationDays - 1, calendar: store.calendar))).")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            Button {
                withAnimation(.snappy) { acceptsRules.toggle() }
            } label: {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: acceptsRules ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(acceptsRules ? Theme.Palette.success : Theme.Palette.textTertiary)
                    Text("I accept the rules: every main activity, every day, proven with a photo. Missing one resets my streak to 0; a skip costs 50 push-ups.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(acceptsRules ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("setup.accept")
        }
    }

    private func title(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(message)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func weekdayPicker(_ selection: Binding<[Int]>, id: String) -> some View {
        HStack(spacing: 6) {
            ForEach(Self.weekdayOrder, id: \.self) { weekday in
                let isOn = selection.wrappedValue.contains(weekday)
                Button {
                    if isOn {
                        selection.wrappedValue.removeAll { $0 == weekday }
                    } else {
                        selection.wrappedValue.append(weekday)
                        selection.wrappedValue.sort()
                    }
                } label: {
                    Text(store.calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(Theme.Typography.callout.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(isOn ? Color.white : Theme.Palette.textSecondary)
                        .background(Circle().fill(isOn ? Theme.Palette.accent : Theme.Palette.surfaceElevated))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.calendar.standaloneWeekdaySymbols[weekday - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("\(id).\(weekday)")
            }
        }
    }

    // MARK: Navigation

    private var bottomButton: some View {
        Group {
            if step == .review {
                Button("Start the challenge") { start() }
                    .buttonStyle(.primary(isLoading: isStarting))
                    .disabled(!acceptsRules || isStarting)
                    .accessibilityIdentifier("setup.start")
            } else {
                Button(step == .intro ? "Set up my routine" : "Next") { next() }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("setup.next")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Palette.background)
    }

    private func next() {
        errorMessage = nil
        switch step {
        case .routine where setup.workoutWeekdays.isEmpty:
            errorMessage = RoutineError.noWorkoutDays.message
            return
        case .skills:
            if let error = skillsError {
                errorMessage = error.message
                return
            }
        case .extras:
            if let incomplete = setup.extras.first(where: { $0.weekdays.isEmpty }) {
                errorMessage = RoutineError.extraIncomplete(incomplete.name).message
                return
            }
        default:
            break
        }
        move(by: 1)
    }

    private func move(by delta: Int) {
        guard let target = Step(rawValue: step.rawValue + delta) else { return }
        errorMessage = nil
        withAnimation(.snappy) { step = target }
    }

    private var skillsError: RoutineError? {
        do {
            var check = setup
            check.workoutWeekdays = [2]
            check.extras = []
            try RoutinePlanner.validate(check)
            return nil
        } catch let error as RoutineError {
            return error
        } catch {
            return nil
        }
    }

    private func start() {
        isStarting = true
        defer { isStarting = false }
        do {
            try store.startRoutine(setup, startDate: startDay, rulesAccepted: acceptsRules)
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }

    private func loadDemo() {
        do {
            _ = try DemoSeeder.seed(container: container, store: store)
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }

    // MARK: Data

    private var startDay: DayKey { startsTomorrow ? store.today.adding(days: 1, calendar: store.calendar) : store.today }

    private var previewHabits: [Habit] {
        (try? RoutinePlanner.habits(for: setup, userId: store.userId, startDate: startDay)) ?? []
    }

    private func skillBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { setup.skills.indices.contains(index) ? setup.skills[index] : "" },
            set: { value in
                while setup.skills.count <= index { setup.skills.append("") }
                setup.skills[index] = value
            }
        )
    }

    private func toggle(_ preset: RoutineExtra) {
        if let index = setup.extras.firstIndex(where: { $0.id == preset.id }) {
            setup.extras.remove(at: index)
        } else {
            var extra = preset
            extra.weekdays = [2, 4, 6]
            setup.extras.append(extra)
        }
    }

    private func format(_ day: DayKey) -> String {
        day.startDate(calendar: store.calendar).formatted(date: .abbreviated, time: .omitted)
    }
}

extension RoutineError {
    var message: String {
        switch self {
        case .noWorkoutDays: return "Choose at least one workout day."
        case .skillsIncomplete: return "Name both skills you want to learn."
        case .duplicateSkills: return "Choose two different skills."
        case .extraIncomplete(let name): return "Choose at least one day for \(name)."
        }
    }
}

extension ChallengePlanError {
    var message: String {
        switch self {
        case .emptyName: return "Give your challenge a name."
        case .invalidDuration: return "Choose a duration between 7 and 365 days."
        case .rulesNotAccepted: return "Accept the rules to start the challenge."
        case .noHabits: return "Choose at least one activity for the challenge."
        case .alreadyActive: return "You already have a challenge in progress."
        case .startInPast: return "A challenge can't start in the past."
        }
    }
}
