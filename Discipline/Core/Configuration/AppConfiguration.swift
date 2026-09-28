import Foundation

/// Which backend the app talks to.
enum BackendMode: Equatable {
    /// Firebase Auth/Firestore/Storage/Functions. Requires `GoogleService-Info.plist` in the bundle.
    case firebase
    /// Local, on-device services with no network. Used for UI tests, previews, and running
    /// the app before Firebase is configured. Data is clearly separated from production.
    case demo
}

struct AppConfiguration {
    let backend: BackendMode
    /// Pre-populates demo data (several weeks of history) in demo mode.
    let seedDemoData: Bool
    /// Starts from a clean slate — used by UI tests so runs are deterministic.
    let resetLocalState: Bool

    static let current = AppConfiguration.detect()

    private static func detect(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        bundle: Bundle = .main
    ) -> AppConfiguration {
        let forceDemo = arguments.contains("-demoMode")
        let hasFirebaseConfig = bundle.path(forResource: "GoogleService-Info", ofType: "plist") != nil
        let backend: BackendMode = (!forceDemo && hasFirebaseConfig) ? .firebase : .demo
        return AppConfiguration(
            backend: backend,
            seedDemoData: arguments.contains("-seedDemoData"),
            resetLocalState: arguments.contains("-resetLocalState")
        )
    }
}
