import SwiftUI

struct MainTabView: View {
    enum Tab: Hashable { case today, progress, streak, profile }

    @State private var selection: Tab = .today

    var body: some View {
        TabView(selection: $selection) {
            DashboardView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(Tab.today)

            ProgressOverviewView()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                .tag(Tab.progress)

            StreakView()
                .tabItem { Label("Streak", systemImage: "flame.fill") }
                .tag(Tab.streak)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(Tab.profile)
        }
    }
}
