import SwiftUI
import DisciplineCore

struct HabitEditorView: View {
    @Environment(HabitsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Habit
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var errorMessage: String?
    @State private var confirmsArchive = false

    private let isNew: Bool

    /// Weekday numbers in Monday-first display order (1 = Sunday … 7 = Saturday).
    private static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    init(habit: Habit?, userId: String, today: DayKey, calendar: Calendar) {
        let initial = habit ?? Habit(
            userId: userId,
            name: "",
            category: .gym,
            frequency: .weekly,
            unit: .sessions,
            targetCount: 3,
            startDate: today
        )
        isNew = habit == nil
        _draft = State(initialValue: initial)
        _startDate = State(initialValue: initial.startDate.startDate(calendar: calendar))
        _hasEndDate = State(initialValue: initial.endDate != nil)
        _endDate = State(initialValue: (initial.endDate ?? today.adding(days: 74, calendar: calendar)).startDate(calendar: calendar))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Gym", text: $draft.name)
                        .font(Theme.Typography.headline)
                        .accessibilityIdentifier("editor.name")
                    TextField("Description (optional)", text: $draft.description, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Category") {
                    categoryPicker
                        .listRowInsets(EdgeInsets(top: Theme.Spacing.sm, leading: 0, bottom: Theme.Spacing.sm, trailing: 0))
                }

                Section {
                    Picker("Frequency", selection: $draft.frequency) {
                        Text("Daily").tag(HabitFrequency.daily)
                        Text("Weekly").tag(HabitFrequency.weekly)
                        Text("Set days").tag(HabitFrequency.custom)
                    }
                    .pickerStyle(.segmented)

                    if draft.frequency == .custom {
                        weekdayPicker
                    }

                    Picker("Measured in", selection: $draft.unit) {
                        ForEach(HabitUnit.allCases, id: \.self) { unit in
                            Text(unit.displayName.capitalized).tag(unit)
                        }
                    }
                    .onChange(of: draft.unit) { _, unit in
                        draft.targetCount = defaultTarget(for: unit)
                    }

                    Stepper(value: $draft.targetCount, in: targetRange, step: targetStep) {
                        LabeledContent("Target", value: draft.targetDescription)
                    }
                    .accessibilityIdentifier("editor.target")
                } header: {
                    Text("Commitment")
                } footer: {
                    Text(isCommitmentLocked
                         ? "Locked while \(lockingChallengeName) is active, so earlier days can't be re-scored. You can still rename or archive the habit."
                         : frequencyFooter)
                }
                .disabled(isCommitmentLocked)

                Section {
                    Toggle("Require photo evidence", isOn: $draft.requiresEvidence)
                        .disabled(isCommitmentLocked)
                    Toggle("Required for daily success", isOn: $draft.isRequired)
                        .disabled(isCommitmentLocked)
                } header: {
                    Text("Verification")
                } footer: {
                    Text("With AI-assisted tracking, evidence-required habits are completed by submitting a photo that's automatically checked against criteria for its category. With manual tracking, evidence isn't requested. Optional habits don't affect your streak.")
                }

                if draft.unit == .sessions {
                    Section {
                        Stepper(value: skipTarget, in: 10...100, step: 5) {
                            LabeledContent("Push-ups", value: "\(skipTarget.wrappedValue)")
                        }
                        .accessibilityIdentifier("editor.skipTarget")
                    } header: {
                        Text("If you skip")
                    } footer: {
                        Text("Skipping a session creates this accountability task, counted by your camera. You'll see it and confirm it every time before skipping. More exercises will be added.")
                    }
                }

                Section("Dates") {
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                        .disabled(isCommitmentLocked)
                    Toggle("End date", isOn: $hasEndDate.animation())
                    if hasEndDate {
                        DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }

                if let errorMessage {
                    Section {
                        InlineMessage(text: errorMessage)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if !isNew {
                    Section {
                        Button("Archive habit", role: .destructive) { confirmsArchive = true }
                    } footer: {
                        Text("Archived habits stop appearing in Today. Their history is kept.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(isNew ? "New habit" : "Edit habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                        .accessibilityIdentifier("editor.save")
                }
            }
            .confirmationDialog("Archive \(draft.name)?", isPresented: $confirmsArchive, titleVisibility: .visible) {
                Button("Archive", role: .destructive) { archive() }
            }
        }
    }

    // MARK: Subviews

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(HabitCategory.allCases, id: \.self) { category in
                    let isSelected = draft.category == category
                    Button {
                        draft.category = category
                    } label: {
                        Label(category.displayName, systemImage: category.symbolName)
                            .font(Theme.Typography.callout.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xs)
                            .foregroundStyle(isSelected ? Color.white : Theme.Palette.textPrimary)
                            .background(
                                Capsule().fill(isSelected ? AnyShapeStyle(Theme.Palette.emberGradient) : AnyShapeStyle(Theme.Palette.surfaceElevated))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(Self.weekdayOrder, id: \.self) { weekday in
                let isOn = draft.scheduledWeekdays.contains(weekday)
                Button {
                    if isOn {
                        draft.scheduledWeekdays.removeAll { $0 == weekday }
                    } else {
                        draft.scheduledWeekdays.append(weekday)
                        draft.scheduledWeekdays.sort()
                    }
                } label: {
                    Text(shortSymbol(for: weekday))
                        .font(Theme.Typography.callout.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(isOn ? Color.white : Theme.Palette.textSecondary)
                        .background(Circle().fill(isOn ? Theme.Palette.accent : Theme.Palette.surfaceElevated))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(fullSymbol(for: weekday))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    // MARK: Logic

    /// Push-up consequence for skipping. Push-ups are currently the only camera-verified exercise.
    private var skipTarget: Binding<Int> {
        Binding(
            get: { draft.skipConsequence?.target ?? AccountabilityPlanner.fallbackConsequence.target },
            set: { draft.skipConsequence = AccountabilityTemplate(type: .pushUps, target: $0) }
        )
    }

    /// Habits in an active challenge keep their commitment fixed (also enforced by security rules).
    private var lockingChallenge: Challenge? {
        guard !isNew, let challengeId = draft.challengeId else { return nil }
        return store.challenges.first { $0.id == challengeId && $0.status == .active }
    }

    private var isCommitmentLocked: Bool { lockingChallenge != nil }
    private var lockingChallengeName: String { lockingChallenge?.name ?? "the challenge" }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && (draft.frequency != .custom || !draft.scheduledWeekdays.isEmpty)
    }

    private var targetRange: ClosedRange<Int> {
        switch draft.unit {
        case .sessions: return 1...14
        case .pages: return 5...2000
        case .minutes: return 5...600
        }
    }

    private var targetStep: Int { draft.unit == .sessions ? 1 : 5 }

    private func defaultTarget(for unit: HabitUnit) -> Int {
        switch unit {
        case .sessions: return 3
        case .pages: return 100
        case .minutes: return 30
        }
    }

    private var frequencyFooter: String {
        switch draft.frequency {
        case .daily: return "The target must be met every day."
        case .weekly: return "The target must be met each week, Monday to Sunday, on any days you choose."
        case .custom: return "The target must be met on each selected day."
        }
    }

    private func shortSymbol(for weekday: Int) -> String {
        store.calendar.veryShortStandaloneWeekdaySymbols[weekday - 1]
    }

    private func fullSymbol(for weekday: Int) -> String {
        store.calendar.standaloneWeekdaySymbols[weekday - 1]
    }

    private func save() {
        var habit = draft
        habit.startDate = DayKey(startDate, calendar: store.calendar)
        habit.endDate = hasEndDate ? DayKey(endDate, calendar: store.calendar) : nil
        if habit.frequency != .custom { habit.scheduledWeekdays = [] }
        do {
            try store.save(habit)
            dismiss()
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }

    private func archive() {
        do {
            try store.archive(draft)
            dismiss()
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}
