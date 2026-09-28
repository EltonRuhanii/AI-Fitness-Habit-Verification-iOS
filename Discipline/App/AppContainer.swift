import Foundation
import Observation

/// Composition root. Every service is created here and injected into view models, so
/// Firebase and demo implementations are interchangeable and features stay testable.
@MainActor
@Observable
final class AppContainer {
    let configuration: AppConfiguration
    let auth: AuthenticationService
    let users: UserRepository
    let habits: HabitRepository
    let completions: CompletionRepository
    let sync: SyncMonitor

    init(
        configuration: AppConfiguration,
        auth: AuthenticationService,
        users: UserRepository,
        habits: HabitRepository,
        completions: CompletionRepository,
        sync: SyncMonitor
    ) {
        self.configuration = configuration
        self.auth = auth
        self.users = users
        self.habits = habits
        self.completions = completions
        self.sync = sync
    }

    static func live(configuration: AppConfiguration = .current) -> AppContainer {
        let sync = SyncMonitor()
        switch configuration.backend {
        case .firebase:
            FirebaseBootstrap.configure()
            return AppContainer(
                configuration: configuration,
                auth: FirebaseAuthenticationService(),
                users: FirestoreUserRepository(),
                habits: FirestoreHabitRepository(monitor: sync),
                completions: FirestoreCompletionRepository(monitor: sync),
                sync: sync
            )
        case .demo:
            if configuration.resetLocalState {
                LocalJSONStore<Int>.removeAllDemoData()
                UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            }
            return demo(configuration: configuration, sync: sync)
        }
    }

    private static func demo(configuration: AppConfiguration, sync: SyncMonitor, defaults: UserDefaults = .standard) -> AppContainer {
        AppContainer(
            configuration: configuration,
            auth: DemoAuthenticationService(defaults: defaults),
            users: DemoUserRepository(),
            habits: DemoHabitRepository(),
            completions: DemoCompletionRepository(),
            sync: sync
        )
    }

    /// Container for SwiftUI previews.
    static let preview: AppContainer = demo(
        configuration: AppConfiguration(backend: .demo, seedDemoData: true, resetLocalState: false),
        sync: SyncMonitor(),
        defaults: UserDefaults(suiteName: "preview") ?? .standard
    )
}
