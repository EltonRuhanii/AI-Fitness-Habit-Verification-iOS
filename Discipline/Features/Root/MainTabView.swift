import SwiftUI
import DisciplineCore

struct MainTabView: View {
    enum Tab: Hashable { case today, progress, streak, profile }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppContainer.self) private var container
    @State private var selection: Tab = .today
    @State private var habits: HabitsStore
    @State private var isSeedingDemo: Bool

    init(profile: UserProfile, container: AppContainer) {
        _habits = State(initialValue: HabitsStore(profile: profile, container: container))
        _isSeedingDemo = State(initialValue: container.configuration.seedDemoData)
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
        .fullScreenCover(isPresented: needsSetup) {
            RoutineSetupView()
                .environment(habits)
        }
        .onAppear { habits.start() }
        .task {
            // `-seedDemoData`: fill a fresh demo account (no challenge yet) once its data has loaded.
            guard isSeedingDemo else { return }
            try? await Task.sleep(for: .seconds(1))
            if habits.needsChallengeSetup { _ = try? DemoSeeder.seed(container: container, store: habits) }
            try? await Task.sleep(for: .milliseconds(500))
            isSeedingDemo = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { habits.refreshToday() }
        }
    }

    /// The app only runs in challenge mode: without a challenge, setup covers everything.
    private var needsSetup: Binding<Bool> {
        Binding(get: { !isSeedingDemo && habits.needsChallengeSetup }, set: { _ in })
    }
}
