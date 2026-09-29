import Foundation
import DisciplineCore

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
    /// Loads generated demo history after the first sign-in (demo mode only).
    let seedDemoData: Bool
    /// Starts from a clean slate — used by UI tests so runs are deterministic.
    let resetLocalState: Bool
    /// UI-test mode (demo only): sample photo instead of the camera, stub verifier, and a
    /// scripted pose source instead of the exercise camera.
    let isUITesting: Bool
    /// Demo only: fixes the experimental condition (UI tests need a known condition).
    let forcedCondition: TrackingCondition?

    init(backend: BackendMode, seedDemoData: Bool, resetLocalState: Bool,
         isUITesting: Bool = false, forcedCondition: TrackingCondition? = nil) {
        self.backend = backend
        self.seedDemoData = seedDemoData
        self.resetLocalState = resetLocalState
        self.isUITesting = isUITesting && backend == .demo
        self.forcedCondition = backend == .demo ? forcedCondition : nil
    }

    static let current = AppConfiguration.detect()

    private static func detect(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        bundle: Bundle = .main
    ) -> AppConfiguration {
        let forceDemo = arguments.contains("-demoMode") || arguments.contains("-uiTesting")
        let hasFirebaseConfig = bundle.path(forResource: "GoogleService-Info", ofType: "plist") != nil
        let backend: BackendMode = (!forceDemo && hasFirebaseConfig) ? .firebase : .demo
        let forced = arguments.firstIndex(of: "-forceCondition")
            .flatMap { arguments.indices.contains($0 + 1) ? TrackingCondition(rawValue: arguments[$0 + 1]) : nil }
        return AppConfiguration(
            backend: backend,
            seedDemoData: arguments.contains("-seedDemoData"),
            resetLocalState: arguments.contains("-resetLocalState"),
            isUITesting: arguments.contains("-uiTesting"),
            forcedCondition: forced
        )
    }
}
