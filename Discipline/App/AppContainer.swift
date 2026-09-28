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
    let accountability: AccountabilityRepository
    let exerciseSessions: ExerciseSessionRepository
    let challenges: ChallengeRepository
    let evidence: EvidenceService
    let verification: AIVerificationService
    let sync: SyncMonitor
    let notifications = NotificationScheduler()
    let notificationPreferences = NotificationPreferencesStore()
    let connectivity = ConnectivityMonitor()

    init(
        configuration: AppConfiguration,
        auth: AuthenticationService,
        users: UserRepository,
        habits: HabitRepository,
        completions: CompletionRepository,
        accountability: AccountabilityRepository,
        exerciseSessions: ExerciseSessionRepository,
        challenges: ChallengeRepository,
        evidence: EvidenceService,
        verification: AIVerificationService,
        sync: SyncMonitor
    ) {
        self.configuration = configuration
        self.auth = auth
        self.users = users
        self.habits = habits
        self.completions = completions
        self.accountability = accountability
        self.exerciseSessions = exerciseSessions
        self.challenges = challenges
        self.evidence = evidence
        self.verification = verification
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
                accountability: FirestoreAccountabilityRepository(monitor: sync),
                exerciseSessions: FirestoreExerciseSessionRepository(monitor: sync),
                challenges: FirestoreChallengeRepository(monitor: sync),
                evidence: FirebaseEvidenceService(),
                verification: FirebaseVerificationService(),
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
        let habits = DemoHabitRepository()
        let completions = DemoCompletionRepository()
        let evidenceBackend = DemoEvidenceBackend(completions: completions, habits: habits)
        let accountability = DemoAccountabilityRepository(completions: completions)
        return AppContainer(
            configuration: configuration,
            auth: DemoAuthenticationService(defaults: defaults),
            users: DemoUserRepository(),
            habits: habits,
            completions: completions,
            accountability: accountability,
            exerciseSessions: DemoExerciseSessionRepository(accountability: accountability),
            challenges: DemoChallengeRepository(),
            evidence: evidenceBackend,
            verification: evidenceBackend,
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
