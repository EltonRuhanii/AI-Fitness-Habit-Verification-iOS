import SwiftUI
import DisciplineCore

struct MainTabView: View {
    enum Tab: Hashable { case today, progress, streak, profile }

    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab = .today
    @State private var habits: HabitsStore

    init(profile: UserProfile, container: AppContainer) {
        _habits = State(initialValue: HabitsStore(profile: profile, container: container))
    }

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
        .environment(habits)
        .onAppear { habits.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { habits.refreshToday() }
        }
    }
}
