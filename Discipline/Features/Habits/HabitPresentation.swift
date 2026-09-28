import SwiftUI
import DisciplineCore

extension CompletionStatus {
    /// Wording follows the rule that verification is an assessment against criteria, not proof.
    var label: String {
        switch self {
        case .pending: return "Pending"
        case .selfReported: return "Completed"
        case .pendingVerification: return "Checking evidence"
        case .verified: return "Verified"
        case .rejected: return "Evidence not accepted"
        case .uncertain: return "Uncertain"
        case .skipped: return "Skipped"
        case .accountabilityRequired: return "Accountability due"
        case .resolved: return "Resolved"
        case .failed: return "Missed"
        }
    }

    var symbolName: String {
        switch self {
        case .pending: return "circle"
        case .selfReported: return "checkmark.circle.fill"
        case .pendingVerification: return "hourglass"
        case .verified: return "checkmark.seal.fill"
        case .rejected: return "xmark.octagon.fill"
        case .uncertain: return "questionmark.circle.fill"
        case .skipped: return "arrow.uturn.forward.circle"
        case .accountabilityRequired: return "figure.strengthtraining.traditional"
        case .resolved: return "checkmark.shield.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .selfReported, .verified, .resolved: return Theme.Palette.success
        case .pendingVerification, .pending: return Theme.Palette.info
        case .uncertain, .skipped, .accountabilityRequired: return Theme.Palette.warning
        case .rejected, .failed: return Theme.Palette.danger
        }
    }
}

struct StatusBadge: View {
    let status: CompletionStatus

    var body: some View {
        Label(status.label, systemImage: status.symbolName)
            .font(Theme.Typography.caption)
            .foregroundStyle(status.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(status.tint.opacity(0.14)))
    }
}

/// Rounded-square category icon used in rows and headers.
struct HabitIcon: View {
    let category: HabitCategory
    var size: CGFloat = 44
    var isComplete = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(isComplete ? AnyShapeStyle(Theme.Palette.success.opacity(0.18)) : AnyShapeStyle(Theme.Palette.accent.opacity(0.14)))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: category.symbolName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(isComplete ? AnyShapeStyle(Theme.Palette.success) : AnyShapeStyle(Theme.Palette.emberGradient))
            )
            .accessibilityHidden(true)
    }
}

struct ProgressBar: View {
    let fraction: Double
    var tint: Color = Theme.Palette.accent
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.surfaceElevated)
                Capsule()
                    .fill(tint)
                    .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: fraction)
        .accessibilityHidden(true)
    }
}

extension Habit {
    /// "4x / week · Photo evidence"
    var summaryLine: String {
        var parts = [targetDescription]
        if requiresEvidence { parts.append("Photo evidence") }
        if !isRequired { parts.append("Optional") }
        return parts.joined(separator: " · ")
    }

    func formatted(_ amount: Int) -> String {
        unit == .sessions ? "\(amount)" : "\(amount) \(unit.displayName)"
    }
}
