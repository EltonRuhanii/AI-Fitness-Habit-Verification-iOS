import SwiftUI
import DisciplineCore

/// The primary "complete" interaction for a habit, shared by the dashboard row and the detail
/// screen so the business rules live in one place.
///
/// - Sessions: confirm, then log.
/// - Pages/minutes: ask for the amount.
/// - Evidence required (AI-assisted condition): photo evidence + automated verification.
struct HabitActionModifier: ViewModifier {
    @Environment(HabitsStore.self) private var store
    @Environment(AppContainer.self) private var container
    @Binding var target: Habit?

    @State private var confirmingSession: Habit?
    @State private var quantityHabit: Habit?
    @State private var evidenceHabit: Habit?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: target) { _, habit in
                guard let habit else { return }
                target = nil
                route(habit)
            }
            .confirmationDialog(
                confirmingSession.map { "Mark \($0.name) as done today?" } ?? "",
                isPresented: Binding(get: { confirmingSession != nil }, set: { if !$0 { confirmingSession = nil } }),
                titleVisibility: .visible,
                presenting: confirmingSession
            ) { habit in
                Button("Mark as done") { perform { try store.logSelfReport(habit) } }
                    .accessibilityIdentifier("habit.confirmDone")
            } message: { _ in
                Text("This is recorded as a self-reported completion.")
            }
            .sheet(item: $quantityHabit) { habit in
                LogQuantitySheet(habit: habit) { amount in
                    perform { try store.logSelfReport(habit, quantity: amount) }
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $evidenceHabit) { habit in
                EvidenceCaptureSheet(habit: habit, store: store, container: container)
            }
            .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sensoryFeedback(.success, trigger: store.completionEvents)
    }

    private func route(_ habit: Habit) {
        if store.requirement(for: habit) == .evidence {
            evidenceHabit = habit
        } else if habit.unit == .sessions {
            confirmingSession = habit
        } else {
            quantityHabit = habit
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}

extension View {
    /// Attach once per screen; set `target` to a habit to start its completion flow.
    func habitCompletionFlow(target: Binding<Habit?>) -> some View {
        modifier(HabitActionModifier(target: target))
    }
}

struct LogQuantitySheet: View {
    let habit: Habit
    let onLog: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount: Int

    init(habit: Habit, onLog: @escaping (Int) -> Void) {
        self.habit = habit
        self.onLog = onLog
        _amount = State(initialValue: habit.unit == .pages ? 20 : 15)
    }

    private let step = 5

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.xs) {
                HabitIcon(category: habit.category, size: 52)
                Text("Log \(habit.name)")
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            .padding(.top, Theme.Spacing.lg)

            HStack(spacing: Theme.Spacing.lg) {
                stepButton("minus", delta: -step)
                VStack(spacing: 0) {
                    Text("\(amount)")
                        .font(Theme.Typography.metric)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .contentTransition(.numericText())
                    Text(habit.unit.displayName)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .frame(minWidth: 110)
                .accessibilityElement(children: .combine)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: change(by: step)
                    case .decrement: change(by: -step)
                    @unknown default: break
                    }
                }
                stepButton("plus", delta: step)
            }

            Spacer()

            Button("Log \(amount) \(habit.unit.displayName)") {
                onLog(amount)
                dismiss()
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("habit.logQuantity")
        }
        .padding(Theme.Spacing.lg)
        .screenBackground()
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        Button {
            change(by: delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .frame(width: 56, height: 56)
                .background(Circle().fill(Theme.Palette.surfaceElevated))
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .accessibilityLabel(delta > 0 ? "Increase" : "Decrease")
    }

    private func change(by delta: Int) {
        withAnimation(.snappy) {
            amount = min(1000, max(1, amount + delta))
        }
    }
}
