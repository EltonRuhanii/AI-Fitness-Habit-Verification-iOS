import SwiftUI

/// Explicit, informed agreement to the rules before any challenge starts. Each statement is
/// acknowledged separately rather than hidden behind a single "I agree".
struct RulesAcceptanceView: View {
    @Environment(SessionStore.self) private var session

    @State private var acceptsAccountability = false
    @State private var understandsAI = false
    @State private var consentsToResearch = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canContinue: Bool { acceptsAccountability && understandsAI && consentsToResearch && !isSaving }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Before you start")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("You set your own commitments. These are the rules you're agreeing to hold yourself to.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    AgreementRow(
                        isOn: $acceptsAccountability,
                        title: "Accountability",
                        text: "If I skip a habit, I'll complete the accountability task shown to me before I confirm the skip. If I don't, that day counts as unresolved and my streak may break.",
                        identifier: "rules.accountability"
                    )
                    AgreementRow(
                        isOn: $understandsAI,
                        title: "Automated verification",
                        text: "I understand that AI photo checks and camera rep counting are automated assessments against defined criteria. They can make mistakes and are not proof of what I did. My evidence photos are assessed by an external AI provider (Anthropic).",
                        identifier: "rules.ai"
                    )
                    AgreementRow(
                        isOn: $consentsToResearch,
                        title: "Research participation",
                        text: "I agree that pseudonymous data about my habit activity (no name, email or photos) may be used for university research on habit adherence. I can withdraw by deleting my account.",
                        identifier: "rules.research"
                    )
                }

                InlineMessage(text: "Accountability exercises are capped at safe limits. Stop any exercise that causes pain.", style: .info)

                if let errorMessage {
                    InlineMessage(text: errorMessage)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Agree and continue") {
                Task { await accept() }
            }
            .buttonStyle(.primary(isLoading: isSaving))
            .disabled(!canContinue)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Palette.background)
            .accessibilityIdentifier("rules.accept")
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func accept() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await session.completeOnboarding(researchConsent: consentsToResearch)
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}

private struct AgreementRow: View {
    @Binding var isOn: Bool
    let title: String
    let text: String
    let identifier: String

    var body: some View {
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.Palette.success : Theme.Palette.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(text)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .card()
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(isOn ? Theme.Palette.success.opacity(0.5) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}
