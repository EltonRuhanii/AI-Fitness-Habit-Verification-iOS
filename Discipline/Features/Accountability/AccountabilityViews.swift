import SwiftUI
import DisciplineCore

extension AccountabilityTaskStatus {
    var label: String {
        switch self {
        case .pending: return "Not started"
        case .inProgress: return "In progress"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .expired: return "Expired"
        }
    }

    var tint: Color {
        switch self {
        case .pending, .inProgress: return Theme.Palette.warning
        case .completed: return Theme.Palette.success
        case .failed, .expired: return Theme.Palette.danger
        }
    }
}

/// Dashboard card for an open task, with a live countdown and the Start action.
struct AccountabilityTaskCard: View {
    let task: AccountabilityTask
    let habitName: String?
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title.uppercased())
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let habitName {
                        Text("For skipping \(habitName)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Label(remaining(until: task.deadline, now: context.date), systemImage: "clock")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.warning)
                }
            }

            if task.progress > 0 {
                ProgressBar(fraction: Double(task.progress) / Double(max(task.target, 1)), tint: Theme.Palette.warning)
                Text("\(task.progress) / \(task.target) valid reps")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            Button(action: onStart) {
                Label(task.status == .inProgress ? "Continue" : "Start", systemImage: "camera.viewfinder")
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("accountability.start")
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.Palette.warning.opacity(0.45), lineWidth: 1.5)
        )
    }

    private func remaining(until deadline: Date, now: Date) -> String {
        let seconds = max(0, Int(deadline.timeIntervalSince(now)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m left" : "\(minutes)m left"
    }
}
