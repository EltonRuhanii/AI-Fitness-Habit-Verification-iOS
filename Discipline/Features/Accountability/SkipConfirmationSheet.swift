import SwiftUI
import DisciplineCore

/// Explicit consent to a pre-agreed consequence. Nothing is recorded until "Accept";
/// "Go back" leaves no trace in the data.
struct SkipConfirmationSheet: View {
    let habit: Habit

    @Environment(HabitsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("SKIP CONFIRMATION")
                            .font(Theme.Typography.eyebrow)
                            .tracking(1.2)
                            .foregroundStyle(Theme.Palette.warning)
                        Text("Skip \(habit.name) today?")
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text("Skipping creates an accountability task. Complete it before the deadline and today still counts. If you don't, this commitment is marked as missed.")
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let consequence = store.skipConsequence(for: habit) {
                        consequenceCard(consequence)
                    }

                    InlineMessage(text: "Only skip if you're able to do this safely. Stop any exercise that causes pain.", style: .info)

                    if let errorMessage {
                        InlineMessage(text: errorMessage)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .screenBackground()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.Spacing.sm) {
                    Button("Accept task") { accept() }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("skip.accept")
                    Button("Go back") { dismiss() }
                        .buttonStyle(.secondary)
                        .accessibilityIdentifier("skip.cancel")
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Palette.background)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func consequenceCard(_ consequence: AccountabilityTemplate) -> some View {
        let deadline = Date().addingTimeInterval(TimeInterval(consequence.deadlineHours) * 3600)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "Your accountability task")
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text("\(consequence.target)")
                    .font(Theme.Typography.metric)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(consequence.type.displayName.uppercased())
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.accent)
            }
            Label("Due by \(deadline.formatted(.dateTime.weekday(.abbreviated).hour().minute()))", systemImage: "clock")
            if consequence.type.isCameraVerified {
                Label("Counted by your camera, on this device", systemImage: "camera.viewfinder")
            }
        }
        .font(Theme.Typography.callout)
        .foregroundStyle(Theme.Palette.textSecondary)
        .card()
        .accessibilityElement(children: .combine)
    }

    private func accept() {
        do {
            try store.acceptSkip(habit)
            dismiss()
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}
