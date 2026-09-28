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

    init(configuration: AppConfiguration, auth: AuthenticationService, users: UserRepository) {
        self.configuration = configuration
        self.auth = auth
        self.users = users
    }

    static func live(configuration: AppConfiguration = .current) -> AppContainer {
        switch configuration.backend {
        case .firebase:
            FirebaseBootstrap.configure()
            return AppContainer(
                configuration: configuration,
                auth: FirebaseAuthenticationService(),
                users: FirestoreUserRepository()
            )
        case .demo:
            if configuration.resetLocalState {
                LocalJSONStore<Int>.removeAllDemoData()
                UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            }
            return AppContainer(
                configuration: configuration,
                auth: DemoAuthenticationService(),
                users: DemoUserRepository()
            )
        }
    }

    /// In-memory container for SwiftUI previews.
    static let preview: AppContainer = AppContainer(
        configuration: AppConfiguration(backend: .demo, seedDemoData: true, resetLocalState: false),
        auth: DemoAuthenticationService(defaults: UserDefaults(suiteName: "preview") ?? .standard),
        users: DemoUserRepository()
    )
}
