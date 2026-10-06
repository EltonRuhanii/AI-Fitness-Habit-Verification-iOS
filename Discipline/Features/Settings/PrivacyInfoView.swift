import SwiftUI
import DisciplineCore

/// Plain-language explanation of what is collected and why.
struct PrivacyInfoView: View {
    var body: some View {
        InfoPage(title: "How your data is used", sections: InfoSection.list([
            ("What's stored", "Your habits, when you complete or skip them, accountability tasks and exercise sessions (repetition counts, not video). Everything is private to your account."),
            ("Photos", "Evidence photos are downscaled and stripped of location data on your phone, then stored in private storage only your account can access. For assessment they're sent by our server to an external AI provider (Anthropic), which processes them under its API terms; they're never made public. You can delete them in Settings."),
            ("Exercise camera", "Repetition counting runs entirely on your phone. Video is never recorded or uploaded; only the number of repetitions, their timing and the measured angles or distances are stored. Face mode only detects where a face is in the picture to measure its size; it never recognises or identifies anyone."),
            ("Questionnaire", "Usability questionnaire answers are stored under your participant ID only, never your account."),
            ("Research", "If you consented, a nightly job creates daily summary records (counts only) under a random participant ID, for example \"P-7K2M9QX4RT\". They never contain your name, email, habit names or photos. Researchers only see these pseudonymous records and aggregates."),
            ("Your choices", "Delete your evidence photos in Settings, or delete your account to remove everything, including your research records.")
        ]))
    }
}

struct AIVerificationInfoView: View {
    var body: some View {
        InfoPage(title: "About AI verification", sections: InfoSection.list([
            ("What it does", "When a habit needs evidence, an AI model looks at your photo and answers specific yes/no questions for that habit's category, for example \"Is exercise equipment visible?\"."),
            ("How the result is decided", "The model doesn't decide by itself. A fixed rule does: if its confidence is below \(Int(VerificationCriteriaCatalog.bundled.defaultConfidenceThreshold * 100))%, the result is uncertain; otherwise it's verified only if every required question is answered yes."),
            ("What it can't do", "It can only judge what's visible in the photo. It can't prove you did the activity, and it can make mistakes. That's why results say the evidence \"satisfies the defined criteria\", not that you definitely did it."),
            ("Transparency", "Every result shows the questions, the confidence, the model's reason and which model produced it. All attempts are stored and never overwritten."),
            ("Exercise counting", "Push-ups are counted by your phone's camera with movement rules (depth and lockout, plus body alignment in side-view mode). Only repetitions meeting those rules count.")
        ]))
    }
}

private struct InfoSection: Identifiable {
    let heading: String
    let text: String
    var id: String { heading }

    static func list(_ pairs: [(String, String)]) -> [InfoSection] {
        pairs.map { InfoSection(heading: $0.0, text: $0.1) }
    }
}

private struct InfoPage: View {
    let title: String
    let sections: [InfoSection]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(section.heading)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(section.text)
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .card()
                }
            }
            .padding(Theme.Spacing.md)
        }
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
