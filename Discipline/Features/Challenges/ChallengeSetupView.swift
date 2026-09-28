import SwiftUI
import DisciplineCore

/// Creates a challenge from the 75-day template or from scratch. The participant configures
/// the rules they'll hold themselves to and explicitly accepts them before starting.
struct ChallengeSetupView: View {
    enum Kind: Hashable {
        case discipline75
        case custom
    }

    let kind: Kind

    @Environment(HabitsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var durationDays: Int
    @State private var startsTomorrow = false
    @State private var rules = ChallengeRules()
    @State private var skipPushUps = 50
    @State private var selectedHabitIds: Set<String> = []
    @State private var acceptsRules = false
    @State private var errorMessage: String?

    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .discipline75:
            _name = State(initialValue: "75 Day Discipline")
            _description = State(initialValue: ChallengeTemplates.discipline75Description)
            _durationDays = State(initialValue: 75)
        case .custom:
            _name = State(initialValue: "")
            _description = State(initialValue: "")
            _durationDays = State(initialValue: 30)
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Challenge name", text: $name)
                    .font(Theme.Typography.headline)
                    .accessibilityIdentifier("challenge.name")
                TextField("Description (optional)", text: $description, axis: .vertical)
                    .lineLimit(1...4)
                Stepper(value: $durationDays, in: ChallengePlanner.durationRange) {
                    LabeledContent("Duration", value: "\(durationDays) days")
                }
                Toggle("Start tomorrow", isOn: $startsTomorrow)
            } footer: {
                Text("Runs \(startDay.startDate(calendar: store.calendar).formatted(date: .abbreviated, time: .omitted)) – \(endDay.startDate(calendar: store.calendar).formatted(date: .abbreviated, time: .omitted)).")
            }

            habitsSection
            rulesSection
            studySection
            acceptanceSection

            if let errorMessage {
                Section {
                    InlineMessage(text: errorMessage)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(kind == .discipline75 ? "75 Day Discipline" : "Custom challenge")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("Start challenge") { start() }
                .buttonStyle(.primary)
                .disabled(!acceptsRules || name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Palette.background)
                .accessibilityIdentifier("challenge.start")
        }
        .onAppear {
            if kind == .custom && selectedHabitIds.isEmpty {
                selectedHabitIds = Set(adoptableHabits.map(\.id))
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var habitsSection: some View {
        Section {
            switch kind {
            case .discipline75:
                ForEach(templateHabits, id: \.name) { habit in
                    habitRow(habit)
                }
            case .custom:
                if adoptableHabits.isEmpty {
                    Text("Create some habits first. They become the challenge's commitments.")
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    ForEach(adoptableHabits) { habit in
                        Button {
                            if selectedHabitIds.contains(habit.id) {
                                selectedHabitIds.remove(habit.id)
                            } else {
                                selectedHabitIds.insert(habit.id)
                            }
                        } label: {
                            HStack {
                                habitRow(habit)
                                Spacer()
                                Image(systemName: selectedHabitIds.contains(habit.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedHabitIds.contains(habit.id) ? Theme.Palette.accent : Theme.Palette.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedHabitIds.contains(habit.id) ? .isSelected : [])
                    }
                }
            }
        } header: {
            Text("Commitments")
        } footer: {
            Text(kind == .discipline75
                 ? "These habits are created for the challenge and end with it."
                 : "Selected habits become part of the challenge. Only challenge habits count toward its streak.")
        }
    }

    private func habitRow(_ habit: Habit) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            HabitIcon(category: habit.category, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name).font(Theme.Typography.callout.weight(.semibold))
                Text(habit.summaryLine).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private var rulesSection: some View {
        Section {
            Toggle("Track a streak", isOn: $rules.streakEnabled)
            Toggle("Every commitment required each day", isOn: $rules.requireAllHabits)
            Toggle("Allow skipping", isOn: $rules.allowSkipping)
            if rules.allowSkipping {
                Stepper(value: $skipPushUps, in: 10...100, step: 5) {
                    LabeledContent("Default skip consequence", value: "\(skipPushUps) push-ups")
                }
            }
            Picker("Missed day", selection: $rules.missedDayBehavior) {
                Text("Breaks the streak").tag(MissedDayBehavior.breakStreak)
                Text("Pauses the streak").tag(MissedDayBehavior.pauseStreak)
            }
            Picker("Uncertain AI result", selection: $rules.uncertainPolicy) {
                Text("Counts").tag(UncertainVerificationPolicy.countsAsResolved)
                Text("Resubmit needed").tag(UncertainVerificationPolicy.requiresResubmission)
            }
        } header: {
            Text("Your rules")
        } footer: {
            Text("Skipping creates the accountability task shown before you confirm each skip. Habits with their own consequence keep it.")
        }
    }

    private var studySection: some View {
        Section {
            lockedRow("AI photo verification", value: rules.aiVerificationEnabled ? "On" : "Off")
            lockedRow("Camera exercise verification", value: rules.exerciseVerificationEnabled ? "On" : "Off")
            lockedRow("AI confidence threshold", value: "\(Int((rules.confidenceThreshold * 100).rounded()))%")
        } header: {
            Text("Set by the study")
        } footer: {
            Text("These parameters are the same for every participant so results can be compared.")
        }
    }

    private func lockedRow(_ title: String, value: String) -> some View {
        LabeledContent {
            Label(value, systemImage: "lock.fill")
                .foregroundStyle(Theme.Palette.textSecondary)
        } label: {
            Text(title)
        }
    }

    private var acceptanceSection: some View {
        Section {
            Button {
                withAnimation(.snappy) { acceptsRules.toggle() }
            } label: {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: acceptsRules ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(acceptsRules ? Theme.Palette.success : Theme.Palette.textTertiary)
                    Text("I accept these rules for the whole challenge. They can't be changed once it starts.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(acceptsRules ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("challenge.accept")
        }
    }

    // MARK: Data

    private var startDay: DayKey { startsTomorrow ? store.today.adding(days: 1, calendar: store.calendar) : store.today }
    private var endDay: DayKey { startDay.adding(days: durationDays - 1, calendar: store.calendar) }

    private var templateHabits: [Habit] {
        ChallengeTemplates.discipline75Habits(userId: store.userId, startDate: startDay)
    }

    /// Active habits not already part of another challenge.
    private var adoptableHabits: [Habit] {
        store.activeHabits.filter { habit in
            guard let challengeId = habit.challengeId else { return true }
            return !store.challenges.contains { $0.id == challengeId && $0.status == .active }
        }
    }

    private func start() {
        var finalRules = rules
        finalRules.defaultSkipConsequence = rules.allowSkipping ? AccountabilityTemplate(type: .pushUps, target: skipPushUps) : nil
        do {
            let plan = try ChallengePlanner.plan(
                name: name,
                description: description,
                durationDays: durationDays,
                startDate: startDay,
                rules: finalRules,
                ownerId: store.userId,
                newHabits: kind == .discipline75 ? templateHabits : [],
                adoptedHabits: kind == .custom ? adoptableHabits.filter { selectedHabitIds.contains($0.id) } : [],
                existingChallenges: store.challenges,
                rulesAccepted: acceptsRules,
                today: store.today,
                templateId: kind == .discipline75 ? ChallengeTemplates.discipline75Id : nil,
                calendar: store.calendar
            )
            try store.startChallenge(plan)
            dismiss()
        } catch let error as ChallengePlanError {
            errorMessage = error.message
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}

extension ChallengePlanError {
    var message: String {
        switch self {
        case .emptyName: return "Give your challenge a name."
        case .invalidDuration: return "Choose a duration between 7 and 365 days."
        case .rulesNotAccepted: return "Accept the rules to start the challenge."
        case .noHabits: return "Choose at least one habit for the challenge."
        case .alreadyActive: return "You already have a challenge in progress."
        case .startInPast: return "A challenge can't start in the past."
        }
    }
}
