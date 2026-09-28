import Foundation

struct OnboardingPage: Identifiable, Hashable {
    let id: Int
    let systemImage: String
    let eyebrow: String
    let title: String
    let body: String
    var points: [String] = []
}

/// Onboarding copy. Wording follows the project's rule that verification is described as
/// an automated assessment against defined criteria — never as proof.
enum OnboardingContent {
    static let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            systemImage: "flame.fill",
            eyebrow: "Welcome",
            title: "Commitments you actually keep",
            body: "Discipline helps you set fitness and lifestyle commitments, follow through on them, and see honestly how consistent you've been."
        ),
        OnboardingPage(
            id: 1,
            systemImage: "checklist",
            eyebrow: "Habits",
            title: "Habits are your commitments",
            body: "A habit is something you commit to on a schedule.",
            points: ["Gym — 4× per week", "Running — 2× per week", "Reading — 100 pages per week", "Cold plunge — 3× per week"]
        ),
        OnboardingPage(
            id: 2,
            systemImage: "calendar.badge.checkmark",
            eyebrow: "Streaks",
            title: "Every resolved day counts",
            body: "A day is successful when every commitment due that day is resolved — completed, or skipped with its accountability task done. Consecutive successful days build your streak. An unresolved day breaks it."
        ),
        OnboardingPage(
            id: 3,
            systemImage: "camera.viewfinder",
            eyebrow: "Evidence",
            title: "Show your work",
            body: "Some habits ask for a photo as evidence — for example your gym, your book, or your cold-plunge setup. You can take a photo or choose one from your library, preview it, and retake it before submitting."
        ),
        OnboardingPage(
            id: 4,
            systemImage: "arrow.uturn.forward.circle.fill",
            eyebrow: "Skipping",
            title: "Skipping is allowed — on your terms",
            body: "Life happens. You can deliberately skip a habit instead of silently missing it. Skipping creates an accountability task that you agreed to in advance.",
            points: ["You see the task before confirming", "You can go back instead", "Consequences stay within safe limits"]
        ),
        OnboardingPage(
            id: 5,
            systemImage: "figure.strengthtraining.traditional",
            eyebrow: "Accountability",
            title: "Earn the day back",
            body: "An accountability task — like 50 push-ups — resolves a skipped commitment. Complete it before its deadline and your day still counts. Leave it unfinished and the day is unresolved."
        ),
        OnboardingPage(
            id: 6,
            systemImage: "figure.cooldown",
            eyebrow: "Exercise verification",
            title: "Your camera counts the reps",
            body: "For exercise tasks, the camera tracks body landmarks on your device and counts repetitions that meet defined movement criteria — lowering far enough and returning to the top. Partial reps don't count.",
            points: ["Runs entirely on your iPhone", "Video is never recorded or uploaded", "Only rep counts and timestamps are stored"]
        ),
        OnboardingPage(
            id: 7,
            systemImage: "sparkle.magnifyingglass",
            eyebrow: "About AI verification",
            title: "An assessment, not proof",
            body: "Evidence photos are checked by an AI model against specific criteria for each habit — for example \"Is exercise equipment visible?\". The result is verified, rejected, or uncertain, with a confidence score and a reason.",
            points: ["AI can make mistakes", "Low confidence is reported as uncertain", "Every result is stored and can be reviewed"]
        ),
        OnboardingPage(
            id: 8,
            systemImage: "lock.shield.fill",
            eyebrow: "Your photos",
            title: "How your photos are handled",
            body: "Evidence photos are uploaded to private storage that only your account can access, sent securely to the verification service, and never made public. You can delete your evidence or your whole account at any time.",
            points: ["Research data uses a random participant ID", "No names or emails in research exports", "Delete your data from Settings"]
        )
    ]
}
