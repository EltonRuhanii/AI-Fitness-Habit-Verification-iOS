import SwiftUI
import DisciplineCore

/// Shows a stored verification result, or re-runs verification for a pending submission.
struct VerificationDetailSheet: View {
    enum Source: Identifiable, Hashable {
        case stored(verificationId: String)
        case retry(evidenceId: String)

        var id: String {
            switch self {
            case .stored(let id): return "stored-\(id)"
            case .retry(let id): return "retry-\(id)"
            }
        }
    }

    let source: Source

    @Environment(AppContainer.self) private var container
    @Environment(HabitsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var result: VerificationResult?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let result {
                        VerificationResultView(result: result)
                    } else if let errorMessage {
                        InlineMessage(text: errorMessage)
                    } else {
                        HStack(spacing: Theme.Spacing.sm) {
                            ProgressView()
                            Text(loadingText)
                                .font(Theme.Typography.callout)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .card()
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .screenBackground()
            .navigationTitle("Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private var loadingText: String {
        if case .retry = source { return "Checking evidence against the criteria…" }
        return "Loading result…"
    }

    private func load() async {
        do {
            switch source {
            case .stored(let id):
                result = try await container.evidence.fetchVerification(id: id)
                if result == nil { errorMessage = "This verification result couldn't be found." }
            case .retry(let evidenceId):
                let fresh = try await container.verification.verify(evidenceId: evidenceId)
                result = fresh
                if fresh.status == .verified { store.noteCompletionEvent() }
            }
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}
