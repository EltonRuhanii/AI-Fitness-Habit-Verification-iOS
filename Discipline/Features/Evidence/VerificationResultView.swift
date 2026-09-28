import SwiftUI
import DisciplineCore

/// Presents one verification result transparently: outcome, confidence vs. threshold, each
/// criterion, the model's stated reason, and provenance. Wording avoids claiming proof.
struct VerificationResultView: View {
    let result: VerificationResult

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            if let confidence = result.confidence {
                confidenceCard(confidence)
            }
            if !result.criteria.isEmpty {
                criteriaCard
            }
            if !result.reason.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    SectionEyebrow(title: result.status == .error ? "What happened" : "Assessment")
                    Text(result.reason)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !result.flags.isEmpty {
                        Text("Flags: " + result.flags.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", "))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                }
                .card()
            }
            provenance
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(Circle().fill(tint.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(explanation)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func confidenceCard(_ confidence: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                SectionEyebrow(title: "Confidence")
                Spacer()
                Text("\(percent(confidence)) · threshold \(percent(result.confidenceThreshold))")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    ProgressBar(fraction: confidence, tint: confidence >= result.confidenceThreshold ? Theme.Palette.success : Theme.Palette.warning)
                    Rectangle()
                        .fill(Theme.Palette.textPrimary.opacity(0.6))
                        .frame(width: 2, height: 14)
                        .offset(x: proxy.size.width * result.confidenceThreshold - 1)
                }
            }
            .frame(height: 14)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Confidence \(percent(confidence)), threshold \(percent(result.confidenceThreshold))")
    }

    private var criteriaCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "Criteria")
            ForEach(result.criteria, id: \.criterionId) { criterion in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: criterion.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(criterion.passed ? Theme.Palette.success : Theme.Palette.danger)
                    Text(criterion.name)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(criterion.name): \(criterion.passed ? "met" : "not met")")
            }
        }
        .card()
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Automated assessment. It can be wrong and is not proof of what happened.")
            Text("\(result.provider) · \(result.model) · \(result.promptVersion) · \(result.processingTimeMs) ms")
                .font(.system(.caption2, design: .monospaced))
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Palette.textTertiary)
    }

    // MARK: Wording

    private var title: String {
        switch result.status {
        case .verified: return "Evidence verified"
        case .rejected: return "Evidence not accepted"
        case .uncertain: return "Couldn't decide"
        case .error: return "Verification failed"
        case .pending: return "Checking…"
        }
    }

    private var explanation: String {
        switch result.status {
        case .verified:
            return "AI verification indicates that the submitted evidence satisfies the defined criteria."
        case .rejected:
            return "AI verification indicates that the evidence does not satisfy all required criteria. You can submit a new photo."
        case .uncertain:
            return "The assessment didn't reach the required confidence, so it was recorded as uncertain rather than guessed."
        case .error:
            return "No assessment was made. Your submission is saved; you can retry verification."
        case .pending:
            return "Your evidence is being assessed."
        }
    }

    private var symbol: String {
        switch result.status {
        case .verified: return "checkmark.seal.fill"
        case .rejected: return "xmark.octagon.fill"
        case .uncertain: return "questionmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .pending: return "hourglass"
        }
    }

    private var tint: Color {
        switch result.status {
        case .verified: return Theme.Palette.success
        case .rejected, .error: return Theme.Palette.danger
        case .uncertain: return Theme.Palette.warning
        case .pending: return Theme.Palette.info
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
