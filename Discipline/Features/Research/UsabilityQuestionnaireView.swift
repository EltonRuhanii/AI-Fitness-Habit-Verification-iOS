import SwiftUI
import DisciplineCore

/// The System Usability Scale questionnaire (thesis usability evaluation). Answers are stored
/// pseudonymously under the participant ID and can't be edited after submitting.
struct UsabilityQuestionnaireView: View {
    @Environment(SessionStore.self) private var session
    @Environment(HabitsStore.self) private var store
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var answers: [Int?] = Array(repeating: nil, count: SUSQuestionnaire.statements.count)
    @State private var submittedScore: Double?
    @State private var errorMessage: String?

    private let labels = ["Strongly disagree", "Disagree", "Neutral", "Agree", "Strongly agree"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if let submittedScore {
                    result(submittedScore)
                } else {
                    intro
                    ForEach(SUSQuestionnaire.statements.indices, id: \.self) { index in
                        question(index)
                    }
                    if let errorMessage { InlineMessage(text: errorMessage) }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .screenBackground()
        .navigationTitle("Usability questionnaire")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if submittedScore == nil {
                Button("Submit answers") { submit() }
                    .buttonStyle(.primary)
                    .disabled(answers.contains(nil))
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Palette.background)
                    .accessibilityIdentifier("sus.submit")
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("How usable is Discipline?")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Ten short statements (the System Usability Scale). Answer with your first reaction; there are no right answers. Your answers are stored under your participant ID only and can't be changed afterwards.")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
            Text("\(answers.compactMap { $0 }.count) of \(answers.count) answered")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    private func question(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("\(index + 1). \(SUSQuestionnaire.statements[index])")
                .font(Theme.Typography.callout.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(Array(SUSQuestionnaire.scale), id: \.self) { value in
                    let selected = answers[index] == value
                    Button {
                        answers[index] = value
                    } label: {
                        Text("\(value)")
                            .font(Theme.Typography.headline)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(selected ? Color.white : Theme.Palette.textPrimary)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .fill(selected ? Theme.Palette.accent : Theme.Palette.surfaceElevated))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(labels[value - 1])
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("sus.q\(index + 1).\(value)")
                }
            }
            HStack {
                Text(labels[0])
                Spacer()
                Text(labels[4])
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
        }
        .card()
    }

    private func result(_ score: Double) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Theme.Palette.success)
            Text("Thank you")
                .font(Theme.Typography.title)
            Text("Your SUS score: \(Int(score.rounded())) / 100 (\(SUSQuestionnaire.rating(for: score)))")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Palette.textSecondary)
                .accessibilityIdentifier("sus.score")
            Button("Done") { dismiss() }
                .buttonStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
    }

    private func submit() {
        guard let profile = session.profile else { return }
        let responses = answers.compactMap { $0 }
        guard let response = SUSResponse.make(participantId: profile.participantId, condition: profile.trackingCondition,
                                              responses: responses, challengeDay: store.challengeProgress?.dayNumber) else {
            errorMessage = "Answer all ten statements."
            return
        }
        do {
            try container.usability.submit(response)
            withAnimation(.snappy) { submittedScore = response.score }
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}
