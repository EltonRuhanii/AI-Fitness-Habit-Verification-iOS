import FirebaseCore
import FirebaseFirestore

enum FirebaseBootstrap {
    /// Configures Firebase once. Only called in `.firebase` backend mode, i.e. when
    /// `GoogleService-Info.plist` is bundled (it is git-ignored and never committed).
    static func configure() {
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()

        // Persistent on-device cache: habits and progress remain readable offline and
        // writes are queued and synchronized when the connection returns.
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings
    }
}
