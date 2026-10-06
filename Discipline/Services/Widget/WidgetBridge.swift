import Foundation
import WidgetKit
import DisciplineCore

/// Publishes the home-screen widget's snapshot to the shared App Group and asks WidgetKit to
/// redraw. The widget never reads Firestore; it only renders what the app last wrote.
enum WidgetBridge {
    static let kind = "DisciplineWidget"

    static func publish(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: WidgetSnapshot.storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    /// Signing out: the widget must not keep showing the previous account's activities.
    static func clear() {
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.removeObject(forKey: WidgetSnapshot.storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
