import Foundation
import Observation
import OSLog

/// Tracks writes that are saved locally but not yet acknowledged by the server, and the
/// most recent synchronization failure. Views show this so sync problems are never silent.
@MainActor
@Observable
final class SyncMonitor {
    private(set) var pendingWrites = 0
    private(set) var lastError: AppError?

    var isSyncing: Bool { pendingWrites > 0 }

    func writeStarted() {
        pendingWrites += 1
    }

    func writeFinished(error: Error?) {
        pendingWrites = max(0, pendingWrites - 1)
        if let error {
            let appError = AppError.from(error)
            lastError = appError
            Log.sync.error("Write failed: \(appError.localizedDescription, privacy: .public)")
        }
    }

    func dismissError() {
        lastError = nil
    }
}

enum Log {
    static let sync = Logger(subsystem: "com.eltonruhani.discipline", category: "sync")
    static let data = Logger(subsystem: "com.eltonruhani.discipline", category: "data")
}
