import SwiftUI

/// Phase 1 shell — the streak engine and calendar arrive in Phase 8.
struct StreakView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                systemImage: "flame.fill",
                title: "Your streak starts today",
                message: "Resolve every commitment due today and your streak begins. Each consecutive successful day adds one."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle("Streak")
        }
    }
}
