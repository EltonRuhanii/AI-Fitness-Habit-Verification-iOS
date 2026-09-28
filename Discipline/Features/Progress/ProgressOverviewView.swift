import SwiftUI

/// Named `ProgressOverviewView` to avoid clashing with SwiftUI's `ProgressView`.
/// Phase 1 shell — analytics arrive in Phase 10/11.
struct ProgressOverviewView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                systemImage: "chart.bar.xaxis",
                title: "Progress will appear here",
                message: "Complete habits for a few days to see your completion rates, verification results and accountability history."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle("Progress")
        }
    }
}
